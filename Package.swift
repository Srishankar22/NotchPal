// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchPal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NotchPal", path: "Sources/NotchPal")
    ]
)
