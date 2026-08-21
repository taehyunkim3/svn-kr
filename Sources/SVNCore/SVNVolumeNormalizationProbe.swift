import Darwin
import Foundation

/// 작업 폴더가 있는 볼륨이 NFC 파일명 바이트를 그대로 보존하는지 실제 파일로 확인합니다.
public final class SVNVolumeNormalizationProbe: @unchecked Sendable {
    public static let shared = SVNVolumeNormalizationProbe()

    private let lock = NSLock()
    private var cachedResults: [String: Bool] = [:]

    public init() {}

    /// 프로브 자체가 실패하면 경고 오탐을 피하기 위해 `nil`을 반환합니다.
    public func preservesPrecomposedFilenames(at directoryPath: String) -> Bool? {
        let path = URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL.path

        if let cachedResult = lock.withLock({ cachedResults[path] }) {
            return cachedResult
        }

        guard let result = probeUncached(at: path) else { return nil }
        return lock.withLock {
            if let cachedResult = cachedResults[path] { return cachedResult }
            cachedResults[path] = result
            return result
        }
    }

    public static func preservesPrecomposedFilenames(at directoryPath: String) -> Bool? {
        shared.preservesPrecomposedFilenames(at: directoryPath)
    }

    private func probeUncached(at directoryPath: String) -> Bool? {
        guard let directory = opendir(directoryPath) else { return nil }
        defer { closedir(directory) }

        let probePrefix = Data(".svn-mac-normalization-probe-".utf8)
        while let entry = readdir(directory) {
            let bytes = entryNameBytes(entry)
            guard bytes.starts(with: probePrefix) else { continue }
            let didRemove = withUnsafePointer(to: &entry.pointee.d_name) { namePointer in
                namePointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)
                ) { unlinkat(dirfd(directory), $0, 0) == 0 }
            }
            guard didRemove else { return nil }
        }

        let probeName = ".svn-mac-normalization-probe-\(UUID().uuidString)-한글"
            .precomposedStringWithCanonicalMapping
        // URL.appendingPathComponent는 Darwin에서 유니코드 경로 표현을 바꿀 수 있으므로
        // 생성할 마지막 경로 성분은 문자열의 UTF-8 바이트를 그대로 POSIX open에 넘깁니다.
        let separator = directoryPath.hasSuffix("/") ? "" : "/"
        let probePath = directoryPath + separator + probeName

        let descriptor = open(probePath, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        close(descriptor)
        defer { unlink(probePath) }

        rewinddir(directory)

        let expectedNFC = Data(probeName.utf8)
        let expectedNFD = Data(probeName.decomposedStringWithCanonicalMapping.utf8)

        while let entry = readdir(directory) {
            let bytes = entryNameBytes(entry)
            if bytes == expectedNFC { return true }
            if bytes == expectedNFD { return false }
        }

        return nil
    }

    private func entryNameBytes(_ entry: UnsafeMutablePointer<dirent>) -> Data {
        withUnsafeBytes(of: &entry.pointee.d_name) { rawBuffer in
            let nameLength = rawBuffer.firstIndex(of: 0) ?? rawBuffer.count
            return Data(rawBuffer.prefix(nameLength))
        }
    }
}
