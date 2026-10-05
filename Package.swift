// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TimeIt",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "time-it-app", targets: ["TimeItApp"])],
    targets: [
        .target(name: "TimeItCore"),
        .executableTarget(name: "TimeItApp", dependencies: ["TimeItCore"]),
        .testTarget(name: "TimeItCoreTests", dependencies: ["TimeItCore"])
    ]
)
