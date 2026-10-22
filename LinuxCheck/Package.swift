// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RawLookCore", products: [.library(name: "RawLookCore", targets: ["RawLookCore"])],
  targets: [
    .target(name: "RawLookCore", path: "Sources"),
    .testTarget(name: "RawLookCoreTests", dependencies: ["RawLookCore"], path: "Tests")
  ])
