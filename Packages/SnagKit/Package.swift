// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnagKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SnagKit", targets: ["SnagKit"])
    ],
    targets: [
        .target(name: "SnagKit"),
        .testTarget(name: "SnagKitTests", dependencies: ["SnagKit"])
    ]
)
