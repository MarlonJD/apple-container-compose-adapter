// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import PackageDescription

let package = Package(
    name: "container-compose-adapter",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ContainerComposeAdapter",
            targets: ["ContainerComposeAdapter"]
        ),
        .executable(
            name: "container-compose-adapter",
            targets: ["ContainerComposeAdapterCLI"]
        ),
        .executable(
            name: "container-compose-footprint-harness",
            targets: ["ContainerComposeAdapterFootprintHarness"]
        ),
        .executable(
            name: "container-compose-phase6-benchmark",
            targets: ["ContainerComposeAdapterPhase6Benchmark"]
        ),
        .executable(
            name: "container-compose-stage4-microbenchmarks",
            targets: ["ContainerComposeAdapterStage4Microbenchmarks"]
        ),
        .executable(
            name: "container-compose-stage5-backend-smoke",
            targets: ["ContainerComposeAdapterStage5BackendSmoke"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/containerization.git", exact: "0.26.5"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.0")
    ],
    targets: [
        .target(name: "ContainerComposeAdapter"),
        .target(
            name: "ContainerComposeAdapterLinuxPod",
            dependencies: [
                "ContainerComposeAdapter",
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationEXT4", package: "containerization"),
                .product(name: "SystemPackage", package: "swift-system")
            ]
        ),
        .executableTarget(
            name: "ContainerComposeAdapterCLI",
            dependencies: [
                "ContainerComposeAdapter",
                "ContainerComposeAdapterLinuxPod"
            ]
        ),
        .executableTarget(
            name: "ContainerComposeAdapterFootprintHarness",
            dependencies: [
                "ContainerComposeAdapter",
                "ContainerComposeAdapterLinuxPod"
            ]
        ),
        .executableTarget(
            name: "ContainerComposeAdapterPhase6Benchmark",
            dependencies: [
                "ContainerComposeAdapter",
                "ContainerComposeAdapterLinuxPod"
            ]
        ),
        .executableTarget(
            name: "ContainerComposeAdapterStage4Microbenchmarks",
            dependencies: ["ContainerComposeAdapter"]
        ),
        .executableTarget(
            name: "ContainerComposeAdapterStage5BackendSmoke",
            dependencies: ["ContainerComposeAdapter"]
        ),
        .testTarget(
            name: "ContainerComposeAdapterTests",
            dependencies: ["ContainerComposeAdapter"]
        )
    ]
)
