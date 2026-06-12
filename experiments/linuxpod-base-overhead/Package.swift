// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import PackageDescription

let package = Package(
    name: "linuxpod-base-overhead",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(
            name: "linuxpod-base-overhead",
            targets: ["LinuxPodBaseOverheadSpike"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/containerization.git", exact: "0.26.5")
    ],
    targets: [
        .executableTarget(
            name: "LinuxPodBaseOverheadSpike",
            dependencies: [
                .product(name: "Containerization", package: "containerization")
            ]
        )
    ]
)
