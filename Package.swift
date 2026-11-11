// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VideoNewsWire",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "VideoNewsWire",
            path: "Sources/VideoNewsWire"
        )
    ],
    swiftLanguageModes: [.v5]
)
