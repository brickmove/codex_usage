// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexUsage", targets: ["CodexUsage"]),
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "UsageCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CodexUsage", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore", "CSQLite"]),
        .testTarget(name: "AppModelTests", dependencies: ["CodexUsage", "UsageCore"])
    ]
)
