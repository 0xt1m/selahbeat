// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SelahBeat",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SelahBeatCore", targets: ["SelahBeatCore"]),
        .library(name: "SelahBeatUI", targets: ["SelahBeatUI"]),
    ],
    targets: [
        // The only real-time-critical code. Plain C so the audio render path
        // never touches the Swift runtime (no ARC, no allocation, no locks).
        .target(name: "SelahBeatAudioC"),

        .target(
            name: "SelahBeatCore",
            dependencies: ["SelahBeatAudioC"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .target(
            name: "SelahBeatUI",
            dependencies: ["SelahBeatCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // A real end-to-end check against actual CoreAudio hardware: builds the
        // live engine, starts it, and confirms ticks are being emitted. Kept
        // out of the test suite so CI (which has no audio device) stays green.
        .executableTarget(
            name: "AudioCheck",
            dependencies: ["SelahBeatCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .testTarget(
            name: "SelahBeatCoreTests",
            dependencies: ["SelahBeatCore", "SelahBeatAudioC"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
