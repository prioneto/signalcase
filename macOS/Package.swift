// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Signalcase",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Signalcase", targets: ["Signalcase"])
    ],
    targets: [
        .executableTarget(
            name: "Signalcase",
            path: "Sources/Signalcase"
        ),
        .testTarget(
            name: "SignalcaseTests",
            dependencies: ["Signalcase"],
            path: "Tests/SignalcaseTests"
        )
    ]
)

