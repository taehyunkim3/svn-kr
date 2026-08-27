import Foundation
import Testing
@testable import SVNMac

@Test func detectsRepositoryPathNormalizationFormUsingUTF8Bytes() {
    let composedPath = "문서/기획서"
    let decomposedPath = composedPath.decomposedStringWithCanonicalMapping

    #expect(Data(composedPath.utf8) != Data(decomposedPath.utf8))
    #expect(repositoryPathNormalizationForm(of: decomposedPath) == .decomposed)
    #expect(repositoryPathNormalizationForm(of: composedPath) == .composed)
}

@Test func selectsOnlyPathComponentsWithDifferentUTF8Bytes() {
    let decomposedPlan = "기획서".decomposedStringWithCanonicalMapping
    let differences = repositoryPathNormalizationComponentDifferences(
        repositoryPath: "공통/0720 \(decomposedPlan)/완료",
        normalizedPath: "공통/0720 기획서/완료"
    )

    #expect(differences.count == 1)
    #expect(differences.first?.componentIndex == 1)
    #expect(differences.first?.repositoryComponent == "0720 \(decomposedPlan)")
    #expect(differences.first?.normalizedComponent == "0720 기획서")
    #expect(differences.first?.repositoryDifference == decomposedPlan)
    #expect(differences.first?.normalizedDifference == "기획서")
    #expect(
        differences.first?.repositoryCodePoints.codePoints
            == "U+1100 U+1175 U+1112 U+116C U+11A8 U+1109 U+1165"
    )
    #expect(differences.first?.normalizedCodePoints.codePoints == "U+AE30 U+D68D U+C11C")
}

@Test func describesKoreanUnicodeCodePointsAndScalarCounts() {
    let composed = repositoryPathCodePointSummary(for: "기")
    let decomposed = repositoryPathCodePointSummary(
        for: "기".decomposedStringWithCanonicalMapping
    )

    #expect(composed.codePoints == "U+AE30")
    #expect(composed.scalarCount == 1)
    #expect(decomposed.codePoints == "U+1100 U+1175")
    #expect(decomposed.scalarCount == 2)
}

@Test func returnsEveryDifferentlyNormalizedPathComponent() {
    let decomposedKorean = "한글".decomposedStringWithCanonicalMapping
    let decomposedSyllable = "기".decomposedStringWithCanonicalMapping
    let differences = repositoryPathNormalizationComponentDifferences(
        repositoryPath: "\(decomposedKorean)/같음/\(decomposedSyllable)",
        normalizedPath: "한글/같음/기"
    )

    #expect(differences.map(\.componentIndex) == [0, 2])
    #expect(differences.map(\.normalizedComponent) == ["한글", "기"])
}

@Test func highlightsOnlyKoreanCharactersWithDifferentUTF8Bytes() {
    let repositoryPath = "공통/0720 기획서/완료".decomposedStringWithCanonicalMapping
    let normalizedPath = "공통/0720 기획서/완료"
    let repositorySegments = repositoryPathDifferenceSegments(
        path: repositoryPath,
        comparedTo: normalizedPath
    )
    let normalizedSegments = repositoryPathDifferenceSegments(
        path: normalizedPath,
        comparedTo: repositoryPath
    )

    #expect(repositorySegments.map(\.isDifferent) == [true, false, true, false, true])
    #expect(normalizedSegments.map(\.isDifferent) == [true, false, true, false, true])
    #expect(repositorySegments.filter(\.isDifferent).map(\.text) == [
        "공통".decomposedStringWithCanonicalMapping,
        "기획서".decomposedStringWithCanonicalMapping,
        "완료".decomposedStringWithCanonicalMapping,
    ])
    #expect(normalizedSegments.filter(\.isDifferent).map(\.text) == ["공통", "기획서", "완료"])
    expectSegments(repositorySegments, restore: repositoryPath)
    expectSegments(normalizedSegments, restore: normalizedPath)
}

@Test func leavesIdenticalPathUnhighlighted() {
    let path = "공통/기획서/완료"
    let segments = repositoryPathDifferenceSegments(path: path, comparedTo: path)

    #expect(segments.allSatisfy { !$0.isDifferent })
    expectSegments(segments, restore: path)
}

@Test func highlightsEntireComponentsWhenCharacterCountsDiffer() {
    let shorterPath = "공통/기획/완료"
    let longerPath = "공통/기획서/완료"
    let shorterSegments = repositoryPathDifferenceSegments(
        path: shorterPath,
        comparedTo: longerPath
    )
    let longerSegments = repositoryPathDifferenceSegments(
        path: longerPath,
        comparedTo: shorterPath
    )

    #expect(shorterSegments.filter(\.isDifferent).map(\.text) == ["기획"])
    #expect(longerSegments.filter(\.isDifferent).map(\.text) == ["기획서"])
    #expect(shorterSegments.filter { $0.text.contains("/") }.allSatisfy { !$0.isDifferent })
    #expect(longerSegments.filter { $0.text.contains("/") }.allSatisfy { !$0.isDifferent })
    expectSegments(shorterSegments, restore: shorterPath)
    expectSegments(longerSegments, restore: longerPath)
}

@Test func determinesRepositoryPathNormalizationSelectionButtonAvailability() {
    #expect(
        repositoryPathNormalizationSelectionAvailability(
            targetCount: 3,
            selectedCount: 0,
            state: .available
        ) == RepositoryPathNormalizationSelectionAvailability(
            canSelectAll: true,
            canDeselectAll: false
        )
    )
    #expect(
        repositoryPathNormalizationSelectionAvailability(
            targetCount: 3,
            selectedCount: 1,
            state: .available
        ) == RepositoryPathNormalizationSelectionAvailability(
            canSelectAll: true,
            canDeselectAll: true
        )
    )
    #expect(
        repositoryPathNormalizationSelectionAvailability(
            targetCount: 3,
            selectedCount: 3,
            state: .available
        ) == RepositoryPathNormalizationSelectionAvailability(
            canSelectAll: false,
            canDeselectAll: true
        )
    )
    #expect(
        repositoryPathNormalizationSelectionAvailability(
            targetCount: 0,
            selectedCount: 0,
            state: .available
        ) == RepositoryPathNormalizationSelectionAvailability(
            canSelectAll: false,
            canDeselectAll: false
        )
    )
    #expect(
        repositoryPathNormalizationSelectionAvailability(
            targetCount: 3,
            selectedCount: 1,
            state: .running
        ) == RepositoryPathNormalizationSelectionAvailability(
            canSelectAll: false,
            canDeselectAll: false
        )
    )
    #expect(
        repositoryPathNormalizationSelectionAvailability(
            targetCount: 3,
            selectedCount: 1,
            state: .showingResult
        ) == RepositoryPathNormalizationSelectionAvailability(
            canSelectAll: false,
            canDeselectAll: false
        )
    )
}

private func expectSegments(
    _ segments: [RepositoryPathDifferenceSegment],
    restore path: String
) {
    let restoredPath = segments.map(\.text).joined()
    #expect(Data(restoredPath.utf8) == Data(path.utf8))
}
