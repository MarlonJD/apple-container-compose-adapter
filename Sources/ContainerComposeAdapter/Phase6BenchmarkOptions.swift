// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum Phase6IterationCleanupPolicy: String, Codable, Equatable, Sendable {
    case fullProjectAndVolumes
    case preserveVolumes
    case preserveProjectRuntime
}

public struct Phase6BenchmarkOptions: Equatable, Sendable {
    public var iterations = 1
    public var projectPrefix = "phase6-backend"
    public var runLabel = "phase6-smoke"
    public var lifecycle: BenchmarkLifecycle = .cold
    public var lifecycleMode: BenchmarkLifecycleMode?
    public var evidencePath: String?
    public var approvalToken: String?
    public var composeFile: String?
    public var seedImageStore: String?
    public var prepareSeedImageStore: String?
    public var dockerHubMirror: String?
    public var allowExternalSeedImageStore = false

    public var effectiveSeedImageStore: String? {
        seedImageStore ?? prepareSeedImageStore
    }

    public var effectiveLifecycleMode: BenchmarkLifecycleMode {
        lifecycleMode ?? BenchmarkLifecycleMode.compatibilityDefault(for: lifecycle)
    }

    public func projectName(forIteration iteration: Int) -> String {
        switch effectiveLifecycleMode {
        case .warmPreservedVolume, .persistentPodHotplug, .allWarmProjectRuntime:
            return "\(projectPrefix)-\(runLabel)-shared"
        case .coldRuntime,
             .imageStoreSeededFreshRuntime,
             .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime:
            return "\(projectPrefix)-\(runLabel)-\(String(format: "%03d", iteration))"
        }
    }

    public func cleanupPolicy(isFinalIteration: Bool) -> Phase6IterationCleanupPolicy {
        if isFinalIteration {
            return .fullProjectAndVolumes
        }
        switch effectiveLifecycleMode {
        case .warmPreservedVolume:
            return .preserveVolumes
        case .persistentPodHotplug, .allWarmProjectRuntime:
            return .preserveProjectRuntime
        case .coldRuntime,
             .imageStoreSeededFreshRuntime,
             .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime:
            return .fullProjectAndVolumes
        }
    }

    public static func parse(_ args: [String]) throws -> Phase6BenchmarkOptions {
        var options = Phase6BenchmarkOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--iterations":
                index += 1
                guard index < args.count, let iterations = Int(args[index]), iterations > 0 else {
                    throw Phase6BenchmarkOptionsError.usage("--iterations requires a positive integer")
                }
                options.iterations = iterations
            case "--project-prefix":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw Phase6BenchmarkOptionsError.usage("--project-prefix requires a value")
                }
                options.projectPrefix = args[index]
            case "--run-label":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw Phase6BenchmarkOptionsError.usage("--run-label requires a value")
                }
                options.runLabel = args[index]
            case "--lifecycle":
                index += 1
                guard index < args.count, let lifecycle = phase6Lifecycle(named: args[index]) else {
                    throw Phase6BenchmarkOptionsError.usage(
                        "--lifecycle must be cold, image-store-seeded-fresh-runtime, or persistent-warm-project-runtime"
                    )
                }
                options.lifecycle = lifecycle
                options.lifecycleMode = BenchmarkLifecycleMode.compatibilityDefault(for: lifecycle)
            case "--lifecycle-mode":
                index += 1
                guard index < args.count, let lifecycleMode = phase8LifecycleMode(named: args[index]) else {
                    throw Phase6BenchmarkOptionsError.usage(
                        "--lifecycle-mode must be cold-runtime, image-store-seeded-fresh-runtime, rootfs-cache-hit-runtime, initfs-cache-hit-runtime, warm-preserved-volume, persistent-pod-hotplug, or all-warm-project-runtime"
                    )
                }
                options.lifecycleMode = lifecycleMode
                options.lifecycle = lifecycleMode.legacyLifecycle
            case "--evidence-jsonl":
                index += 1
                guard index < args.count else {
                    throw Phase6BenchmarkOptionsError.usage("--evidence-jsonl requires a path")
                }
                options.evidencePath = args[index]
            case "--approval-token":
                index += 1
                guard index < args.count else {
                    throw Phase6BenchmarkOptionsError.usage("--approval-token requires a value")
                }
                options.approvalToken = args[index]
            case "--compose-file":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw Phase6BenchmarkOptionsError.usage("--compose-file requires a path")
                }
                options.composeFile = args[index]
            case "--seed-image-store":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw Phase6BenchmarkOptionsError.usage("--seed-image-store requires a path")
                }
                options.seedImageStore = args[index]
            case "--prepare-seed-image-store":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw Phase6BenchmarkOptionsError.usage("--prepare-seed-image-store requires a path")
                }
                options.prepareSeedImageStore = args[index]
            case "--allow-external-seed-image-store":
                options.allowExternalSeedImageStore = true
            case "--docker-hub-mirror":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw Phase6BenchmarkOptionsError.usage("--docker-hub-mirror requires a registry host or host/path prefix")
                }
                options.dockerHubMirror = try DockerHubOfficialImageMirror.validatedMirror(args[index])
            case "--help", "-h":
                throw Phase6BenchmarkOptionsError.usage(Self.usage())
            default:
                throw Phase6BenchmarkOptionsError.usage("unknown argument: \(arg)\n\n\(Self.usage())")
            }
            index += 1
        }
        if let prepareSeedImageStore = options.prepareSeedImageStore,
           let seedImageStore = options.seedImageStore,
           prepareSeedImageStore != seedImageStore {
            throw Phase6BenchmarkOptionsError.usage(
                "--prepare-seed-image-store and --seed-image-store must use the same path when both are provided"
            )
        }
        if let seedPath = options.effectiveSeedImageStore {
            try Phase6SeedImageStorePolicy.validateSeedPathOwnership(
                seedPath,
                allowExternal: options.allowExternalSeedImageStore
            )
        }
        guard options.evidencePath != nil else {
            throw Phase6BenchmarkOptionsError.usage("--evidence-jsonl is required")
        }
        return options
    }

    public static func usage() -> String {
        """
        Usage: container-compose-phase6-benchmark --evidence-jsonl path --approval-token token [--iterations n] [--project-prefix name] [--run-label label] [--lifecycle cold|image-store-seeded-fresh-runtime|persistent-warm-project-runtime] [--lifecycle-mode cold-runtime|image-store-seeded-fresh-runtime|rootfs-cache-hit-runtime|initfs-cache-hit-runtime|warm-preserved-volume|persistent-pod-hotplug|all-warm-project-runtime] [--compose-file path] [--seed-image-store path] [--prepare-seed-image-store path] [--allow-external-seed-image-store] [--docker-hub-mirror mirror.gcr.io]
        """
    }

    private static func phase6Lifecycle(named value: String) -> BenchmarkLifecycle? {
        switch value {
        case BenchmarkLifecycle.cold.rawValue:
            return .cold
        case BenchmarkLifecycle.imageStoreSeededFreshRuntime.rawValue:
            return .imageStoreSeededFreshRuntime
        case BenchmarkLifecycle.persistentWarmProjectRuntime.rawValue:
            return .persistentWarmProjectRuntime
        default:
            return nil
        }
    }

    private static func phase8LifecycleMode(named value: String) -> BenchmarkLifecycleMode? {
        BenchmarkLifecycleMode(rawValue: value)
    }
}

public enum Phase6BenchmarkOptionsError: Error, CustomStringConvertible, Equatable {
    case usage(String)

    public var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

public enum Phase6SeedImageStorePolicy {
    public static let sentinelFileName = ".container-compose-adapter-seed-image-store"
    public static let cacheDirectoryComponents = [
        ".container-compose-adapter",
        "benchmark-seed-image-stores"
    ]

    public static func adapterOwnedSeedCacheDirectory(
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> URL {
        cacheDirectoryComponents.reduce(repositoryRoot.standardizedFileURL) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }

    public static func validateSeedPathOwnership(
        _ path: String,
        allowExternal: Bool,
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws {
        let url = absoluteURL(for: path, repositoryRoot: repositoryRoot)
        try validateSeedPathOwnership(url, allowExternal: allowExternal, repositoryRoot: repositoryRoot)
    }

    public static func validateSeedPathOwnership(
        _ url: URL,
        allowExternal: Bool,
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws {
        guard allowExternal || isAdapterOwnedSeedPath(url, repositoryRoot: repositoryRoot) else {
            throw Phase6BenchmarkOptionsError.usage(
                "seed image-store path \(url.path) is outside adapter-owned benchmark seed cache \(adapterOwnedSeedCacheDirectory(repositoryRoot: repositoryRoot).path); pass --allow-external-seed-image-store to override"
            )
        }
    }

    public static func validateSeedSource(
        _ url: URL,
        allowExternal: Bool,
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws {
        try validateSeedPathOwnership(url, allowExternal: allowExternal, repositoryRoot: repositoryRoot)
        let sentinel = url.appendingPathComponent(sentinelFileName)
        guard allowExternal || FileManager.default.fileExists(atPath: sentinel.path) else {
            throw Phase6BenchmarkOptionsError.usage(
                "seed image-store source \(url.path) is missing sentinel \(sentinelFileName)"
            )
        }
    }

    public static func writeSentinel(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent(sentinelFileName)
        if !FileManager.default.fileExists(atPath: sentinel.path) {
            try Data("Container Compose Adapter seed image store\n".utf8).write(to: sentinel, options: .atomic)
        }
    }

    public static func assertCleanupDoesNotTargetSeedSource(
        cleanupTarget: URL,
        seedSource: URL
    ) throws {
        let cleanupPath = cleanupTarget.standardizedFileURL.path
        let seedPath = seedSource.standardizedFileURL.path
        let cleanupPrefix = cleanupPath.hasSuffix("/") ? cleanupPath : cleanupPath + "/"
        guard cleanupPath != seedPath,
              !seedPath.hasPrefix(cleanupPrefix) else {
            throw Phase6BenchmarkOptionsError.usage(
                "refusing cleanup target \(cleanupTarget.path) because it contains seed image-store source \(seedSource.path)"
            )
        }
    }

    public static func isAdapterOwnedSeedPath(
        _ url: URL,
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> Bool {
        isDescendant(url.standardizedFileURL, of: adapterOwnedSeedCacheDirectory(repositoryRoot: repositoryRoot))
    }

    public static func absoluteURL(
        for path: String,
        repositoryRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        return repositoryRoot.appendingPathComponent(expanded, isDirectory: true).standardizedFileURL
    }

    private static func isDescendant(_ url: URL, of base: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == "/" + basePath || path.hasPrefix("/" + basePath + "/")
    }
}
