// swift-tools-version: 6.0
// Linux-first pack. Evidence is the official `swift:6.0` container.
// Apple platforms (Darwin, iOS, tvOS, watchOS) are unproven.
//
// treatAllWarnings(as: .error) is SwiftPM 6.2+. On 6.0 we pass
// -warnings-as-errors through unsafeFlags (same compiler switch).
// -strict-memory-safety is the Swift 6.2 diagnostic group; 6.0 already
// enables complete concurrency checking via tools-version 6.0.

import PackageDescription

let strictSettings: [SwiftSetting] = [
  .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
  name: "Warehouse",
  products: [
    .library(name: "Warehouse", targets: ["Warehouse"])
  ],
  targets: [
    .target(
      name: "Warehouse",
      swiftSettings: strictSettings
    ),
    .testTarget(
      name: "WarehouseTests",
      dependencies: ["Warehouse"],
      swiftSettings: strictSettings
    ),
  ]
)
