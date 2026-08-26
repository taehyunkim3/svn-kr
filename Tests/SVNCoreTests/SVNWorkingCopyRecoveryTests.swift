import Foundation
import SVNCore
import Testing

@Suite("SVNWorkingCopyRecoveryTests")
struct SVNWorkingCopyRecoveryTests {
    @Test func recoversRealChangesIntoCleanCheckoutWithoutChangingSource() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-recovery-test-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("기능", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let modifiedData = Data("사용자 수정".utf8)
        let newData = Data("새 파일".utf8)
        let modifiedSource = source.appendingPathComponent("기능/수정.txt")
        let newSource = source.appendingPathComponent("기능/새 파일.txt")
        try modifiedData.write(to: modifiedSource)
        try newData.write(to: newSource)
        let sourceBefore = try directoryFileDigest(at: source)

        let executable = root.appendingPathComponent("fake-svn")
        let decomposedFeature = "기능".decomposedStringWithCanonicalMapping
        let script = """
        #!/bin/sh
        command=
        for argument in "$@"; do
          case "$argument" in
            status|info|checkout) command=$argument ;;
          esac
        done
        if [ "$command" = info ]; then
          printf 'https://svn.example.test/project/trunk\n'
          exit 0
        fi
        if [ "$command" = checkout ]; then
          mkdir -p '기능'
          printf '서버 원본' > '기능/수정.txt'
          printf '삭제 전 원본' > '기능/삭제.txt'
          exit 0
        fi
        if [ "$command" = status ]; then
          if [ "$(basename "$PWD")" = source ]; then
            printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="10"/></entry><entry path="기능"><wc-status item="normal" revision="10"/></entry><entry path="기능/수정.txt"><wc-status item="modified" revision="10"/></entry><entry path="\(decomposedFeature)/새 파일.txt"><wc-status item="unversioned"/></entry><entry path="기능/삭제.txt"><wc-status item="missing" revision="10"/></entry><entry path="\(decomposedFeature)"><wc-status item="missing" revision="-1"/></entry></target></status>'
          else
            printf '%s' '<?xml version="1.0"?><status><target path="."><entry path="."><wc-status item="normal" revision="10"/></entry><entry path="기능"><wc-status item="normal" revision="10"/></entry><entry path="기능/수정.txt"><wc-status item="modified" revision="10"/></entry><entry path="기능/새 파일.txt"><wc-status item="unversioned"/></entry><entry path="기능/삭제.txt"><wc-status item="missing" revision="10"/></entry></target></status>'
          fi
          exit 0
        fi
        exit 1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let client = SVNClient(
            executablePath: executable.path,
            configDirectoryPath: root.appendingPathComponent("svn-config").path
        )
        let preview = try await client.recoveryPreview(at: source.path)
        #expect(preview.modifiedCount == 1)
        #expect(preview.addedCount == 1)
        #expect(preview.deletedCount == 1)
        #expect(preview.ignoredAliasCount == 1)
        #expect(preview.blockingPaths.isEmpty)

        let result = try await client.recoverWorkingCopy(from: source.path, to: destination.path)

        #expect(try Data(contentsOf: destination.appendingPathComponent("기능/수정.txt")) == modifiedData)
        #expect(try Data(contentsOf: destination.appendingPathComponent("기능/새 파일.txt")) == newData)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("기능/삭제.txt").path))
        #expect(try directoryFileDigest(at: source) == sourceBefore)
        #expect(result.destinationPath == destination.path)
        #expect(Set(result.migratedPaths) == ["기능/새 파일.txt", "기능/수정.txt", "기능/삭제.txt"])
        #expect(result.snapshot.collisions.isEmpty)
    }

    @Test func rejectsNonemptyRecoveryDestinationBeforeCheckout() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-recovery-nonempty-test-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: destination.appendingPathComponent("existing.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent("fake-svn")
        let script = """
        #!/bin/sh
        printf '%s\n' "$*" >> '\(root.appendingPathComponent("command-log").path)'
        exit 1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = SVNClient(executablePath: executable.path)

        do {
            _ = try await client.recoverWorkingCopy(from: source.path, to: destination.path)
            Issue.record("비어 있지 않은 복구 폴더가 거부되어야 합니다.")
        } catch SVNError.recoveryDestinationNotEmpty {
            // expected
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("command-log").path))
        #expect(try String(contentsOf: destination.appendingPathComponent("existing.txt"), encoding: .utf8) == "keep")
    }

    /// 복구 대상 폴더가 원본 작업 폴더 안이면 새 체크아웃이 원본의 미등록 항목으로 잡혀
    /// 저장소 전체가 자기 안으로 한 번 더 복사됩니다. svn을 부르기 전에 막아야 합니다.
    @Test func rejectsRecoveryDestinationInsideSourceWorkingCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-recovery-nested-test-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = source.appendingPathComponent("복구", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let commandLog = root.appendingPathComponent("command-log")
        let client = SVNClient(executablePath: try makeLoggingFakeSVN(at: root, log: commandLog).path)

        do {
            _ = try await client.recoverWorkingCopy(from: source.path, to: destination.path)
            Issue.record("원본 하위 폴더가 거부되어야 합니다.")
        } catch SVNError.recoveryBlocked {
            // expected
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: commandLog.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func rejectsRecoveryDestinationThatContainsSourceWorkingCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svn-recovery-parent-test-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("작업", isDirectory: true)
        let source = destination.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let commandLog = root.appendingPathComponent("command-log")
        let client = SVNClient(executablePath: try makeLoggingFakeSVN(at: root, log: commandLog).path)

        do {
            _ = try await client.recoverWorkingCopy(from: source.path, to: destination.path)
            Issue.record("원본을 품는 폴더가 거부되어야 합니다.")
        } catch SVNError.recoveryBlocked {
            // expected
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: commandLog.path))
    }
}

private func makeLoggingFakeSVN(at root: URL, log: URL) throws -> URL {
    let executable = root.appendingPathComponent("fake-svn-\(UUID().uuidString)")
    let script = """
    #!/bin/sh
    printf '%s\\n' "$*" >> '\(log.path)'
    exit 1
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return executable
}

private func directoryFileDigest(at root: URL) throws -> [String: Data] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [:] }
    var result: [String: Data] = [:]
    for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let relative = String(fileURL.path.dropFirst(root.path.count + 1))
        result[relative] = try Data(contentsOf: fileURL)
    }
    return result
}
