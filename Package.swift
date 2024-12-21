// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftWebSocketClient",
    platforms: [.iOS(.v16), .macOS(.v14), .macCatalyst(.v16), .visionOS(.v1), .tvOS(.v16), .watchOS(.v10)],
    products: [
        .library(
            name: "SwiftWebSocketClient",
            targets: ["SwiftWebSocketClient"]),
    ],
    targets: [
        .target(
            name: "SwiftWebSocketClient"),

    ]
)
