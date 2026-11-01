// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SiliciumKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SiliciumShared", targets: ["SiliciumShared"]),
        .library(name: "SiliciumSensors", targets: ["SiliciumSensors"]),
        .library(name: "SiliciumCore", targets: ["SiliciumCore"]),
        .library(name: "SiliciumStorage", targets: ["SiliciumStorage"]),
        .library(name: "SiliciumUI", targets: ["SiliciumUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(name: "SiliciumShared"),
        .target(name: "CSMC"),
        .target(name: "SiliciumSensors", dependencies: ["SiliciumShared", "CSMC"]),
        .target(name: "SiliciumCore", dependencies: ["SiliciumShared", "SiliciumSensors"]),
        .target(name: "SiliciumStorage", dependencies: [
            "SiliciumShared", .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "SiliciumUI", dependencies: [
            "SiliciumShared", "SiliciumCore", "SiliciumStorage",
        ]),
        .executableTarget(name: "silicium-probe", dependencies: ["SiliciumShared", "SiliciumSensors", "SiliciumCore"]),
        .testTarget(name: "SiliciumCoreTests", dependencies: ["SiliciumCore", "SiliciumShared"]),
        .testTarget(name: "SiliciumSensorsTests", dependencies: ["SiliciumSensors", "SiliciumShared"]),
        .testTarget(name: "SiliciumStorageTests", dependencies: ["SiliciumStorage", "SiliciumShared"]),
        .testTarget(name: "SiliciumUITests", dependencies: ["SiliciumUI", "SiliciumShared"]),
    ],
    swiftLanguageModes: [.v6]
)
