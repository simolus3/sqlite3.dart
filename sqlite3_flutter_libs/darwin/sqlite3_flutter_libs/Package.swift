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
        .package(url: "https://github.com/sbooth/CSQLite.git", exact: "3.47.1")
    ],
    targets: [
        .target(
            name: "sqlite3_flutter_libs",
            dependencies: ["CSQLite"],
            resources: []
        )
    ]
)
