import Foundation
import SVNCore
import Testing
@testable import SVNMac

@Test @MainActor func legacyUntrustedCertificateSettingMigratesWithoutDroppingProjects() throws {
    let suiteName = "ServerCertificateTrustTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let projectID = UUID()
    let legacyData = Data(
        """
        [{
          "id": "\(projectID.uuidString)",
          "name": "Legacy",
          "path": "/tmp/legacy",
          "username": "office.user",
          "allowsUntrustedServerCertificate": true
        }]
        """.utf8
    )
    defaults.set(legacyData, forKey: "legacy-projects")

    let persistence = UserDefaultsProjectPersistence(
        defaults: defaults,
        key: "legacy-projects"
    )
    let projects = persistence.loadProjects()
    let project = try #require(projects.first)
    let store = ProjectStore(
        persistence: persistence,
        updateBadgeRefreshInterval: nil
    )

    #expect(projects.count == 1)
    #expect(project.id == projectID)
    #expect(project.name == "Legacy")
    #expect(store.allowedServerCertificateFailures(for: project) == [
        .unknownCertificateAuthority,
        .commonNameMismatch,
    ])
    let reloadedProject = try #require(persistence.loadProjects().first)
    #expect(reloadedProject.id == projectID)
    #expect(store.allowedServerCertificateFailures(for: reloadedProject) == [
        .unknownCertificateAuthority,
        .commonNameMismatch,
    ])
}

@Test func classifiesCertificateFailureReasonsFromSubversionStderr() {
    let failures: [(String, SVNServerCertificateFailure)] = [
        ("certificate has expired", .expired),
        ("certificate is not yet valid", .notYetValid),
        ("issuer is not trusted", .unknownCertificateAuthority),
        ("certificate issued for a different hostname", .commonNameMismatch),
    ]

    for (reason, expectedFailure) in failures {
        let error = SVNError.commandFailed(
            command: "svn log",
            message: "svn: E230001: Server SSL certificate verification failed: \(reason)"
        )
        #expect(SVNErrorLocalization.serverCertificateFailure(for: error) == expectedFailure)
    }

    let unclassifiedError = SVNError.commandFailed(
        command: "svn log",
        message: "svn: E230001: Server SSL certificate verification failed"
    )
    #expect(SVNErrorLocalization.serverCertificateFailure(for: unclassifiedError) == .other)
    #expect(SVNErrorLocalization.serverCertificateFailure(for: SVNError.invalidWorkingCopy) == nil)
    #expect(
        SVNErrorLocalization.message(for: unclassifiedError, language: .english)
            .contains("did not identify a supported reason")
    )
}

@Test @MainActor func expiredCertificateRequiresConsentThenAppliesOnlyToRequestedProject() throws {
    let firstProject = SVNProject(name: "First", path: "/tmp/first")
    let secondProject = SVNProject(name: "Second", path: "/tmp/second")
    let persistence = CertificateProjectPersistence(projects: [firstProject, secondProject])
    let store = ProjectStore(
        persistence: persistence,
        updateBadgeRefreshInterval: nil
    )
    store.selectedProjectID = firstProject.id
    let error = SVNError.commandFailed(
        command: "svn update",
        message: "svn: E175002: Server SSL certificate verification failed: certificate has expired"
    )

    store.handleRemoteError(error, project: firstProject, action: .update)

    let request = try #require(store.authenticationRequest)
    #expect(request.serverCertificateTrust?.failure == .expired)
    #expect(request.serverCertificateTrust?.canAllow == true)
    #expect(!store.allowedServerCertificateFailures(for: firstProject).contains(.expired))
    #expect(!store.allowedServerCertificateFailures(for: secondProject).contains(.expired))

    store.allowServerCertificateFailure(for: request)

    let updatedFirstProject = try #require(store.projects.first { $0.id == firstProject.id })
    let unchangedSecondProject = try #require(store.projects.first { $0.id == secondProject.id })
    #expect(store.authenticationRequest == nil)
    #expect(store.allowedServerCertificateFailures(for: updatedFirstProject).contains(.expired))
    #expect(!store.allowedServerCertificateFailures(for: unchangedSecondProject).contains(.expired))
    #expect(persistence.savedProjects.last?.first?.allowedServerCertificateFailures.contains(.expired) == true)
}

@Test @MainActor func disablingLegacyToggleRemovesOnlyLegacyCertificateFailures() throws {
    let project = SVNProject(
        name: "Project",
        path: "/tmp/project",
        allowsUntrustedServerCertificate: true,
        allowedServerCertificateFailures: [.expired]
    )
    let store = ProjectStore(
        persistence: CertificateProjectPersistence(projects: [project]),
        updateBadgeRefreshInterval: nil
    )

    let didSave = store.saveCredentials(
        for: project.id,
        username: "",
        newPassword: "",
        allowsUntrustedServerCertificate: false
    )

    let updatedProject = try #require(store.projects.first)
    #expect(didSave)
    #expect(store.allowedServerCertificateFailures(for: updatedProject) == [.expired])
}

@Test @MainActor func unclassifiedCertificateFailureExplainsProblemWithoutBroadConsent() throws {
    let project = SVNProject(name: "Project", path: "/tmp/project")
    let store = ProjectStore(
        persistence: CertificateProjectPersistence(projects: [project]),
        updateBadgeRefreshInterval: nil
    )
    store.selectedProjectID = project.id
    let error = SVNError.commandFailed(
        command: "svn log",
        message: "svn: E230001: Server SSL certificate verification failed"
    )

    store.handleRemoteError(error, project: project, action: .refreshHistory)

    let request = try #require(store.authenticationRequest)
    #expect(request.serverCertificateTrust?.failure == .other)
    #expect(request.serverCertificateTrust?.canAllow == false)
    store.allowServerCertificateFailure(for: request)
    #expect(store.allowedServerCertificateFailures(for: project).isEmpty)
}

@Test func notYetValidGuidancePrioritizesCorrectingClocks() {
    let guidance = SVNErrorLocalization.serverCertificateGuidance(
        for: .notYetValid,
        language: .english
    )

    #expect(guidance.contains("server and Mac clocks"))
    #expect(guidance.contains("before allowing"))
}

private final class CertificateProjectPersistence: ProjectPersisting {
    private let loadedProjects: [SVNProject]
    private(set) var savedProjects: [[SVNProject]] = []

    init(projects: [SVNProject]) {
        loadedProjects = projects
    }

    func loadProjects() -> [SVNProject] {
        loadedProjects
    }

    func saveProjects(_ projects: [SVNProject]) {
        savedProjects.append(projects)
    }
}
