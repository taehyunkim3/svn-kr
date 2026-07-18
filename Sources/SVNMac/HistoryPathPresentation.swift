import Foundation

/// 저장소 절대 경로를 작업 복사본 루트 기준의 짧은 파일 표기로 바꿉니다.
/// 예: `/project/trunk/backend/src/App.swift` + `/project/trunk/backend`
/// → 파일명 `App.swift`, 경로 `src`
struct HistoryPathPresentation: Equatable {
    let fileName: String
    let directory: String
    let relativePath: String

    init(repositoryPath: String, workingCopyRepositoryPath: String?) {
        let repositoryPath = Self.decoded(repositoryPath)
        let rootPath = workingCopyRepositoryPath.map(Self.decoded)
        let relativePath = Self.relativePath(repositoryPath, below: rootPath)
        let path = relativePath as NSString

        self.relativePath = relativePath.precomposedStringWithCanonicalMapping
        self.fileName = path.lastPathComponent.precomposedStringWithCanonicalMapping
        let directory = path.deletingLastPathComponent
        self.directory = directory == "." ? "" : directory.precomposedStringWithCanonicalMapping
    }

    private static func decoded(_ path: String) -> String {
        (path.removingPercentEncoding ?? path).precomposedStringWithCanonicalMapping
    }

    private static func relativePath(_ repositoryPath: String, below rootPath: String?) -> String {
        let repositoryComponents = components(of: repositoryPath)
        guard let rootPath else { return repositoryComponents.joined(separator: "/") }
        let rootComponents = components(of: rootPath)
        guard repositoryComponents.starts(with: rootComponents) else {
            return repositoryComponents.joined(separator: "/")
        }
        return repositoryComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
