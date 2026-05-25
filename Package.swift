// swift-tools-version: 5.7
// This Package.swift is for opening the project in Xcode.
// For building, run: `bash generate-xcodeproj.sh` then open the .xcodeproj.
import PackageDescription

let package = Package(
    name: "EasyTierManager",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EasyTierHelperShared",
            dependencies: [],
            path: "Sources/EasyTierHelperShared"
        ),
        .executableTarget(
            name: "EasyTierManager",
            dependencies: ["EasyTierHelperShared"],
            path: "Sources/EasyTierManager",
            resources: [.copy("../../VERSION")]
        ),
        .executableTarget(
            name: "EasyTierHelper",
            dependencies: ["EasyTierHelperShared"],
            path: "Sources/EasyTierHelper"
        )
    ]
)