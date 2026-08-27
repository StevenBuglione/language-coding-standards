// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TypeViolation",
  products: [
    .library(name: "TypeViolation", targets: ["TypeViolation"])
  ],
  targets: [
    .target(name: "TypeViolation")
  ]
)
