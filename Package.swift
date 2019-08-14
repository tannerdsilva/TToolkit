// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TToolkit",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "TToolkit",
            targets: ["TToolkit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
		.package(url: "https://github.com/kareman/SwiftShell.git", .upToNextMinor(from:"5.0.0")),
		.package(url: "https://github.com/IBM-Swift/kitura.git", .upToNextMinor(from:"2.7.1")),
		.package(url: "https://github.com/IBM-Swift/BlueSSLService.git", .upToNextMinor(from:"1.0.48")),
		.package(url: "https://github.com/crossroadlabs/Regex.git", .upToNextMinor(from:"1.2.0")),
		.package(url: "https://github.com/IBM-Swift/kitura-net.git", .upToNextMinor(from:"2.3.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TToolkit",
            dependencies: ["SwiftShell", "Kitura", "SSLService", "Regex", "KituraNet"]),
        .testTarget(
            name: "TToolkitTests",
            dependencies: ["TToolkit"]),
    ]
)
