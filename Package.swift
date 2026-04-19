// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CursorCat",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CursorCat", targets: ["CursorCat"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "CursorCat",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CursorCat",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "CursorCatTests",
            dependencies: ["CursorCat"],
            path: "Tests/CursorCatTests"
        )
    ]
)
