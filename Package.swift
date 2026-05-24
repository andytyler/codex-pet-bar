// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPetBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexPetBarCore", targets: ["CodexPetBarCore"]),
        .executable(name: "CodexPetBar", targets: ["CodexPetBar"])
    ],
    targets: [
        .target(
            name: "CodexPetBarCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "CodexPetBar",
            dependencies: ["CodexPetBarCore"]
        ),
        .testTarget(
            name: "CodexPetBarCoreTests",
            dependencies: ["CodexPetBarCore"]
        )
    ]
)
