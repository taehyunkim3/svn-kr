import Foundation

public enum SVNFileSystem {
    private static let chunkSize = 1024 * 1024

    public static func overwriteFile(at destination: URL, withContentsOf source: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        try output.truncate(atOffset: 0)
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }

    public static func filesHaveEqualContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        let lhsValues = try lhs.resourceValues(forKeys: keys)
        let rhsValues = try rhs.resourceValues(forKeys: keys)
        guard lhsValues.isRegularFile == true,
              rhsValues.isRegularFile == true,
              lhsValues.fileSize == rhsValues.fileSize else {
            return false
        }
        let lhsHandle = try FileHandle(forReadingFrom: lhs)
        let rhsHandle = try FileHandle(forReadingFrom: rhs)
        defer {
            try? lhsHandle.close()
            try? rhsHandle.close()
        }
        while true {
            let lhsChunk = try lhsHandle.read(upToCount: chunkSize) ?? Data()
            let rhsChunk = try rhsHandle.read(upToCount: chunkSize) ?? Data()
            guard lhsChunk == rhsChunk else { return false }
            if lhsChunk.isEmpty { return true }
        }
    }
}
