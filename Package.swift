// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sumbee",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [.package(path: "Vendor/FluidAudio")],
    targets: [
        // All application logic and SwiftUI views live here so they can be unit-tested.
        .target(
            name: "SumbeeKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            resources: [.copy("Resources/meeting-models.json"), .copy("Resources/meeting-notices.txt")]
        ),
        // Thin shell: hosts the SwiftUI app lifecycle.
        .executableTarget(
            name: "Sumbee",
            dependencies: ["SumbeeKit"]
        ),
        .testTarget(
            name: "SumbeeKitTests",
            dependencies: ["SumbeeKit"]
        ),
    ],
    // v5 language mode for a frictionless first build; strict-concurrency migration is
    // a documented, isolated later step (see specs/.../research.md D7).
    swiftLanguageModes: [.v5]
)
