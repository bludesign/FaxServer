import PackageDescription

let package = Package(
    name: "Server",
    targets: [
        Target(name: "Server"),
        Target(name: "App", dependencies: ["Server"])
    ],
    dependencies: [
        .Package(url: "https://github.com/vapor/vapor.git", majorVersion: 2),
        .Package(url: "https://github.com/vapor/leaf-provider.git", majorVersion: 1),
        .Package(url: "https://github.com/vapor/validation.git", majorVersion: 1),
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 4),
        .Package(url: "https://github.com/bludesign/vapor-apns", majorVersion: 2)
    ],
    exclude: [
        "Config",
        "Deploy",
        "Public",
        "Resources",
        "Tests",
        "Database"
    ]
)
