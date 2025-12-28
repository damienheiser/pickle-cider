// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleNotesTools",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "cider", targets: ["Cider"]),
        .executable(name: "pickle", targets: ["Pickle"]),
        .executable(name: "PickleCider", targets: ["PickleCider"]),
        .library(name: "CiderCore", targets: ["CiderCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.25.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CiderCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .executableTarget(
            name: "Cider",
            dependencies: [
                "CiderCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "Pickle",
            dependencies: [
                "CiderCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "PickleCider",
            dependencies: ["CiderCore"]
        ),
        .testTarget(
            name: "CiderCoreTests",
            dependencies: ["CiderCore"]
        ),
    ]
)
