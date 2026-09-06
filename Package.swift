// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TimetableWallpaper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TimetableWallpaper", targets: ["TimetableWallpaper"])],
    targets: [
        .executableTarget(name: "TimetableWallpaper"),
        .testTarget(name: "TimetableWallpaperTests", dependencies: ["TimetableWallpaper"])
    ]
)
