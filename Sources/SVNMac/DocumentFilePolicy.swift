import Foundation
import SVNCore

/// 줄 단위 병합이 어려워 편집 전에 저장소 잠금을 권장하는 파일 형식입니다.
enum DocumentFilePolicy {
    private static let lockRecommendedExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pdf", "psd", "ai", "sketch",
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "webp",
    ]

    static func recommendsLock(for path: String) -> Bool {
        lockRecommendedExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}

struct DocumentOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let relativePath: String
    let existingLock: SVNLockInfo?
}
