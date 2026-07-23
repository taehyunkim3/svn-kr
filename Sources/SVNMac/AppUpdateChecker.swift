import AppKit
import Foundation

struct AppStoreRelease: Equatable, Sendable {
    let version: String
    let storeURL: URL
}

enum AppUpdateResult: Equatable, Sendable {
    case updateAvailable(AppStoreRelease)
    case upToDate(currentVersion: String)
}

enum AppUpdateError: Error, Equatable {
    case missingBundleInformation
    case appNotFound
}

struct AppUpdateService: Sendable {
    private let bundleIdentifier: String?
    private let currentVersion: String?
    private let regionCode: String?
    private let session: URLSession

    init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        regionCode: String? = Locale.current.region?.identifier,
        session: URLSession = .shared
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
        self.regionCode = regionCode
        self.session = session
    }

    func check() async throws -> AppUpdateResult {
        guard let currentVersion, let lookupURL else {
            throw AppUpdateError.missingBundleInformation
        }

        let (data, response) = try await session.data(from: lookupURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let lookup = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        guard let item = lookup.results.first,
              let storeURL = URL(string: item.trackViewURL) else {
            throw AppUpdateError.appNotFound
        }

        let release = AppStoreRelease(version: item.version, storeURL: storeURL)
        if Self.isVersion(release.version, newerThan: currentVersion) {
            return .updateAvailable(release)
        }
        return .upToDate(currentVersion: currentVersion)
    }

    var lookupURL: URL? {
        guard let bundleIdentifier else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        if let regionCode, !regionCode.isEmpty {
            queryItems.append(URLQueryItem(name: "country", value: regionCode.lowercased()))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = numericVersionParts(candidate)
        let currentParts = numericVersionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private static func numericVersionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix(while: \Character.isNumber)) ?? 0
        }
    }
}

private struct AppStoreLookupResponse: Decodable, Sendable {
    let results: [AppStoreLookupItem]
}

private struct AppStoreLookupItem: Decodable, Sendable {
    let version: String
    let trackViewURL: String

    enum CodingKeys: String, CodingKey {
        case version
        case trackViewURL = "trackViewUrl"
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    enum ManualStatus: Equatable {
        case idle
        case checking
        case updateAvailable(AppStoreRelease)
        case upToDate(version: String)
        case failed
    }

    @Published private(set) var manualStatus: ManualStatus = .idle
    @Published private(set) var automaticUpdate: AppStoreRelease?

    private static let lastAutomaticCheckKey = "last-automatic-update-check"
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let service: AppUpdateService
    private let defaults: UserDefaults
    private var checkedAutomaticallyThisSession = false

    init(service: AppUpdateService = AppUpdateService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    func checkAutomaticallyIfNeeded(now: Date = Date()) {
        guard !checkedAutomaticallyThisSession else { return }
        checkedAutomaticallyThisSession = true

        if let lastCheck = defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date,
           now.timeIntervalSince(lastCheck) < Self.automaticCheckInterval {
            return
        }

        Task {
            do {
                let result = try await service.check()
                defaults.set(now, forKey: Self.lastAutomaticCheckKey)
                if case let .updateAvailable(release) = result {
                    automaticUpdate = release
                }
            } catch {
                // 자동 확인 실패는 앱 사용을 방해하지 않습니다. 수동 확인에서만 오류를 표시합니다.
            }
        }
    }

    func checkManually() {
        guard manualStatus != .checking else { return }
        manualStatus = .checking

        Task {
            do {
                switch try await service.check() {
                case let .updateAvailable(release):
                    manualStatus = .updateAvailable(release)
                case let .upToDate(currentVersion):
                    manualStatus = .upToDate(version: currentVersion)
                }
            } catch {
                manualStatus = .failed
            }
        }
    }

    func openStore(for release: AppStoreRelease) {
        NSWorkspace.shared.open(release.storeURL)
    }

    func dismissAutomaticUpdate() {
        automaticUpdate = nil
    }
}
