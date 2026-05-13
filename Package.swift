// swift-tools-version: 6.2
// 声明使用的 Swift 工具链版本，必须 <= 你安装的 Swift 版本 (6.2.4)

import PackageDescription

let package = Package(
    name: "TranSee",
    defaultLocalization: "en",
    // 修正：macOS 目前最高支持到 .v15 (macOS 15 Sequoia)。
    // .v26 是错误的版本号，会导致 SPM 无法解析平台特性。
    platforms: [
        .macOS(.v15) 
    ],
    products: [
        .executable(
            name: "sound2text",
            targets: ["sound2text"]
        )
    ],
    dependencies: [
        // 修正：去除 URL 末尾的空格，这可能导致 VS Code 插件解析失败
        .package(url: "https://github.com/elai950/AlertToast", .upToNextMajor(from: "1.3.9")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.6.1")),
        // 建议使用具体的 tag 或 commit 而不是 main 分支，以保证构建稳定性
        // 如果必须用 main，保持原样即可
        .package(url: "https://github.com/argmaxinc/whisperkit", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "sound2text",
            dependencies: [
                .product(name: "WhisperKit", package: "whisperkit"),
                .product(name: "AlertToast", package: "AlertToast"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "sound2text",
            exclude: [
                "Info.plist",
                "sound2text.entitlements",
                "Sources"
            ],
            resources: [
                .process("Assets.xcassets")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "TranSeeTests",
            dependencies: [.target(name: "sound2text")],
            path: "sound2textTests",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
)
