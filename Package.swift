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
            path: "Sources/Cursorcat",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CursorcatTests",
            dependencies: ["CursorCat"],
            path: "Tests/CursorcatTests"
        )
    ]
)
