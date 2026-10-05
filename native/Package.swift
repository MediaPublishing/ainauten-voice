// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceWispr",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VoiceWispr", targets: ["VoiceWispr"]), .executable(name: "VoiceWisprProbe", targets: ["VoiceWisprProbe"]), .library(name: "VoiceWisprCore", targets: ["VoiceWisprCore"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5", traits: []), .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.1")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .binaryTarget(name: "llama", path: "Vendor/build-apple/llama.xcframework"),
        .target(name: "VoiceWisprCore", dependencies: ["CSQLite", "llama", .product(name: "FluidAudio", package: "FluidAudio")], exclude: ["FreeFlow/LICENSE.txt"], resources: [.copy("Resources")], linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("AppKit"), .linkedFramework("ApplicationServices"), .linkedFramework("Security"), .linkedFramework("Carbon")]),
        .executableTarget(name: "VoiceWispr", dependencies: ["VoiceWisprCore", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "VoiceWisprProbe", dependencies: ["VoiceWisprCore", .product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "VoiceWisprCoreTests", dependencies: ["VoiceWisprCore", "CSQLite"])
    ],
    swiftLanguageModes: [.v5]
)
