// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipboardMac",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "ClipboardMac",
            path: "Sources/ClipboardMac"
        )
    ]
)
