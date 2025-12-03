// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LGTVMenuBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LGTVMenuBar", targets: ["LGTVMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "LGTVMenuBar",
            path: "Sources/LGTVMenuBar",
            exclude: ["Info.plist", "LGTVMenuBar.entitlements"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "LGTVMenuBarTests",
            dependencies: ["LGTVMenuBar"],
            path: "Tests/LGTVMenuBarTests"
        )
    ]
)
