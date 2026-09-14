// swift-tools-version: 5.9
// Sumbee: runtime-only manifest adapted from swift-transformers 1.1.6.
import PackageDescription
let package = Package(name: "swift-transformers", platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "Tokenizers", targets: ["Tokenizers"])],
    dependencies: [.package(path: "../swift-jinja"), .package(path: "../swift-collections")],
    targets: [
        .target(name: "Hub", dependencies: [.product(name: "Jinja", package: "swift-jinja"),
            .product(name: "OrderedCollections", package: "swift-collections")],
            resources: [.process("Resources")], swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "Tokenizers", dependencies: ["Hub", .product(name: "Jinja", package: "swift-jinja")])
    ])
