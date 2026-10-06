// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "FanKit", dependencies: ["CSMC"]),
        .executableTarget(name: "FanHelper", dependencies: ["FanKit"]),
        .executableTarget(name: "FanControl", dependencies: ["FanKit"]),
        .executableTarget(name: "smcprobe", dependencies: ["FanKit"]),
    ]
)
