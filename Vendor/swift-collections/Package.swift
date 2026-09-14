// swift-tools-version: 5.7
// Copyright (c) 2021 - 2024 Apple Inc. and the Swift project authors.
// Apache-2.0 with Runtime Library Exception; see LICENSE.txt.
// Sumbee: runtime-only manifest adapted from swift-collections 1.1.4.
import PackageDescription
let package = Package(name: "swift-collections",
    products: [.library(name: "OrderedCollections", targets: ["OrderedCollections"])],
    targets: [
        .target(name: "InternalCollectionsUtilities", swiftSettings: [.define("COLLECTIONS_RANDOMIZED_TESTING")]),
        .target(name: "OrderedCollections", dependencies: ["InternalCollectionsUtilities"],
                swiftSettings: [.define("COLLECTIONS_RANDOMIZED_TESTING")])
    ])
