// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TToolkit",
    platforms: [
    	.macOS(.v10_14)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "TToolkit",
            targets: ["TToolkit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    	.package(url: "https://github.com/IBM-Swift/Swift-SMTP.git", .upToNextMinor(from:"5.1.1"),
    	.package(url: "https://github.com/tannerdsilva/Ctt_clone.git", .upToNextMinor(from:"1.0.1"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TToolkit",
            dependencies: ["SwiftSMTP", "Ctt_clone"]),
        .testTarget(
            name: "TToolkitTests",
            dependencies: ["TToolkit"]),
    ]
)
