// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipBoard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipBoard", targets: ["ClipBoard"])],
    targets: [
        .executableTarget(
            name: "ClipBoard",
            path: "Clipboard",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(name: "ClipBoardTests", dependencies: ["ClipBoard"], path: "ClipboardTests")
    ]
)
