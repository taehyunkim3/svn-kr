import Foundation
import Testing
@testable import SVNCore

@Test func repositoryNormalizationSelectsOnlyNFDPathsByBytes() {
    let nfc = "한글.txt"
    let nfd = nfc.decomposedStringWithCanonicalMapping

    let targets = SVNRepositoryPathNormalization.targets(from: [
        SVNRepositoryListEntry(path: nfc, isDirectory: false),
        SVNRepositoryListEntry(path: nfd, isDirectory: false),
        SVNRepositoryListEntry(path: "plain.txt", isDirectory: false),
    ])

    #expect(targets.count == 1)
    #expect(targets[0].isDirectory == false)
    #expect(Data(targets[0].repositoryPath.utf8) == Data(nfd.utf8))
    #expect(Data(targets[0].normalizedPath.utf8) == Data(nfc.utf8))
    #expect(Data(nfd.utf8) != Data(nfc.utf8))
}

@Test func repositoryNormalizationIncludesNFDDescendantsOfSelectedAncestor() {
    let directory = "한글폴더".decomposedStringWithCanonicalMapping
    let child = "하위파일.txt".decomposedStringWithCanonicalMapping

    let targets = SVNRepositoryPathNormalization.targets(from: [
        SVNRepositoryListEntry(path: directory + "/" + child, isDirectory: false),
        SVNRepositoryListEntry(path: directory, isDirectory: true),
    ])

    #expect(targets.count == 2)
    #expect(Data(targets[0].repositoryPath.utf8) == Data(directory.utf8))
    #expect(targets[0].isDirectory)
    #expect(Data(targets[1].repositoryPath.utf8) == Data((directory + "/" + child).utf8))
    #expect(Data(targets[1].normalizedPath.utf8) == Data((directory + "/하위파일.txt").utf8))
    #expect(!targets[1].isDirectory)
}

@Test func repositoryNormalizationExcludesNFCDescendantOfSelectedAncestor() {
    let directory = "한글폴더".decomposedStringWithCanonicalMapping
    let child = "하위파일.txt"

    let targets = SVNRepositoryPathNormalization.targets(from: [
        SVNRepositoryListEntry(path: directory + "/" + child, isDirectory: false),
        SVNRepositoryListEntry(path: directory, isDirectory: true),
    ])

    #expect(targets.count == 1)
    #expect(Data(targets[0].repositoryPath.utf8) == Data(directory.utf8))
    #expect(Data(targets[0].normalizedPath.utf8) == Data("한글폴더".utf8))
    #expect(targets[0].isDirectory)
}

@Test func repositoryNormalizationSortsShallowPathsFirst() {
    let shallow = "가".decomposedStringWithCanonicalMapping
    let medium = "plain/나".decomposedStringWithCanonicalMapping
    let deep = "plain/nested/다".decomposedStringWithCanonicalMapping

    let targets = SVNRepositoryPathNormalization.targets(from: [
        SVNRepositoryListEntry(path: deep, isDirectory: false),
        SVNRepositoryListEntry(path: medium, isDirectory: false),
        SVNRepositoryListEntry(path: shallow, isDirectory: false),
    ])

    #expect(targets.map { $0.repositoryPath.split(separator: "/").count } == [1, 2, 3])
    #expect(targets.map { Data($0.repositoryPath.utf8) } == [
        Data(shallow.utf8), Data(medium.utf8), Data(deep.utf8),
    ])
}

@Test func svnmuccArgumentsPutDeepMovesFirstAndPercentEncodeAtSigns() {
    let shallowSource = "얕은@폴더".decomposedStringWithCanonicalMapping
    let shallowDestination = "얕은@폴더"
    let deepSource = "plain/깊은@파일.txt".decomposedStringWithCanonicalMapping
    let deepDestination = "plain/깊은@파일.txt"

    let arguments = SVNRepositoryPathNormalization.svnmuccMoveArguments(
        for: [
            SVNRepositoryPathNormalizationTarget(
                repositoryPath: shallowSource,
                normalizedPath: shallowDestination,
                isDirectory: true
            ),
            SVNRepositoryPathNormalizationTarget(
                repositoryPath: deepSource,
                normalizedPath: deepDestination,
                isDirectory: false
            ),
        ],
        repositoryURL: "https://example.com/repository"
    )

    #expect(arguments == [
        "mv",
        SVNRepositoryPathNormalization.repositoryURL(
            "https://example.com/repository",
            appending: deepSource
        ),
        SVNRepositoryPathNormalization.repositoryURL(
            "https://example.com/repository",
            appending: deepDestination
        ),
        "mv",
        SVNRepositoryPathNormalization.repositoryURL(
            "https://example.com/repository",
            appending: shallowSource
        ),
        SVNRepositoryPathNormalization.repositoryURL(
            "https://example.com/repository",
            appending: shallowDestination
        ),
    ])
    #expect(arguments[1].contains("%40"))
    #expect(!arguments[1].hasSuffix("@"))
}

@Test func parsesSVNMuccCommittedRevision() {
    #expect(SVNRepositoryPathNormalization.committedSVNMuccRevision(
        from: "r1847 committed by user at 2026-08-27T04:50:20.490312Z\n"
    ) == "1847")
}
