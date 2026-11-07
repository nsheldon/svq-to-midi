// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SVQKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SVQKit", targets: ["SVQKit"]),
        .executable(name: "svq2mid", targets: ["svq2mid"]),
    ],
    targets: [
        .target(name: "SVQKit"),
        .executableTarget(name: "svq2mid", dependencies: ["SVQKit"]),
        .testTarget(
            name: "SVQKitTests",
            dependencies: ["SVQKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
