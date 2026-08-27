import Foundation

enum RepositoryPathNormalizationForm: Equatable {
    case decomposed
    case composed
}

struct RepositoryPathCodePointSummary: Equatable {
    let codePoints: String
    let scalarCount: Int
}

struct RepositoryPathDifferenceSegment: Equatable {
    var text: String
    let isDifferent: Bool
}

struct RepositoryPathNormalizationComponentDifference: Equatable {
    let componentIndex: Int
    let repositoryComponent: String
    let normalizedComponent: String
    let repositoryDifference: String
    let normalizedDifference: String
    let repositoryCodePoints: RepositoryPathCodePointSummary
    let normalizedCodePoints: RepositoryPathCodePointSummary
}

func repositoryPathNormalizationForm(
    of path: String
) -> RepositoryPathNormalizationForm {
    let pathBytes = Data(path.utf8)
    let composedBytes = Data(path.precomposedStringWithCanonicalMapping.utf8)
    return pathBytes == composedBytes ? .composed : .decomposed
}

func repositoryPathCodePointSummary(
    for value: String
) -> RepositoryPathCodePointSummary {
    let codePoints = value.unicodeScalars.map { scalar in
        String(format: "U+%04X", scalar.value)
    }
    return RepositoryPathCodePointSummary(
        codePoints: codePoints.joined(separator: " "),
        scalarCount: codePoints.count
    )
}

func repositoryPathNormalizationComponentDifferences(
    repositoryPath: String,
    normalizedPath: String
) -> [RepositoryPathNormalizationComponentDifference] {
    let repositoryComponents = repositoryPath
        .split(separator: "/", omittingEmptySubsequences: false)
        .map(String.init)
    let normalizedComponents = normalizedPath
        .split(separator: "/", omittingEmptySubsequences: false)
        .map(String.init)
    let componentCount = max(repositoryComponents.count, normalizedComponents.count)

    return (0..<componentCount).compactMap { index in
        let repositoryComponent = repositoryComponents.indices.contains(index)
            ? repositoryComponents[index]
            : ""
        let normalizedComponent = normalizedComponents.indices.contains(index)
            ? normalizedComponents[index]
            : ""

        guard Data(repositoryComponent.utf8) != Data(normalizedComponent.utf8) else {
            return nil
        }
        let differingText = repositoryPathDifferingText(
            repositoryComponent: repositoryComponent,
            normalizedComponent: normalizedComponent
        )

        return RepositoryPathNormalizationComponentDifference(
            componentIndex: index,
            repositoryComponent: repositoryComponent,
            normalizedComponent: normalizedComponent,
            repositoryDifference: differingText.repository,
            normalizedDifference: differingText.normalized,
            repositoryCodePoints: repositoryPathCodePointSummary(for: differingText.repository),
            normalizedCodePoints: repositoryPathCodePointSummary(for: differingText.normalized)
        )
    }
}

func repositoryPathDifferenceSegments(
    path: String,
    comparedTo comparisonPath: String
) -> [RepositoryPathDifferenceSegment] {
    let pathComponents = path
        .split(separator: "/", omittingEmptySubsequences: false)
        .map(String.init)
    let comparisonComponents = comparisonPath
        .split(separator: "/", omittingEmptySubsequences: false)
        .map(String.init)
    var segments: [RepositoryPathDifferenceSegment] = []

    for index in pathComponents.indices {
        if index > pathComponents.startIndex {
            appendRepositoryPathSegment(text: "/", isDifferent: false, to: &segments)
        }

        let pathCharacters = pathComponents[index].map(String.init)
        let comparisonCharacters = comparisonComponents.indices.contains(index)
            ? comparisonComponents[index].map(String.init)
            : []
        guard pathCharacters.count == comparisonCharacters.count else {
            appendRepositoryPathSegment(
                text: pathComponents[index],
                isDifferent: true,
                to: &segments
            )
            continue
        }

        for (pathCharacter, comparisonCharacter) in zip(
            pathCharacters,
            comparisonCharacters
        ) {
            appendRepositoryPathSegment(
                text: pathCharacter,
                isDifferent: Data(pathCharacter.utf8) != Data(comparisonCharacter.utf8),
                to: &segments
            )
        }
    }

    return segments
}

private func appendRepositoryPathSegment(
    text: String,
    isDifferent: Bool,
    to segments: inout [RepositoryPathDifferenceSegment]
) {
    guard !text.isEmpty else { return }
    if segments.last?.isDifferent == isDifferent {
        segments[segments.index(before: segments.endIndex)].text.append(contentsOf: text)
    } else {
        segments.append(
            RepositoryPathDifferenceSegment(text: text, isDifferent: isDifferent)
        )
    }
}

private func repositoryPathDifferingText(
    repositoryComponent: String,
    normalizedComponent: String
) -> (repository: String, normalized: String) {
    let repositoryCharacters = repositoryComponent.map(String.init)
    let normalizedCharacters = normalizedComponent.map(String.init)
    guard repositoryCharacters.count == normalizedCharacters.count else {
        return (repositoryComponent, normalizedComponent)
    }

    var repositoryDifference = ""
    var normalizedDifference = ""
    for (repositoryCharacter, normalizedCharacter) in zip(
        repositoryCharacters,
        normalizedCharacters
    ) where Data(repositoryCharacter.utf8) != Data(normalizedCharacter.utf8) {
        repositoryDifference.append(repositoryCharacter)
        normalizedDifference.append(normalizedCharacter)
    }
    return (repositoryDifference, normalizedDifference)
}
