// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cursorcat",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Cursorcat", targets: ["Cursorcat"])
    ],
    targets: [
        .executableTarget(
            name: "Cursorcat",
            path: "Sources/Cursorcat",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
