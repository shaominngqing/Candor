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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Candor",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Candor",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        .testTarget(
            name: "CandorTests",
            dependencies: ["Candor"],
            path: "Tests/CandorTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
