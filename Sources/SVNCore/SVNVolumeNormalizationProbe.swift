import Darwin
import Foundation

/// 작업 폴더가 있는 볼륨이 NFC 파일명 바이트를 그대로 보존하는지 실제 파일로 확인합니다.
public final class SVNVolumeNormalizationProbe: @unchecked Sendable {
    public static let shared = SVNVolumeNormalizationProbe()

    private static let probeNamePrefix = ".svn-mac-normalization-probe-"

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
        // 예전 판이 남긴 탐사 파일을 먼저 치웁니다. 지금은 대상 폴더에 탐사 파일을
        // 만들지 않으므로 이 정리는 실행 중인 다른 프로브와 겹치지 않습니다.
        guard removeStaleProbeFiles(inDirectoryAt: directoryPath) else { return nil }

        // 탐사 파일을 작업 복사본 안에 만들면 그 순간의 `svn status`에 미버전 항목으로
        // 잡히고, 같은 폴더를 조사하는 다른 프로브의 정리 루프가 그 파일을 지웁니다.
        // 같은 볼륨의 전용 임시 폴더에서 조사하면 두 문제가 함께 없어집니다.
        if let volumeTemporaryDirectory = try? FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: directoryPath, isDirectory: true),
            create: true
        ) {
            defer { try? FileManager.default.removeItem(at: volumeTemporaryDirectory) }
            if let result = probeNormalization(inDirectoryAt: volumeTemporaryDirectory.path) {
                return result
            }
        }

        // 볼륨 임시 폴더를 만들 수 없으면 대상 폴더에서 직접 조사합니다.
        return probeNormalization(inDirectoryAt: directoryPath)
    }

    private func removeStaleProbeFiles(inDirectoryAt directoryPath: String) -> Bool {
        guard let directory = opendir(directoryPath) else { return false }
        defer { closedir(directory) }

        let probePrefix = Data(Self.probeNamePrefix.utf8)
        while let entry = readdir(directory) {
            let bytes = entryNameBytes(entry)
            guard bytes.starts(with: probePrefix) else { continue }
            let didRemove = withUnsafePointer(to: &entry.pointee.d_name) { namePointer in
                namePointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)
                ) { unlinkat(dirfd(directory), $0, 0) == 0 }
            }
            guard didRemove else { return false }
        }
        return true
    }

    private func probeNormalization(inDirectoryAt directoryPath: String) -> Bool? {
        let probeName = "\(Self.probeNamePrefix)\(UUID().uuidString)-한글"
            .precomposedStringWithCanonicalMapping
        // URL.appendingPathComponent는 Darwin에서 유니코드 경로 표현을 바꿀 수 있으므로
        // 생성할 마지막 경로 성분은 문자열의 UTF-8 바이트를 그대로 POSIX open에 넘깁니다.
        let separator = directoryPath.hasSuffix("/") ? "" : "/"
        let probePath = directoryPath + separator + probeName

        let descriptor = open(probePath, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        close(descriptor)
        defer { unlink(probePath) }

        // 탐사 파일을 만든 뒤에 디렉터리를 엽니다. 먼저 연 스트림은 새로 만든 항목을
        // 돌려주지 않을 수 있습니다.
        guard let directory = opendir(directoryPath) else { return nil }
        defer { closedir(directory) }

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
