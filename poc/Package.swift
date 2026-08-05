// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nagi-poc",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "nagi-poc", targets: ["NagiPoC"]),
        .library(name: "NagiMozcIPC", targets: ["NagiMozcIPC"])
    ],
    dependencies: [
        // SwiftProtobuf: generates Swift types from Mozc's .proto files
        // and provides runtime serialization.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0")
    ],
    targets: [
        .executableTarget(
            name: "NagiPoC",
            dependencies: ["NagiMozcIPC"]
        ),
        .target(
            name: "NagiMozcIPC",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "NagiMozcProto"
            ]
        ),
        .target(
            name: "NagiMozcProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            // Generated files land in Generated/ after running
            // scripts/fetch-mozc-proto.sh. Not checked in — see .gitignore.
            exclude: ["README.md"]
        )
    ]
)
