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
        .executable(name: "price-watch", targets: ["PriceWatch"]),
    ],
    targets: [
        .target(
            name: "NewsCore",
            resources: [
                .process("Resources"),
            ]
        ),
        // Command-line price watcher run by GitHub Actions (sends ntfy notifications).
        .executableTarget(
            name: "PriceWatch",
            dependencies: ["NewsCore"]
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
