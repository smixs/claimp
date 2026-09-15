// swift-tools-version: 6.3
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "Claimp",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "Claimp", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.14.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
        .package(url: "https://github.com/x-sheep/swift-property-based", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: strict),
        .target(
            name: "Playback",
            dependencies: [
                "Core",
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
            ],
            swiftSettings: strict),
        .target(
            name: "Waveform",
            dependencies: ["Core"],
            swiftSettings: strict),
        .executableTarget(
            name: "App",
            dependencies: ["Core", "Playback", "Waveform"],
            resources: [.copy("Resources/claimp-logo.svg")],
            swiftSettings: strict),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                .product(name: "PropertyBased", package: "swift-property-based"),
            ],
            swiftSettings: strict),
        .testTarget(
            name: "PlaybackTests",
            dependencies: [
                "Playback",
                .product(name: "PropertyBased", package: "swift-property-based"),
            ],
            swiftSettings: strict),
        .testTarget(
            name: "WaveformTests",
            dependencies: [
                "Waveform",
                .product(name: "PropertyBased", package: "swift-property-based"),
            ],
            swiftSettings: strict),
    ]
)
