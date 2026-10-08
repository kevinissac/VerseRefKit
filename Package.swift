// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VerseRefKit",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "VerseRefKit", targets: ["VerseRefKit"]),
    ],
    targets: [
        .target(name: "VerseRefKit"),
        .testTarget(name: "VerseRefKitTests", dependencies: ["VerseRefKit"]),
    ]
)
