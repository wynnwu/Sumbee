// swift-tools-version: 6.0
// Sumbee: runtime-only manifest adapted from swift-jinja 2.0.0.
import PackageDescription
let package = Package(name: "Jinja", platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "Jinja", targets: ["Jinja"])],
    dependencies: [.package(path: "../swift-collections")],
    targets: [.target(name: "Jinja", dependencies: [.product(name: "OrderedCollections", package: "swift-collections")])])
