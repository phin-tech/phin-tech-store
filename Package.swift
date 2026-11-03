// swift-tools-version: 6.0
import PackageDescription

// PhinTechStoreKit holds everything that isn't UI, so `swift test` covers it headless. The app (project.yml) links it
// as a local package; Sparkle is an Xcode-only dependency and stays out of here.
let package = Package(
    name: "PhinTechStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PhinTechStoreKit", targets: ["PhinTechStoreKit"]),
    ],
    targets: [
        .target(name: "PhinTechStoreKit"),
        .testTarget(name: "PhinTechStoreKitTests", dependencies: ["PhinTechStoreKit"]),
    ]
)
