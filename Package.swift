// swift-tools-version:5.9
// The game's rules, computer players and table layout as a small package, so
// the logic tests run anywhere Swift runs (including a cheap Linux machine),
// without Xcode. The app itself is built from Dominoes.xcodeproj, which
// compiles these same files.
import PackageDescription

let package = Package(
    name: "DominoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DominoCore", targets: ["DominoCore"]),
    ],
    targets: [
        .target(name: "DominoCore", path: "Dominoes/Core"),
        .testTarget(
            name: "DominoCoreTests",
            dependencies: ["DominoCore"],
            path: "Tests/DominoCoreTests",
            // Real answers from the game server, read by OnlineTests.
            exclude: ["Fixtures"]
        ),
    ]
)
