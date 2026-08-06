// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nagi-app",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Nagi"
            // Cocoa / InputMethodKit are system frameworks, linked
            // implicitly via `import` on Apple platforms — no explicit
            // linker settings needed.
        )
    ]
)
