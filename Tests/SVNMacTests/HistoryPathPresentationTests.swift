import Testing
@testable import SVNMac

@Test func presentsHistoryPathRelativeToWorkingCopyRoot() {
    let value = HistoryPathPresentation(
        repositoryPath: "/project/trunk/backend/.mvn/apache-maven-3.9.9/bin/mvn",
        workingCopyRepositoryPath: "/project/trunk/backend"
    )

    #expect(value.fileName == "mvn")
    #expect(value.directory == ".mvn/apache-maven-3.9.9/bin")
    #expect(value.relativePath == ".mvn/apache-maven-3.9.9/bin/mvn")
}

@Test func preservesRepositoryPathWhenChangedPathIsOutsideWorkingCopyRoot() {
    let value = HistoryPathPresentation(
        repositoryPath: "/shared/templates/App.swift",
        workingCopyRepositoryPath: "/project/trunk"
    )

    #expect(value.fileName == "App.swift")
    #expect(value.directory == "shared/templates")
}

@Test func normalizesAndDecodesHistoryPathForDisplay() {
    let value = HistoryPathPresentation(
        repositoryPath: "/project/%E1%84%92%E1%85%A1%E1%86%AB%E1%84%80%E1%85%B3%E1%86%AF/file.swift",
        workingCopyRepositoryPath: "/project"
    )

    #expect(value.fileName == "file.swift")
    #expect(value.directory == "한글")
}
