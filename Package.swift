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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        // SSH to a rooted TV. Pinned exactly: 0.12.1 moved its SSH transport to an unvetted
        // third-party fork (Wellz26/swift-nio-ssh); 0.12.0 still uses the Citadel author's own.
        .package(url: "https://github.com/orlandos-nl/Citadel", exact: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "LGTVMenuBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Citadel", package: "Citadel")
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
