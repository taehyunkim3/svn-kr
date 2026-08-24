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
