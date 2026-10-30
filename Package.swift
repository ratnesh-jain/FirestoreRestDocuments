// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FirestoreRestDocuments",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
    .tvOS(.v16),
    .watchOS(.v9),
    .macCatalyst(.v16),
    .visionOS(.v1),
  ],
  products: [
    .library(
      name: "FirestoreRestDocuments",
      targets: ["FirestoreRestDocuments"]
    ),
    .library(
      name: "FirestoreRestDocumentsDependencies",
      targets: ["FirestoreRestDocumentsDependencies"]
    ),
    .executable(
      name: "frd",
      targets: ["FirestoreCLI"]
    ),
    .library(
      name: "FirestoreMCPServer",
      targets: ["FirestoreMCPServer"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      from: "1.5.0"
    ),
    .package(
      url: "https://github.com/modelcontextprotocol/swift-sdk.git",
      from: "0.11.0"
    ),
    .package(
      url: "https://github.com/pointfreeco/swift-dependencies",
      from: "1.2.0"
    ),
    .package(
      url: "https://github.com/apple/swift-log",
      from: "1.6.0"
    ),
    .package(
      url: "https://github.com/apple/swift-crypto.git",
      "3.0.0"..<"6.0.0"
    ),
  ],
  targets: [
    .target(
      name: "FirestoreRestDocuments",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "_CryptoExtras", package: "swift-crypto"),
      ]
    ),
    .target(
      name: "FirestoreRestDocumentsDependencies",
      dependencies: [
        "FirestoreRestDocuments",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .target(
      name: "FirestoreOperations",
      dependencies: [
        "FirestoreRestDocuments",
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .target(
      name: "FirestoreCLICore",
      dependencies: [
        "FirestoreRestDocuments",
        "FirestoreOperations",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .executableTarget(
      name: "FirestoreCLI",
      dependencies: ["FirestoreCLICore"]
    ),
    .target(
      name: "FirestoreMCPServer",
      dependencies: [
        "FirestoreRestDocuments",
        "FirestoreOperations",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .executableTarget(
      name: "FirestoreMCP",
      dependencies: ["FirestoreMCPServer", "FirestoreOperations"]
    ),
    .testTarget(
      name: "FirestoreRestDocumentsTests",
      dependencies: [
        "FirestoreRestDocuments",
        "FirestoreRestDocumentsDependencies",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "FirestoreCLICoreTests",
      dependencies: [
        "FirestoreCLICore",
        "FirestoreOperations",
        "FirestoreRestDocuments",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "FirestoreMCPServerTests",
      dependencies: [
        "FirestoreMCPServer",
        "FirestoreOperations",
        "FirestoreRestDocuments",
        .product(name: "MCP", package: "swift-sdk"),
      ]
    ),
  ]
)
