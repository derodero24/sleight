// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sleight",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Sleight", path: "Sources/Sleight")
    ]
)
