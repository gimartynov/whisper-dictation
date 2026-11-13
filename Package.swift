// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WhisperDictation",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WhisperDictation",
            path: "Sources/WhisperDictation",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
