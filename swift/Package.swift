// swift-tools-version: 6.0
// Linux-first pack. Evidence is the official `swift:6.0` container.
// Apple platforms (Darwin, iOS, tvOS, watchOS) are unproven.

import PackageDescription

let package = Package(
  name: "Warehouse",
  products: [
    .library(name: "Warehouse", targets: ["Warehouse"])
  ],
  targets: [
    .target(name: "Warehouse"),
    .testTarget(
      name: "WarehouseTests",
      dependencies: ["Warehouse"]
    ),
  ]
)
