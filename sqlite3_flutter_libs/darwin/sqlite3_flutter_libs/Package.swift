// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sqlite3_flutter_libs",
    platforms: [
        .iOS("12.0"),
        .macOS("10.14")
    ],
    products: [
        .library(name: "sqlite3-flutter-libs", type: .static, targets: ["sqlite3_flutter_libs"])
    ],
    dependencies: [
        .package(url: "https://github.com/simolus3/CSQLite.git", revision: "7381ec26064b49105594dc13508d8de303607c2f")
    ],
    targets: [
        .target(
            name: "sqlite3_flutter_libs",
            dependencies: ["CSQLite"],
            resources: []
        )
    ]
)
