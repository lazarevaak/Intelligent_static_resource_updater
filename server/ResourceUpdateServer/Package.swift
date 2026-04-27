// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ResourceUpdateServer",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // 🔐 Cross-platform crypto primitives (Linux/macOS)
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.3.0"),
        // 🧩 CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // ⚙️ Configuration package pinned explicitly to avoid incompatible transitive resolution
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0"),
        // ☁️ AWS SDK for Swift (S3 via Soto)
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
        .package(url: "https://github.com/soto-project/soto-core.git", from: "7.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "ResourceUpdateServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoCore", package: "soto-core"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ResourceUpdateServerTests",
            dependencies: [
                .target(name: "ResourceUpdateServer"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
