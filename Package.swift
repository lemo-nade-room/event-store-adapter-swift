// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "event-store-adaptor",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "EventStoreAdaptor",
            targets: [
                "EventStoreAdaptor"
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "EventStoreAdaptor",
            dependencies: [
                .product(name: "AWSDynamoDB", package: "aws-sdk-swift"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]),
        .testTarget(
            name: "EventStoreAdaptorTests",
            dependencies: [
                .target(name: "EventStoreAdaptor"),
                .target(name: "PackageTestUtil"),
            ]),
        .target(
            name: "PackageTestUtil",
            dependencies: [
                .target(name: "EventStoreAdaptor")
            ]),
    ]
)
