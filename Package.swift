// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "YuJing",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "YuJing", targets: ["YuJing"])
    ],
    targets: [
        .executableTarget(
            name: "YuJing",
            path: "Sources/YuJing"
        ),
        .testTarget(
            name: "YuJingTests",
            dependencies: ["YuJing"],
            path: "Tests/YuJingTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
