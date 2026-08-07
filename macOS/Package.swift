// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Signalcase",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Signalcase", targets: ["Signalcase"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/supabase/supabase-swift.git",
            exact: "2.54.1"
        )
    ],
    targets: [
        .executableTarget(
            name: "Signalcase",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/Signalcase"
        ),
        .testTarget(
            name: "SignalcaseTests",
            dependencies: ["Signalcase"],
            path: "Tests/SignalcaseTests"
        )
    ]
)
