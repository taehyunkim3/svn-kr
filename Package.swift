// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SVNMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SVNMac", targets: ["SVNMac"]),
        .library(name: "SVNCore", targets: ["SVNCore"]),
    ],
    targets: [
        .target(name: "SVNCore"),
        .executableTarget(name: "SVNMac", dependencies: ["SVNCore"]),
        .testTarget(name: "SVNCoreTests", dependencies: ["SVNCore"]),
        .testTarget(name: "SVNMacTests", dependencies: ["SVNMac", "SVNCore"]),
    ]
)
