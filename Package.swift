// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FirestoreRestDocuments",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
    .tvOS(.v13),
    .watchOS(.v7),
    .macCatalyst(.v13),
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
  ],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-dependencies",
      from: "1.2.0"
    ),
    .package(
      url: "https://github.com/apple/swift-log",
      from: "1.6.0"
    ),
  ],
  targets: [
    .target(
      name: "FirestoreRestDocuments",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .target(
      name: "FirestoreRestDocumentsDependencies",
      dependencies: [
        "FirestoreRestDocuments",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "FirestoreRestDocumentsTests",
      dependencies: [
        "FirestoreRestDocuments",
        "FirestoreRestDocumentsDependencies",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ]
    ),
  ]
)
