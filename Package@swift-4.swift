// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Server",
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/vapor/leaf-provider.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/vapor/validation.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/OpenKitten/MongoKitten.git", .upToNextMajor(from: "4.0.0")),
        .package(url: "https://github.com/bludesign/vapor-apns", .upToNextMajor(from: "2.0.1"))
    ],
    targets: [
        .target(name: "Server",
                dependencies: [
                    "Vapor",
                    "LeafProvider",
                    "Validation",
                    "MongoKitten",
                    "VaporAPNS"
                ],
                exclude: [
                    "Config",
                    "Deploy",
                    "Public",
                    "Resources",
                    "Tests",
                    "Database"
        ]),
        .target(name: "App", dependencies: ["Server"])
    ]
)
