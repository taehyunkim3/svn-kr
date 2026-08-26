import Foundation
import Testing
@testable import SVNCore

@Test func normalizationProbePreservesNFCAndRemovesTemporaryFile() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-probe-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: directory) }

    let probe = SVNVolumeNormalizationProbe()
    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == true)
    #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func normalizationProbeCachesResultByWorkingCopyPath() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-cache-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)

    let probe = SVNVolumeNormalizationProbe()
    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == true)
    try fileManager.removeItem(at: directory)

    // 폴더가 사라진 뒤에도 첫 결과가 나오면 두 번째 파일 생성 없이 캐시를 사용한 것입니다.
    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == true)
}

@Test func normalizationProbeDoesNotCacheUnknownResult() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-retry-\(UUID().uuidString)", isDirectory: true)
    let probe = SVNVolumeNormalizationProbe()

    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == nil)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: directory) }

    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == true)
}

@Test func normalizationProbeRemovesStaleProbeFilesBeforeRunning() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-cleanup-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: directory) }

    let staleProbe = directory.appendingPathComponent(
        ".svn-mac-normalization-probe-STALE-한글",
        isDirectory: false
    )
    let unrelatedFile = directory.appendingPathComponent(".keep", isDirectory: false)
    #expect(fileManager.createFile(atPath: staleProbe.path, contents: Data()))
    #expect(fileManager.createFile(atPath: unrelatedFile.path, contents: Data()))

    let probe = SVNVolumeNormalizationProbe()
    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == true)
    #expect(try fileManager.contentsOfDirectory(atPath: directory.path) == [".keep"])
}

@Test func normalizationProbeDetectsHFSPlusWhenDiskImagesAreAvailable() throws {
    let fileManager = FileManager.default
    let hdiutil = "/usr/bin/hdiutil"
    guard fileManager.isExecutableFile(atPath: hdiutil) else { return }

    let base = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-hfs-\(UUID().uuidString)", isDirectory: true)
    let image = base.appendingPathExtension("dmg")
    let mount = base.appendingPathComponent("mount", isDirectory: true)
    try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)

    guard run(hdiutil, ["create", "-size", "20m", "-fs", "HFS+", "-volname", "NFDPROBE", "-quiet", image.path]),
          run(hdiutil, ["attach", image.path, "-mountpoint", mount.path, "-nobrowse", "-quiet"]) else {
        try? fileManager.removeItem(at: base)
        try? fileManager.removeItem(at: image)
        return
    }
    defer {
        detachDiskImage(hdiutil, mountPath: mount.path)
        try? fileManager.removeItem(at: base)
        try? fileManager.removeItem(at: image)
    }

    let probe = SVNVolumeNormalizationProbe()
    #expect(probe.preservesPrecomposedFilenames(at: mount.path) == false)
    // 탐사는 같은 볼륨의 전용 임시 폴더에서 하므로 대상 폴더에는 탐사 파일이 남지 않습니다.
    // 볼륨 루트의 `.TemporaryItems`는 macOS가 만드는 폴더라 대상에서 제외합니다.
    let remaining = (try? fileManager.contentsOfDirectory(atPath: mount.path)) ?? []
    #expect(!remaining.contains { $0.hasPrefix(".svn-mac-normalization-probe-") })
}

@Test func normalizationProbeDiskImageDetachRetriesBeforeWarning() {
    var attempts = 0
    var waits: [TimeInterval] = []
    var warnings: [String] = []

    detachDiskImage(
        "/usr/bin/hdiutil",
        mountPath: "/tmp/normalization-probe-mount",
        execute: { _, _ in
            attempts += 1
            return false
        },
        wait: { waits.append($0) },
        warning: { warnings.append($0) }
    )

    #expect(attempts == 3)
    #expect(waits == [0.5, 0.5])
    #expect(warnings.count == 1)
}

private let diskImageDetachAttemptCount = 3
private let diskImageDetachRetryInterval: TimeInterval = 0.5

private func detachDiskImage(
    _ executablePath: String,
    mountPath: String,
    execute: (String, [String]) -> Bool = run,
    wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    warning: (String) -> Void = { print("warning: \($0)") }
) {
    for attempt in 1 ... diskImageDetachAttemptCount {
        if execute(executablePath, ["detach", mountPath, "-quiet"]) { return }
        if attempt < diskImageDetachAttemptCount {
            wait(diskImageDetachRetryInterval)
        }
    }
    warning("hdiutil detach failed after \(diskImageDetachAttemptCount) attempts: \(mountPath)")
}

private func run(_ executable: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

@Test func concurrentProbesOnSameDirectoryDoNotDeleteEachOthersProbeFiles() async throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-race-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: directory) }

    // 캐시를 공유하지 않는 별개 프로브가 같은 폴더를 동시에 조사해도 결과가 나와야 합니다.
    let results = await withTaskGroup(of: Bool?.self, returning: [Bool?].self) { group in
        for _ in 0 ..< 16 {
            group.addTask {
                SVNVolumeNormalizationProbe().preservesPrecomposedFilenames(at: directory.path)
            }
        }
        var collected: [Bool?] = []
        for await result in group { collected.append(result) }
        return collected
    }

    #expect(results.allSatisfy { $0 == true })
    #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func normalizationProbeDoesNotWriteInsideTargetDirectory() throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("svn-normalization-readonly-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? fileManager.removeItem(at: directory)
    }

    // 쓰기 권한이 없는 폴더에서도 결과가 나오면 탐사 파일을 그 폴더에 만들지 않은 것입니다.
    try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

    let probe = SVNVolumeNormalizationProbe()
    #expect(probe.preservesPrecomposedFilenames(at: directory.path) == true)
    #expect(try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty)
}
