// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PremierClone",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ProjectCore", targets: ["ProjectCore"]),
        .library(name: "TimelineCore", targets: ["TimelineCore"]),
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
        .library(name: "RenderCore", targets: ["RenderCore"]),
        .library(name: "AICore", targets: ["AICore"]),
        .library(name: "IOAdapters", targets: ["IOAdapters"]),
        .library(name: "AppShell", targets: ["AppShell"]),
        .executable(name: "PremierCloneApp", targets: ["PremierCloneApp"])
    ],
    targets: [
        .target(
            name: "ProjectCore"
        ),
        .target(
            name: "TimelineCore",
            dependencies: ["ProjectCore"]
        ),
        .target(
            name: "PlaybackCore",
            dependencies: ["ProjectCore"]
        ),
        .target(
            name: "RenderCore",
            dependencies: ["ProjectCore"]
        ),
        .target(
            name: "AICore",
            dependencies: ["ProjectCore", "TimelineCore"]
        ),
        .target(
            name: "IOAdapters",
            dependencies: ["ProjectCore"]
        ),
        .target(
            name: "AppShell",
            dependencies: [
                "ProjectCore",
                "TimelineCore",
                "PlaybackCore",
                "RenderCore",
                "AICore",
                "IOAdapters"
            ]
        ),
        .executableTarget(
            name: "PremierCloneApp",
            dependencies: ["AppShell"]
        ),
        .testTarget(
            name: "ProjectCoreTests",
            dependencies: ["ProjectCore"]
        ),
        .testTarget(
            name: "TimelineCoreTests",
            dependencies: ["TimelineCore", "ProjectCore"]
        ),
        .testTarget(
            name: "RenderCoreTests",
            dependencies: ["RenderCore", "ProjectCore"]
        ),
        .testTarget(
            name: "AICoreTests",
            dependencies: ["AICore", "ProjectCore"]
        ),
        .testTarget(
            name: "IOAdaptersTests",
            dependencies: ["IOAdapters", "ProjectCore"]
        )
    ]
)
