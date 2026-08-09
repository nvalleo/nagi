// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nagi-app",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // M2: real conversion via Mozc's Mach IPC, proven out in poc/ (M0)
        // and reused as-is rather than duplicated — see
        // poc/Sources/NagiMozcIPC/.
        .package(path: "../poc")
    ],
    targets: [
        .executableTarget(
            name: "Nagi",
            dependencies: [
                // Package identity for a local path dependency is the
                // directory name ("poc"), not the `name:` field in
                // poc/Package.swift ("nagi-poc") — confirmed by SwiftPM's
                // own resolver error when this said "nagi-poc".
                .product(name: "NagiMozcIPC", package: "poc")
            ]
            // Cocoa / InputMethodKit / SwiftUI are system frameworks,
            // linked implicitly via `import` on Apple platforms — no
            // explicit linker settings needed.
        )
    ]
)
