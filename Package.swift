// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CursorCat",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CursorCat", targets: ["CursorCat"])
    ],
    targets: [
        .executableTarget(
            name: "CursorCat",
            path: "Sources/CursorCat",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CursorCatTests",
            dependencies: ["CursorCat"],
            path: "Tests/CursorCatTests"
        )
    ]
)
