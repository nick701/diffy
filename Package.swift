// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Diffy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Diffy", targets: ["Diffy"]),
        .library(name: "DiffyCore", targets: ["DiffyCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(name: "DiffyCore"),
        .executableTarget(
            name: "Diffy",
            dependencies: [
                "DiffyCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "DiffyCoreTests",
            dependencies: ["DiffyCore"]
        )
    ]
)
