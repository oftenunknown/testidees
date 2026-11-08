// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OdysseyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "OdysseyKit", targets: ["OdysseyKit"])
    ],
    targets: [
        .target(name: "OdysseyKit"),
        .testTarget(name: "OdysseyKitTests", dependencies: ["OdysseyKit"])
    ]
)
