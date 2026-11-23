// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterTokenPanel",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BetterTokenPanel", targets: ["BetterTokenPanel"])],
    targets: [
        .executableTarget(name: "BetterTokenPanel", resources: [.copy("BalanceReader.js"), .copy("PanelDetector.js")])
    ]
)
