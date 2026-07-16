import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: build-icns.swift <iconset> <output.icns>\n".utf8))
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

func bigEndianBytes(_ value: Int) -> [UInt8] {
    let value = UInt32(value)
    return [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
}

var chunks = Data()
for (type, fileName) in entries {
    let imageData = try Data(contentsOf: iconset.appendingPathComponent(fileName))
    chunks.append(contentsOf: type.utf8)
    chunks.append(contentsOf: bigEndianBytes(imageData.count + 8))
    chunks.append(imageData)
}

var output = Data("icns".utf8)
output.append(contentsOf: bigEndianBytes(chunks.count + 8))
output.append(chunks)
try output.write(to: outputURL, options: .atomic)
