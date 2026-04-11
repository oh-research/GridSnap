// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sniq",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Sniq",
            path: "Sources"
        ),
    ]
)
