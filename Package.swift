// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PasteDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClipboardCore",
            targets: ["ClipboardCore"]
        ),
        .executable(
            name: "PasteDock",
            targets: ["PasteDock"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "ClipboardCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "PasteDock",
            dependencies: ["ClipboardCore"]
        ),
        .testTarget(
            name: "ClipboardCoreTests",
            dependencies: ["ClipboardCore"]
        ),
        .testTarget(
            name: "PasteDockTests",
            dependencies: ["PasteDock"]
        )
    ]
)
