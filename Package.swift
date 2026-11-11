// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RarExtractor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RarExtractorCore", targets: ["RarExtractorCore"]),
        .executable(name: "RarExtractor", targets: ["RarExtractor"]),
    ],
    targets: [
        .target(name: "RarExtractorCore"),
        .executableTarget(name: "RarExtractor", dependencies: ["RarExtractorCore"]),
        .testTarget(
            name: "RarExtractorCoreTests",
            dependencies: ["RarExtractorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
