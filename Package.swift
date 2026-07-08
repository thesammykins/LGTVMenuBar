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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "LGTVMenuBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/LGTVMenuBar",
            exclude: ["Info.plist", "LGTVMenuBar.entitlements"],
            resources: [.copy("Resources")],
            swiftSettings: [
                .define("LOCAL_ARYLIC_BUILD")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "LGTVMenuBarTests",
            dependencies: ["LGTVMenuBar"],
            path: "Tests/LGTVMenuBarTests",
            swiftSettings: [
                .define("LOCAL_ARYLIC_BUILD")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../.."
                ])
            ]
        )
    ]
)
