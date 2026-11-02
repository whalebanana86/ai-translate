// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslateCore",
    // 화면 글의 원문 언어 (TASK-058). 번역은 Resources/Localizable.xcstrings
    defaultLocalization: "ko",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TranslateCore", targets: ["TranslateCore"])
    ],
    targets: [
        .target(name: "TranslateCore", resources: [.process("Resources")]),
        .testTarget(name: "TranslateCoreTests", dependencies: ["TranslateCore"]),
    ]
)
