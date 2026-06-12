// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import ContainerComposeAdapterLinuxPod
import Containerization
import Foundation

@main
struct Phase6BenchmarkHarness {
    static func main() async {
        do {
            let options = try Phase6BenchmarkOptions.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(64)
        }
    }

    private static func run(_ options: Phase6BenchmarkOptions) async throws {
        guard options.approvalToken == LinuxPodBackend.runtimeApprovalToken else {
            throw HarnessError.usage(
                "Phase 6 LinuxPod benchmark requires --approval-token \(LinuxPodBackend.runtimeApprovalToken)"
            )
        }
        let approval = RuntimeApproval(approved: true, token: options.approvalToken)
        let executor = ContainerizationLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        var records: [Phase6BenchmarkIterationRecord] = []

        if let prepareSeedImageStore = options.prepareSeedImageStore {
            let seedPlan = try makePlan(
                options: options,
                projectName: "\(options.projectPrefix)-\(options.runLabel)-seed"
            )
            FileHandle.standardError.write(
                Data("phase6-benchmark: preparing seed image store at \(prepareSeedImageStore)\n".utf8)
            )
            try await Self.prepareSeedImageStore(path: prepareSeedImageStore, plan: seedPlan, options: options)
        }

        for iteration in 1...options.iterations {
            let projectName = options.projectName(forIteration: iteration)
            let plan = try makePlan(options: options, projectName: projectName)
            let projectResource = backend.stateStore.projectName(for: plan.project)
            let projectDirectory = backend.stateStore.projectDirectory(for: plan.project)
            let cleanupPolicy = options.cleanupPolicy(isFinalIteration: iteration == options.iterations)

            FileHandle.standardError.write(Data("phase6-benchmark: \(options.runLabel) iteration \(iteration)/\(options.iterations) up\n".utf8))
            let record = await runIteration(
                iteration: iteration,
                options: options,
                plan: plan,
                projectResource: projectResource,
                projectDirectory: projectDirectory,
                cleanupPolicy: cleanupPolicy,
                backend: backend,
                executor: executor,
                approval: approval
            )
            try appendJSONLine(record, path: options.evidencePath)
            records.append(record)
        }

        let summary = Phase6BenchmarkSummaryRecord(
            timestamp: iso8601Now(),
            projectPrefix: options.projectPrefix,
            runLabel: options.runLabel,
            requestedIterations: options.iterations,
            records: records
        )
        try appendJSONLine(summary, path: options.evidencePath)
        print("phase6-benchmark: completed \(options.iterations) iteration(s); evidence at \(options.evidencePath ?? "")")
    }

    // Image-store-seeded fresh-runtime iterations copy a prepared local image
    // store into a fresh project runtime. Rootfs/initfs/volumes/pods remain cold.
    private static func seedImageStoreIfRequested(
        options: Phase6BenchmarkOptions,
        plan: RuntimePlan,
        backend: LinuxPodBackend
    ) async throws -> SeedImageStoreCopyResult {
        let runtimeDirectory = backend.stateStore.runtimeDirectory(for: plan.project)
        let existedBeforeSeed = FileManager.default.fileExists(atPath: runtimeDirectory.path)
        guard let seed = options.effectiveSeedImageStore else {
            return SeedImageStoreCopyResult.notRequested(
                projectRuntimeDirectoryExistedBeforeSeed: existedBeforeSeed
            )
        }
        let seedURL = Phase6SeedImageStorePolicy.absoluteURL(for: seed)
        try Phase6SeedImageStorePolicy.validateSeedSource(
            seedURL,
            allowExternal: options.allowExternalSeedImageStore
        )
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let target = runtimeDirectory.appendingPathComponent("image-store", isDirectory: true)
        try Phase6SeedImageStorePolicy.assertCleanupDoesNotTargetSeedSource(
            cleanupTarget: runtimeDirectory,
            seedSource: seedURL
        )
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: seedURL, to: target)
        let imageCacheStatus = await verifiedImageCacheStatus(imageStorePath: target, plan: plan)
        return SeedImageStoreCopyResult(
            requested: true,
            copied: true,
            validated: imageCacheStatus == .verifiedHit,
            path: seed,
            projectRuntimeDirectoryExistedBeforeSeed: existedBeforeSeed,
            imageCacheStatus: imageCacheStatus
        )
    }

    private static func prepareSeedImageStore(
        path: String,
        plan: RuntimePlan,
        options: Phase6BenchmarkOptions
    ) async throws {
        let seedURL = Phase6SeedImageStorePolicy.absoluteURL(for: path)
        try Phase6SeedImageStorePolicy.validateSeedPathOwnership(
            seedURL,
            allowExternal: options.allowExternalSeedImageStore
        )
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: seedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw HarnessError.usage("--prepare-seed-image-store must point to a directory path")
        }

        try FileManager.default.createDirectory(at: seedURL, withIntermediateDirectories: true)
        let imageStore = try ImageStore(path: seedURL)
        if !(await imageStoreContainsLinuxArmReference(
            imageStore,
            reference: ContainerizationLinuxPodRuntimeExecutor.defaultInitImageReference
        )) {
            _ = try await imageStore.getInitImage(
                reference: ContainerizationLinuxPodRuntimeExecutor.defaultInitImageReference
            )
        }

        for image in Set(plan.services.map(\.image)).sorted() {
            if await imageStoreContainsLinuxArmReference(imageStore, reference: image) {
                FileHandle.standardError.write(
                    Data("phase6-benchmark: validated existing linux/arm64 image \(image)\n".utf8)
                )
                continue
            }
            FileHandle.standardError.write(Data("phase6-benchmark: seeding linux/arm64 image \(image)\n".utf8))
            _ = try await imageStore.pull(
                reference: image,
                platform: SystemPlatform.linuxArm.ociPlatform()
            )
        }
        try Phase6SeedImageStorePolicy.writeSentinel(in: seedURL)
    }

    private static func imageStoreContainsLinuxArmReference(
        _ imageStore: ImageStore,
        reference: String
    ) async -> Bool {
        do {
            let image = try await imageStore.get(reference: reference)
            _ = try await image.manifest(for: SystemPlatform.linuxArm.ociPlatform())
            return true
        } catch {
            return false
        }
    }

    private static func verifiedImageCacheStatus(
        imageStorePath: URL,
        plan: RuntimePlan
    ) async -> BenchmarkCacheStatus {
        do {
            let imageStore = try ImageStore(path: imageStorePath)
            let references = Set(
                plan.services.map(\.image)
                    + [ContainerizationLinuxPodRuntimeExecutor.defaultInitImageReference]
            )
            var results: [Bool] = []
            for reference in references {
                results.append(await imageStoreContainsLinuxArmReference(imageStore, reference: reference))
            }
            guard !results.isEmpty else {
                return .invalid
            }
            if results.allSatisfy({ $0 }) {
                return .verifiedHit
            }
            return results.contains(true) ? .partialHit : .invalid
        } catch {
            return .invalid
        }
    }

    private static func makePlan(options: Phase6BenchmarkOptions, projectName: String) throws -> RuntimePlan {
        let plan: RuntimePlan
        if let composeFile = options.composeFile {
            let frontendResult = try ComposeFrontend().parseProject(
                fileURL: URL(fileURLWithPath: composeFile),
                projectName: projectName
            )
            plan = AppleNativePlanner().plan(frontendResult.project).runtimePlan
        } else {
            plan = SamplePlans.publicBackendShaped(project: ProjectName(projectName))
        }
        return DockerHubOfficialImageMirror.rewrite(plan: plan, mirror: options.dockerHubMirror)
    }

    private static func runIteration(
        iteration: Int,
        options: Phase6BenchmarkOptions,
        plan: RuntimePlan,
        projectResource: String,
        projectDirectory: URL,
        cleanupPolicy: Phase6IterationCleanupPolicy,
        backend: LinuxPodBackend,
        executor: ContainerizationLinuxPodRuntimeExecutor,
        approval: RuntimeApproval
    ) async -> Phase6BenchmarkIterationRecord {
        var upDuration: Double?
        var statusDuration: Double?
        var logsDuration: Double?
        var cleanupDuration: Double?
        var guest: HostFootprintGuestStats?
        var actionCount = 0
        var upActionResults: [RuntimeActionResult] = []
        var seedResult = SeedImageStoreCopyResult.notRequested(
            projectRuntimeDirectoryExistedBeforeSeed: FileManager.default.fileExists(
                atPath: backend.stateStore.runtimeDirectory(for: plan.project).path
            )
        )
        var environment = benchmarkEnvironment(
            options: options,
            plan: plan,
            backend: backend,
            projectDirectory: projectDirectory,
            seedResult: seedResult
        )

        do {
            seedResult = try await seedImageStoreIfRequested(options: options, plan: plan, backend: backend)
            environment = benchmarkEnvironment(
                options: options,
                plan: plan,
                backend: backend,
                projectDirectory: projectDirectory,
                seedResult: seedResult
            )
            let upStarted = Date()
            let up = try await backend.execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(),
                approval: approval
            )
            upDuration = elapsedSeconds(since: upStarted)
            upActionResults = up.actionResults
            actionCount += up.actionResults.count

            guest = try await executor.guestStatistics(project: projectResource)

            let statusStarted = Date()
            let status = try await backend.execute(
                command: .status,
                plan: plan,
                options: RuntimeOptions(),
                approval: RuntimeApproval()
            )
            statusDuration = elapsedSeconds(since: statusStarted)
            actionCount += status.actionResults.count

            let logsStarted = Date()
            let logs = try await backend.execute(
                command: .logs,
                plan: plan,
                options: RuntimeOptions(),
                approval: RuntimeApproval()
            )
            logsDuration = elapsedSeconds(since: logsStarted)
            actionCount += logs.actionResults.count

            let dataFootprintBeforeCleanup = dataFootprintBytes(projectDirectory)
            let cleanupStarted = Date()
            let cleanup = try await cleanupAfterIteration(
                cleanupPolicy,
                backend: backend,
                plan: plan,
                approval: approval
            )
            cleanupDuration = elapsedSeconds(since: cleanupStarted)
            actionCount += cleanup.actionResults.count
            let cleanupResult = cleanupResultValue(
                cleanupPolicy,
                projectDirectory: projectDirectory
            )

            return Phase6BenchmarkIterationRecord(
                timestamp: iso8601Now(),
                project: projectResource,
                runLabel: options.runLabel,
                iteration: iteration,
                environment: environment,
                status: .measured,
                durationsSeconds: Phase6BenchmarkDurations(
                    up: upDuration,
                    status: statusDuration,
                    logs: logsDuration,
                    cleanup: cleanupDuration,
                    rootfsPrep: duration(
                        upActionResults,
                        for: [.prepareImageRootfs]
                    ),
                    initfsPrep: duration(
                        upActionResults,
                        for: [.createProjectRuntime]
                    ),
                    volumeCreateOrReuse: duration(
                        upActionResults,
                        for: [.createNamedVolume]
                    ),
                    podCreateOrReuse: duration(
                        upActionResults,
                        for: [.createProjectRuntime]
                    ),
                    containerStart: duration(
                        upActionResults,
                        for: [.startContainer, .runJob]
                    ),
                    healthcheck: duration(
                        upActionResults,
                        for: [.waitForReadiness]
                    )
                ),
                guest: guest,
                hostPhysicalMemoryStatus: .blocked,
                actionCount: actionCount,
                cleanupStateDirectoryExistsAfterCleanup: FileManager.default.fileExists(atPath: projectDirectory.path),
                healthcheckAttempts: up.actionResults.filter { $0.kind == .waitForReadiness }.count,
                dataFootprintBytes: dataFootprintBeforeCleanup,
                cleanupResult: cleanupResult,
                failure: nil
            )
        } catch {
            let cleanupStarted = Date()
            if let cleanup = try? await backend.execute(
                command: .down,
                plan: plan,
                options: RuntimeOptions(includeVolumes: true),
                approval: approval
            ) {
                actionCount += cleanup.actionResults.count
            }
            cleanupDuration = elapsedSeconds(since: cleanupStarted)
            return Phase6BenchmarkIterationRecord(
                timestamp: iso8601Now(),
                project: projectResource,
                runLabel: options.runLabel,
                iteration: iteration,
                environment: environment,
                status: .failed,
                durationsSeconds: Phase6BenchmarkDurations(
                    up: upDuration,
                    status: statusDuration,
                    logs: logsDuration,
                    cleanup: cleanupDuration
                ),
                guest: guest,
                hostPhysicalMemoryStatus: .blocked,
                actionCount: actionCount,
                cleanupStateDirectoryExistsAfterCleanup: FileManager.default.fileExists(atPath: projectDirectory.path),
                failure: "\(error)"
            )
        }
    }

    private static func cleanupAfterIteration(
        _ policy: Phase6IterationCleanupPolicy,
        backend: LinuxPodBackend,
        plan: RuntimePlan,
        approval: RuntimeApproval
    ) async throws -> ExecutionResult {
        switch policy {
        case .fullProjectAndVolumes:
            return try await backend.execute(
                command: .down,
                plan: plan,
                options: RuntimeOptions(includeVolumes: true),
                approval: approval
            )
        case .preserveVolumes:
            return try await backend.execute(
                command: .down,
                plan: plan,
                options: RuntimeOptions(includeVolumes: false),
                approval: approval
            )
        case .preserveProjectRuntime:
            return ExecutionResult(
                backend: .linuxpod,
                command: .down,
                status: "preserved-project-runtime-for-warm-reuse"
            )
        }
    }

    private static func cleanupResultValue(
        _ policy: Phase6IterationCleanupPolicy,
        projectDirectory: URL
    ) -> String {
        switch policy {
        case .fullProjectAndVolumes:
            return FileManager.default.fileExists(atPath: projectDirectory.path) ? "leftovers" : "clean"
        case .preserveVolumes:
            return "preserved-volume-for-warm-reuse"
        case .preserveProjectRuntime:
            return "preserved-project-runtime-for-warm-reuse"
        }
    }

    private static func duration(
        _ results: [RuntimeActionResult],
        for kinds: Set<PlannedActionKind>
    ) -> Double? {
        let values = results.compactMap { result -> Double? in
            guard kinds.contains(result.kind),
                  let value = result.metadata["durationSeconds"],
                  let seconds = Double(value) else {
                return nil
            }
            return seconds
        }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
    }

    private static func dataFootprintBytes(_ url: URL) -> UInt64? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }
        var total: UInt64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            let addition = UInt64(fileSize)
            let sum = total.addingReportingOverflow(addition)
            total = sum.overflow ? UInt64.max : sum.partialValue
        }
        return total
    }
}

private enum HarnessError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

private func appendJSONLine<T: Encodable>(_ record: T, path: String?) throws {
    guard let path else {
        throw HarnessError.usage("--evidence-jsonl is required")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(record) + Data("\n".utf8)
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: url.path) {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    } else {
        try data.write(to: url, options: .atomic)
    }
}

private func iso8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func elapsedSeconds(since start: Date) -> Double {
    Date().timeIntervalSince(start)
}

private struct SeedImageStoreCopyResult {
    let requested: Bool
    let copied: Bool
    let validated: Bool
    let path: String?
    let projectRuntimeDirectoryExistedBeforeSeed: Bool
    let imageCacheStatus: BenchmarkCacheStatus

    static func notRequested(projectRuntimeDirectoryExistedBeforeSeed: Bool) -> SeedImageStoreCopyResult {
        SeedImageStoreCopyResult(
            requested: false,
            copied: false,
            validated: false,
            path: nil,
            projectRuntimeDirectoryExistedBeforeSeed: projectRuntimeDirectoryExistedBeforeSeed,
            imageCacheStatus: .miss
        )
    }
}

private func benchmarkEnvironment(
    options: Phase6BenchmarkOptions,
    plan: RuntimePlan,
    backend: LinuxPodBackend,
    projectDirectory: URL,
    seedResult: SeedImageStoreCopyResult
) -> BenchmarkRunMetadata {
    let imageStatuses = plan.services.map { service in
        cacheStatus(path: backend.stateStore.rootfsCachePath(image: service.image).path)
    }
    let rootfsStatus = combinedCacheStatus(imageStatuses)
    let volumeStatuses = plan.volumes.map { volume in
        FileManager.default.fileExists(atPath: backend.stateStore.volumePath(project: plan.project, volume: volume).path)
    }
    let runtimeDirectory = backend.stateStore.runtimeDirectory(for: plan.project)
    let projectRuntimeDirectoryExistedBeforeRun = FileManager.default.fileExists(atPath: runtimeDirectory.path)
    return BenchmarkRunMetadata(
        runtime: .linuxpod,
        targetName: options.effectiveLifecycleMode.targetName,
        runtimeVersion: "apple/containerization LinuxPod",
        containerizationVersion: ContainerizationLinuxPodRuntimeExecutor.containerizationVersion,
        appleContainerCLIVersion: nil,
        macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        hostArchitecture: hostArchitecture(),
        lifecycle: options.lifecycle,
        lifecycleMode: options.effectiveLifecycleMode,
        seedImageStoreRequested: seedResult.requested,
        seedImageStoreCopied: seedResult.copied,
        seedImageStoreValidated: seedResult.validated,
        seedImageStorePath: seedResult.path,
        projectRuntimeExistedBeforeRun: projectRuntimeDirectoryExistedBeforeRun,
        projectRuntimeDirectoryExistedBeforeSeed: seedResult.projectRuntimeDirectoryExistedBeforeSeed,
        projectRuntimeDirectoryExistedBeforeRun: projectRuntimeDirectoryExistedBeforeRun,
        podExistedBeforeRun: FileManager.default.fileExists(
            atPath: runtimeDirectory.appendingPathComponent("boot.log").path
        ),
        imageCacheStatus: seedResult.imageCacheStatus,
        rootfsCacheStatus: rootfsStatus,
        initfsCacheStatus: cacheStatus(path: backend.stateStore.initfsCachePath().path),
        volumeExistedBeforeRun: volumeStatuses.contains(true),
        hostPortPublished: nil,
        hostPortTTFBSeconds: nil,
        hostPortProbeStatus: "notMeasured",
        hostPortPublishingNotImplemented: true,
        loadWindowSeconds: nil,
        loadWindowStatus: "notMeasured",
        completedRequests: nil,
        requestFailureCount: nil
    )
}

private func cacheStatus(path: String) -> BenchmarkCacheStatus {
    FileManager.default.fileExists(atPath: path) ? .hit : .miss
}

private func combinedCacheStatus(_ statuses: [BenchmarkCacheStatus]) -> BenchmarkCacheStatus {
    guard !statuses.isEmpty else {
        return .unknown
    }
    return statuses.allSatisfy { $0 == .hit } ? .hit : .miss
}

private func hostArchitecture() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}
