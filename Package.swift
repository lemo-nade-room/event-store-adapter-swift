// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "event-store-adapter",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "EventStoreAdapter", targets: ["EventStoreAdapter"]),
        .library(name: "EventStoreAdapterDynamoDB", targets: ["EventStoreAdapterDynamoDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "EventStoreAdapter",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "EventStoreAdapterTests",
            dependencies: [
                .target(name: "EventStoreAdapter"),
                .target(name: "PackageTestUtil"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "EventStoreAdapterDynamoDB",
            dependencies: [
                .product(name: "AWSDynamoDB", package: "aws-sdk-swift"),
                .target(name: "EventStoreAdapter"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "EventStoreAdapterDynamoDBTests",
            dependencies: [
                .target(name: "EventStoreAdapterDynamoDB"),
                .target(name: "PackageTestUtil"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PackageTestUtil",
            dependencies: [
                .target(name: "EventStoreAdapter"),
                .target(name: "EventStoreAdapterDynamoDB"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
var swiftSettings: [SwiftSetting] {
    [
        .enableExperimentalFeature("StrictConcurrency"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
