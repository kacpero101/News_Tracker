// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NewsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "NewsCore", targets: ["NewsCore"]),
    ],
    targets: [
        .target(
            name: "NewsCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "NewsCoreTests",
            dependencies: ["NewsCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
