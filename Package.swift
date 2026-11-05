// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Amnesia",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AmnesiaCore"),
        .executableTarget(name: "Amnesia", dependencies: ["AmnesiaCore"]),
        .testTarget(name: "AmnesiaCoreTests", dependencies: ["AmnesiaCore"]),
    ]
)
