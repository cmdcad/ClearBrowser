// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BingBot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BingBot", targets: ["BingBot"])],
    targets: [
        .executableTarget(name: "BingBot", path: "ClearBrowser/Views/BingBot", exclude: ["README.md"]),
        .testTarget(name: "BingBotTests", dependencies: ["BingBot"], path: "tests/BingBotTests")
    ]
)
