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

@Test func repositoryNormalizationExcludesDescendantsOfSelectedAncestor() {
    let directory = "한글폴더".decomposedStringWithCanonicalMapping
    let child = "하위파일.txt".decomposedStringWithCanonicalMapping

    let targets = SVNRepositoryPathNormalization.targets(from: [
        SVNRepositoryListEntry(path: directory + "/" + child, isDirectory: false),
        SVNRepositoryListEntry(path: directory, isDirectory: true),
    ])

    #expect(targets.count == 1)
    #expect(Data(targets[0].repositoryPath.utf8) == Data(directory.utf8))
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
