// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shortkeys",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "Vendor/KeyboardShortcuts"),
    ],
    targets: [
        .executableTarget(
            name: "Shortkeys",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/Shortkeys"
        ),
    ]
)
