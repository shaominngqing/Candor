// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Candor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Candor", targets: ["Candor"])
    ],
    targets: [
        .executableTarget(
            name: "Candor",
            path: "Sources/Candor"
        ),
        .testTarget(
            name: "CandorTests",
            dependencies: ["Candor"],
            path: "Tests/CandorTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
