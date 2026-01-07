// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Jabber",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Jabber", targets: ["Jabber"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Jabber",
            dependencies: ["WhisperKit"],
            path: "Sources/Jabber",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
