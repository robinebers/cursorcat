// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cursorcat",
    platforms: [
        .macOS(.v26)
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
