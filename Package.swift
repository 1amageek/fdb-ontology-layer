// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fdb-ontology-layer",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "OntologyLayer",
            targets: ["OntologyLayer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/foundationdb/fdb-swift-bindings.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "OntologyLayer",
            dependencies: [
                .product(name: "FoundationDB", package: "fdb-swift-bindings"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-warn-concurrency"])
            ]
        ),
        .testTarget(
            name: "OntologyLayerTests",
            dependencies: ["OntologyLayer"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
