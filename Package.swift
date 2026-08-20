// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Vantage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Vantage", targets: ["Vantage"])
    ],
    targets: [
        .executableTarget(
            name: "Vantage",
            path: "Sources/Vantage",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VantageTests",
            dependencies: ["Vantage"],
            path: "Tests/VantageTests"
        )
    ]
)
