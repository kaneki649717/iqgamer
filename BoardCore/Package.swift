// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BoardCore",
    products: [
        .library(name: "BoardCore", targets: ["BoardCore"])
    ],
    targets: [
        .target(name: "BoardCore"),
        .testTarget(name: "BoardCoreTests", dependencies: ["BoardCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
