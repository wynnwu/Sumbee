// swift-tools-version: 6.0
// Sumbee: runtime-only manifest adapted from FluidAudio v0.12.4; see ../README.md.
import PackageDescription
let package = Package(name: "FluidAudio", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FluidAudio", targets: ["FluidAudio"])],
    dependencies: [.package(path: "../swift-transformers")],
    targets: [
        .target(name: "FluidAudio", dependencies: ["FastClusterWrapper", "MachTaskSelfWrapper",
            .product(name: "Tokenizers", package: "swift-transformers")],
            exclude: ["Frameworks/LICENSES"],
            cSettings: [.define("ACCELERATE_NEW_LAPACK")]),
        .target(name: "FastClusterWrapper", publicHeadersPath: "include"),
        .target(name: "MachTaskSelfWrapper", publicHeadersPath: "include")
    ], cxxLanguageStandard: .cxx17)
