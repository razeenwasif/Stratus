// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stratus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Stratus", targets: ["Stratus"])
    ],
    targets: [
        .executableTarget(
            name: "Stratus",
            path: "Sources/Stratus"
        ),
        .testTarget(
            name: "StratusTests",
            dependencies: ["Stratus"],
            path: "Tests/StratusTests"
        )
    ]
)
