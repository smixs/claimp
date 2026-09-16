// swift-tools-version: 6.3
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "Claimp",
    platforms: [
        // Анализ BPM/тональности идёт через системный MusicUnderstanding (macOS 27).
        // Строковая форма, а не .v27: в PackageDescription этого тулчейна такого случая нет.
        .macOS("27.0"),
    ],
    products: [
        .executable(name: "Claimp", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.14.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
        .package(url: "https://github.com/x-sheep/swift-property-based", from: "2.0.0"),
        // Запись BPM и тональности в теги файла (T22). Версия та же, что уже стоит в
        // Package.resolved: TagLib приходит в граф вместе с SFBAudioEngine, качать нечего.
        .package(url: "https://github.com/sbooth/CXXTagLib", from: "2.3.2"),
        // Автообновление. Sparkle приезжает бинарным артефактом: сам Sparkle.framework
        // внутри xcframework плюс утилиты generate_keys/generate_appcast, которыми
        // пользуются цели Makefile.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
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
        // ObjC++ поверх TagLib: сам C++ наружу не торчит, Swift видит один класс с NSError.
        // Разделение на C-таргет и Swift-обёртку - приём SFBAudioEngine (CSFBAudioEngine +
        // SFBAudioEngine): смешанный таргет SwiftPM не собирает.
        .target(
            name: "CTagWriter",
            dependencies: [
                .product(name: "taglib", package: "CXXTagLib"),
            ]),
        .target(
            name: "TagWriter",
            dependencies: ["CTagWriter"],
            swiftSettings: strict),
        .target(
            name: "Analysis",
            dependencies: ["Core"],
            swiftSettings: strict),
        .target(
            name: "Waveform",
            dependencies: ["Core"],
            swiftSettings: strict),
        .executableTarget(
            name: "App",
            dependencies: [
                "Analysis", "Core", "Playback", "TagWriter", "Waveform",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.copy("Resources/claimp-logo.svg")],
            swiftSettings: strict),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                // Тест миграции v2 сам собирает базу версии v1 - для этого нужен GRDB напрямую.
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "PropertyBased", package: "swift-property-based"),
            ],
            swiftSettings: strict),
        .testTarget(
            name: "AnalysisTests",
            dependencies: [
                "Analysis",
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
            name: "TagWriterTests",
            dependencies: [
                // Читателем в тестах записи выступает штатный сканер плейлиста.
                "Core",
                "TagWriter",
            ],
            swiftSettings: strict),
        .testTarget(
            name: "WaveformTests",
            dependencies: [
                "Waveform",
                .product(name: "PropertyBased", package: "swift-property-based"),
            ],
            swiftSettings: strict),
    ],
    // TagLib требует C++17 (заголовки из CXXTagLib собираются вместе с нашим ObjC++).
    cxxLanguageStandard: .cxx17
)
