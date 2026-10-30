// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslateCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TranslateCore", targets: ["TranslateCore"])
    ],
    targets: [
        .target(name: "TranslateCore"),
        .testTarget(name: "TranslateCoreTests", dependencies: ["TranslateCore"]),
    ]
)
