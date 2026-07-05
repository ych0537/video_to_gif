// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoToGif",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "video-to-gif", targets: ["VideoToGif"]),
        .executable(name: "VideoToGifApp", targets: ["VideoToGifApp"])
    ],
    targets: [
        .target(
            name: "VideoToGifCore",
            path: "Sources/VideoToGifCore"
        ),
        .executableTarget(
            name: "VideoToGif",
            dependencies: ["VideoToGifCore"],
            path: "Sources/VideoToGif"
        ),
        .executableTarget(
            name: "VideoToGifApp",
            dependencies: ["VideoToGifCore"],
            path: "Sources/VideoToGifApp"
        )
    ]
)
