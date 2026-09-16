// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "event-store-adapter",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EventStoreAdapter", targets: ["EventStoreAdapter"]),
    .library(name: "EventStoreAdapterDynamoDB", targets: ["EventStoreAdapterDynamoDB"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-configuration", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    .package(url: "https://github.com/soto-project/soto-core.git", from: "7.0.0"),
    .package(url: "https://github.com/apple/swift-system.git", from: "1.6.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "EventStoreAdapter",
      swiftSettings: swiftSettings,
    ),
    .target(
      name: "EventStoreAdapterDynamoDB",
      dependencies: [
        .product(name: "Configuration", package: "swift-configuration"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SotoDynamoDB", package: "soto"),
        .target(name: "EventStoreAdapter"),
      ],
      swiftSettings: swiftSettings,
    ),
    .testTarget(
      name: "EventStoreAdapterDynamoDBTests",
      dependencies: [
        .target(name: "EventStoreAdapter"),
        .target(name: "EventStoreAdapterDynamoDB"),
        .product(name: "Configuration", package: "swift-configuration"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SotoDynamoDB", package: "soto"),
        .product(name: "SystemPackage", package: "swift-system"),
      ],
      swiftSettings: swiftSettings,
    ),
  ],
  swiftLanguageModes: [.v6],
)
var swiftSettings: [SwiftSetting] {
  [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
  ]
}
