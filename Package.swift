// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DontTouchIt",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "DontTouchIt", targets: ["DontTouchIt"])
    ],
    targets: [
        .executableTarget(name: "DontTouchIt")
    ],
    swiftLanguageModes: [.v5]
)
