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

        if options.stage10BRuntimeComparison {
            try await runStage10BRuntimeComparison(options, approval: approval)
            return
        }

        let executor = ContainerizationLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        var records: [Phase6BenchmarkIterationRecord] = []

        if options.stage9BHotplugProbe {
            try await runStage9BHotplugProbe(options, executor: executor)
            return
        }
        if options.stage9DHotplugProviderProbe {
            try await runStage9DHotplugProviderProbe(options, executor: executor)
            return
        }
        if options.stage10ARootfsMaterializationProbe {
            try await runStage10ARootfsMaterializationProbe(options, executor: executor)
            return
        }

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

        if options.warmStatePrimerPolicy != .none {
            let projectName = options.projectName(forIteration: 1)
            let plan = try makePlan(options: options, projectName: projectName)
            FileHandle.standardError.write(
                Data("phase6-benchmark: priming \(options.effectiveLifecycleMode.rawValue) warm state\n".utf8)
            )
            try await primeWarmState(
                options.warmStatePrimerPolicy,
                plan: plan,
                backend: backend,
                executor: executor,
                approval: approval
            )
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

    private static func runStage9BHotplugProbe(
        _ options: Phase6BenchmarkOptions,
        executor: ContainerizationLinuxPodRuntimeExecutor
    ) async throws {
        let defaultImage = "docker.io/library/python:3.12-alpine"
        let image = options.dockerHubMirror.map { mirror in
            DockerHubOfficialImageMirror.rewrite(image: defaultImage, mirror: mirror)
        } ?? defaultImage
        FileHandle.standardError.write(
            Data("stage9b-hotplug-probe: using image \(image)\n".utf8)
        )
        let records = await executor.runStage9BHotplugCapabilityProbe(
            projectPrefix: options.projectPrefix,
            runLabel: options.runLabel,
            image: image
        )
        for record in records {
            try appendJSONLine(record, path: options.evidencePath)
        }
        let diagnostics = Stage9BHotplugProbeEvidenceValidator().validate(records: records)
        let blocking = diagnostics.filter { $0.severity == DiagnosticSeverity.blocking }
        guard blocking.isEmpty else {
            throw HarnessError.usage(
                "Stage 9B hotplug probe evidence failed validation: \(blocking.map { $0.code }.joined(separator: ", "))"
            )
        }
        print("stage9b-hotplug-probe: completed \(records.count) record(s); evidence at \(options.evidencePath ?? "")")
    }

    private static func runStage9DHotplugProviderProbe(
        _ options: Phase6BenchmarkOptions,
        executor: ContainerizationLinuxPodRuntimeExecutor
    ) async throws {
        let defaultImage = "docker.io/library/python:3.12-alpine"
        let image = options.dockerHubMirror.map { mirror in
            DockerHubOfficialImageMirror.rewrite(image: defaultImage, mirror: mirror)
        } ?? defaultImage
        FileHandle.standardError.write(
            Data("stage9d-hotplug-provider-probe: using image \(image)\n".utf8)
        )
        let record = await executor.runStage9DHotplugProviderProbe(
            projectPrefix: options.projectPrefix,
            runLabel: options.runLabel,
            image: image
        )
        try appendJSONLine(record, path: options.evidencePath)
        let diagnostics = Stage9DHotplugProviderProbeEvidenceValidator().validate(records: [record])
        let blocking = diagnostics.filter { $0.severity == DiagnosticSeverity.blocking }
        guard blocking.isEmpty else {
            throw HarnessError.usage(
                "Stage 9D hotplug provider probe evidence failed validation: \(blocking.map { $0.code }.joined(separator: ", "))"
            )
        }
        print("stage9d-hotplug-provider-probe: completed 1 record; evidence at \(options.evidencePath ?? "")")
    }

    private static func runStage10ARootfsMaterializationProbe(
        _ options: Phase6BenchmarkOptions,
        executor: ContainerizationLinuxPodRuntimeExecutor
    ) async throws {
        let defaultImage = "docker.io/library/postgres:16-alpine"
        let image = options.dockerHubMirror.map { mirror in
            DockerHubOfficialImageMirror.rewrite(image: defaultImage, mirror: mirror)
        } ?? defaultImage
        let strategies: [RootfsMaterializationStrategy] = options.rootfsMaterializationStrategy == .auto
            ? [.fullCopy, .auto]
            : [options.rootfsMaterializationStrategy]
        FileHandle.standardError.write(
            Data("stage10a-rootfs-materialization-probe: using image \(image); strategies \(strategies.map(\.rawValue).joined(separator: ","))\n".utf8)
        )
        var records: [RootfsMaterializationProbeRecord] = []
        for strategy in strategies {
            let record = await executor.runStage10ARootfsMaterializationProbe(
                projectPrefix: options.projectPrefix,
                runLabel: options.runLabel,
                image: image,
                strategy: strategy
            )
            try appendJSONLine(record, path: options.evidencePath)
            records.append(record)
        }
        let diagnostics = Stage10ARootfsMaterializationProbeEvidenceValidator().validate(records: records)
        let blocking = diagnostics.filter { $0.severity == DiagnosticSeverity.blocking }
        guard blocking.isEmpty else {
            throw HarnessError.usage(
                "Stage 10A rootfs materialization evidence failed validation: \(blocking.map { $0.code }.joined(separator: ", "))"
            )
        }
        print("stage10a-rootfs-materialization-probe: completed \(records.count) record(s); evidence at \(options.evidencePath ?? "")")
    }

    private static func runStage10BRuntimeComparison(
        _ options: Phase6BenchmarkOptions,
        approval: RuntimeApproval
    ) async throws {
        let candidate = options.rootfsMaterializationStrategy.isCloneStrategy
            ? options.rootfsMaterializationStrategy
            : RootfsMaterializationStrategy.auto
        let strategies: [RootfsMaterializationStrategy] = [.fullCopy, candidate]
        var recordsByStrategy: [RootfsMaterializationStrategy: [Phase6BenchmarkIterationRecord]] = [:]
        var summariesByStrategy: [RootfsMaterializationStrategy: Phase6BenchmarkSummaryRecord] = [:]

        for strategy in strategies {
            var strategyOptions = options
            strategyOptions.stage10BRuntimeComparison = true
            strategyOptions.rootfsMaterializationStrategy = strategy
            strategyOptions.runLabel = "\(options.runLabel)-\(stage10BRunLabelSuffix(strategy))"

            let executor = ContainerizationLinuxPodRuntimeExecutor()
            let backend = LinuxPodBackend(runtimeExecutor: executor)
            var strategyRecords: [Phase6BenchmarkIterationRecord] = []

            for iteration in 1...strategyOptions.iterations {
                let projectName = strategyOptions.projectName(forIteration: iteration)
                let plan = try makePlan(options: strategyOptions, projectName: projectName)
                let projectResource = backend.stateStore.projectName(for: plan.project)
                let projectDirectory = backend.stateStore.projectDirectory(for: plan.project)
                let cleanupPolicy = strategyOptions.cleanupPolicy(isFinalIteration: iteration == strategyOptions.iterations)

                FileHandle.standardError.write(
                    Data("stage10b-runtime-comparison: \(strategy.rawValue) iteration \(iteration)/\(strategyOptions.iterations) up\n".utf8)
                )
                let record = await runIteration(
                    iteration: iteration,
                    options: strategyOptions,
                    plan: plan,
                    projectResource: projectResource,
                    projectDirectory: projectDirectory,
                    cleanupPolicy: cleanupPolicy,
                    backend: backend,
                    executor: executor,
                    approval: approval
                )
                try appendJSONLine(record, path: options.evidencePath)
                strategyRecords.append(record)
            }

            let summary = Phase6BenchmarkSummaryRecord(
                timestamp: iso8601Now(),
                projectPrefix: strategyOptions.projectPrefix,
                runLabel: strategyOptions.runLabel,
                requestedIterations: strategyOptions.iterations,
                records: strategyRecords
            )
            try appendJSONLine(summary, path: options.evidencePath)
            recordsByStrategy[strategy] = strategyRecords
            summariesByStrategy[strategy] = summary
        }

        guard let fullCopyRecords = recordsByStrategy[.fullCopy],
              let fullCopySummary = summariesByStrategy[.fullCopy],
              let candidateRecords = recordsByStrategy[candidate],
              let candidateSummary = summariesByStrategy[candidate] else {
            throw HarnessError.usage("Stage 10B comparison did not produce both fullCopy and clone-candidate records.")
        }
        let comparison = Stage10BRuntimeComparisonRecord(
            timestamp: iso8601Now(),
            fullCopy: stage10BStrategySummary(
                requestedStrategy: .fullCopy,
                records: fullCopyRecords,
                summary: fullCopySummary
            ),
            cloneCandidate: stage10BStrategySummary(
                requestedStrategy: candidate,
                records: candidateRecords,
                summary: candidateSummary
            )
        )
        try appendJSONLine(comparison, path: options.evidencePath)
        let diagnostics = Stage10BRuntimeComparisonEvidenceValidator()
            .validate(records: fullCopyRecords + candidateRecords, comparison: comparison)
        let blocking = diagnostics.filter { $0.severity == DiagnosticSeverity.blocking }
        guard blocking.isEmpty else {
            throw HarnessError.usage(
                "Stage 10B runtime comparison evidence failed validation: \(blocking.map { $0.code }.joined(separator: ", "))"
            )
        }
        print("stage10b-runtime-comparison: completed \(strategies.count) strategy run(s); evidence at \(options.evidencePath ?? "")")
    }

    private static func stage10BRunLabelSuffix(_ strategy: RootfsMaterializationStrategy) -> String {
        switch strategy {
        case .fullCopy:
            return "fullcopy"
        case .auto:
            return "auto"
        case .clonefile:
            return "clonefile"
        case .copyfileClone:
            return "copyfileclone"
        case .apfsClone:
            return "apfsclone"
        case .fileManagerCopy:
            return "filemanagercopy"
        case .unsupported,
             .unpack,
             .copy,
             .clone,
             .reuse,
             .unknown:
            return strategy.rawValue.lowercased()
        }
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

    private static func primeWarmState(
        _ policy: Phase6WarmStatePrimerPolicy,
        plan: RuntimePlan,
        backend: LinuxPodBackend,
        executor: ContainerizationLinuxPodRuntimeExecutor,
        approval: RuntimeApproval
    ) async throws {
        switch policy {
        case .none:
            return
        case .preservedVolume:
            _ = try await backend.execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(),
                approval: approval
            )
            _ = try await cleanupAfterIteration(
                .preserveVolumes,
                backend: backend,
                plan: plan,
                approval: approval
            )
        case .emptyPersistentPod:
            let projectRuntimeOnlyPlan = RuntimePlan(project: plan.project, services: [])
            let projectResource = backend.stateStore.projectName(for: plan.project)
            _ = try await backend.execute(
                command: .up,
                plan: projectRuntimeOnlyPlan,
                options: RuntimeOptions(),
                approval: approval
            )
            try await executor.ensurePodCreated(project: projectResource)
        case .allWarmProjectRuntime:
            _ = try await backend.execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(),
                approval: approval
            )
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
        var podExistedBeforeRun = false
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
            seedResult: seedResult,
            podExistedBeforeRun: false
        )

        do {
            podExistedBeforeRun = await executor.hasCreatedPod(project: projectResource)
            seedResult = try await seedImageStoreIfRequested(options: options, plan: plan, backend: backend)
            environment = benchmarkEnvironment(
                options: options,
                plan: plan,
                backend: backend,
                projectDirectory: projectDirectory,
                seedResult: seedResult,
                podExistedBeforeRun: podExistedBeforeRun
            )
            let upStarted = Date()
            let up = try await backend.execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(
                    rootfsMaterializationStrategyOverride: options.stage10BRuntimeComparison
                        ? options.rootfsMaterializationStrategy
                        : nil
                ),
                approval: approval
            )
            upDuration = elapsedSeconds(since: upStarted)
            upActionResults = up.actionResults
            actionCount += up.actionResults.count
            let jobResults = up.actionResults.filter { $0.kind == .runJob }

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
            let hotplugIntrospection = await executor.hotplugIntrospectionMetadata(project: projectResource)
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
                jobAttempts: jobResults.count,
                successfulJobCount: jobResults.filter { $0.metadata["exitCode"] == "0" }.count,
                jobExitCodes: jobResults.map { result in
                    "\(result.resourceName ?? "job"):\(result.metadata["exitCode"] ?? "unknown")"
                },
                dataFootprintBytes: dataFootprintBeforeCleanup,
                cleanupResult: cleanupResult,
                failure: nil,
                rootfsPreparation: rootfsPreparationBreakdowns(
                    upActionResults,
                    failedAddContainerMetadata: hotplugIntrospection
                ),
                hotplugDiagnostics: hotplugDiagnosticsIfNeeded(
                    options: options,
                    plan: plan,
                    backend: backend,
                    podExistedBeforeRun: podExistedBeforeRun,
                    upActionResults: upActionResults,
                    failure: nil,
                    hotplugIntrospection: hotplugIntrospection
                ),
                warmServiceRecreate: warmServiceRecreateMetadataIfNeeded(
                    options: options,
                    plan: plan,
                    backend: backend,
                    podExistedBeforeRun: podExistedBeforeRun
                ),
                blockIOAttribution: "wholeRunOnly",
                rootfsBlockIOAttribution: "notMeasured"
            )
        } catch {
            let hotplugIntrospection = await executor.hotplugIntrospectionMetadata(project: projectResource)
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
                failure: "\(error)",
                rootfsPreparation: rootfsPreparationBreakdowns(
                    upActionResults,
                    failedAddContainerMetadata: hotplugIntrospection
                ),
                hotplugDiagnostics: hotplugDiagnosticsIfNeeded(
                    options: options,
                    plan: plan,
                    backend: backend,
                    podExistedBeforeRun: podExistedBeforeRun,
                    upActionResults: upActionResults,
                    failure: error,
                    hotplugIntrospection: hotplugIntrospection
                ),
                warmServiceRecreate: warmServiceRecreateMetadataIfNeeded(
                    options: options,
                    plan: plan,
                    backend: backend,
                    podExistedBeforeRun: podExistedBeforeRun
                ),
                blockIOAttribution: "wholeRunOnly",
                rootfsBlockIOAttribution: "notMeasured"
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

    private static func rootfsPreparationBreakdowns(
        _ results: [RuntimeActionResult],
        failedAddContainerMetadata: [String: String] = [:]
    ) -> [RootfsPreparationBreakdown]? {
        let rootfsKinds: Set<PlannedActionKind> = [.prepareImageRootfs, .addContainer]
        var sourceResults = results
        let hasAddContainerRootfs = sourceResults.contains { result in
            result.kind == .addContainer
                && result.metadata.keys.contains(where: { $0.contains("rootfs") || $0.contains("Rootfs") })
        }
        if !hasAddContainerRootfs,
           failedAddContainerMetadata.keys.contains(where: { $0.contains("rootfs") || $0.contains("Rootfs") }) {
            sourceResults.append(
                RuntimeActionResult(
                    order: -1,
                    kind: .addContainer,
                    resourceName: failedAddContainerMetadata["failedAddContainerResourceName"],
                    status: "failed",
                    metadata: failedAddContainerMetadata
                )
            )
        }
        let breakdowns = sourceResults.compactMap { result -> RootfsPreparationBreakdown? in
            guard rootfsKinds.contains(result.kind),
                  result.metadata.keys.contains(where: { $0.contains("rootfs") || $0.contains("Rootfs") }) else {
                return nil
            }
            return RootfsPreparationBreakdown(
                actionKind: result.kind.rawValue,
                resourceName: result.resourceName,
                image: result.metadata["image"] ?? (result.kind == .prepareImageRootfs ? result.resourceName : nil),
                service: result.metadata["service"],
                imageReferenceResolveDuration: doubleMetadata(result, "imageReferenceResolveDuration"),
                imageStoreLookupDuration: doubleMetadata(result, "imageStoreLookupDuration"),
                platformValidationDuration: doubleMetadata(result, "platformValidationDuration"),
                imagePullDuration: doubleMetadata(result, "imagePullDuration"),
                baseRootfsCacheLookupDuration: doubleMetadata(result, "baseRootfsCacheLookupDuration"),
                baseRootfsCacheHit: boolMetadata(result, "baseRootfsCacheHit"),
                baseRootfsCreateOrUnpackDuration: doubleMetadata(result, "baseRootfsCreateOrUnpackDuration"),
                containerRootfsMaterializeDuration: doubleMetadata(result, "containerRootfsMaterializeDuration"),
                containerRootfsCopyDuration: doubleMetadata(result, "containerRootfsCopyDuration"),
                containerRootfsCloneDuration: doubleMetadata(result, "containerRootfsCloneDuration"),
                containerRootfsMountPrepareDuration: doubleMetadata(result, "containerRootfsMountPrepareDuration"),
                rootfsBytesCopied: uint64Metadata(result, "rootfsBytesCopied"),
                rootfsSourcePath: redactRepositoryPath(result.metadata["rootfsSourcePath"]),
                rootfsDestinationPath: redactRepositoryPath(result.metadata["rootfsDestinationPath"]),
                rootfsMountType: result.metadata["rootfsMountType"],
                rootfsMountFormat: result.metadata["rootfsMountFormat"],
                rootfsMountIsBlock: boolMetadata(result, "rootfsMountIsBlock"),
                rootfsMaterializationStrategy: RootfsMaterializationStrategy(
                    rawValue: result.metadata["rootfsMaterializationStrategy"] ?? ""
                ) ?? .unknown,
                rootfsWorkAvoided: EvidenceTruthValue(
                    rawValue: result.metadata["rootfsWorkAvoided"] ?? ""
                ) ?? .unknown,
                rootfsCacheClaim: RootfsCacheClaim(
                    rawValue: result.metadata["rootfsCacheClaim"] ?? ""
                ) ?? .unknown
            )
        }
        return breakdowns.isEmpty ? nil : breakdowns
    }

    private static func stage10BStrategySummary(
        requestedStrategy: RootfsMaterializationStrategy,
        records: [Phase6BenchmarkIterationRecord],
        summary: Phase6BenchmarkSummaryRecord
    ) -> Stage10BStrategyRuntimeSummary {
        let measured = records.filter { $0.status == .measured }
        let breakdowns = measured.flatMap { $0.rootfsPreparation ?? [] }
        let observedStrategies = Array(Set(breakdowns.map(\.rootfsMaterializationStrategy))).sorted {
            $0.rawValue < $1.rawValue
        }
        return Stage10BStrategyRuntimeSummary(
            requestedStrategy: requestedStrategy,
            observedStrategies: observedStrategies,
            measured: summary.measuredIterations > 0 && summary.failureCount == 0,
            upDurationSeconds: summary.upDurationP50Seconds,
            readinessDurationSeconds: summary.healthcheckDurationP50Seconds,
            rootfsPrepDurationSeconds: summary.rootfsPrepDurationP50Seconds,
            projectRootfsMaterializeDurationSeconds: p50Double(
                measured.map { stage10BMaterializationDuration($0, actionKind: PlannedActionKind.prepareImageRootfs.rawValue) }
            ),
            containerRootfsMaterializeDurationSeconds: p50Double(
                measured.map { stage10BMaterializationDuration($0, actionKind: PlannedActionKind.addContainer.rawValue) }
            ),
            blockReadBytes: summary.blockReadP50Bytes,
            blockWriteBytes: summary.blockWriteP50Bytes,
            healthcheckAttempts: summary.healthcheckAttemptsP50,
            jobAttempts: summary.jobAttemptsP50,
            successfulJobCount: summary.successfulJobCountP50,
            volumeExistedBeforeRun: summary.environment?.volumeExistedBeforeRun,
            volumeCreateOrReuseDurationSeconds: summary.volumeCreateOrReuseDurationP50Seconds,
            dataFootprintBytes: summary.dataFootprintP50Bytes,
            cleanupResult: summary.cleanupResult ?? records.last?.cleanupResult ?? "unknown",
            cleanupStateDirectoryExistsAfterCleanup: records.last?.cleanupStateDirectoryExistsAfterCleanup ?? true,
            hostPortProbeStatus: summary.hostPortProbeStatus,
            loadWindowStatus: summary.loadWindowStatus,
            rootfsWorkAvoided: stage10BRootfsWorkAvoided(breakdowns),
            failure: records.compactMap(\.failure).first
        )
    }

    private static func stage10BMaterializationDuration(
        _ record: Phase6BenchmarkIterationRecord,
        actionKind: String
    ) -> Double? {
        let values = (record.rootfsPreparation ?? [])
            .filter { $0.actionKind == actionKind }
            .compactMap(\.containerRootfsMaterializeDuration)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +)
    }

    private static func stage10BRootfsWorkAvoided(_ breakdowns: [RootfsPreparationBreakdown]) -> EvidenceTruthValue {
        guard !breakdowns.isEmpty else {
            return .unknown
        }
        if breakdowns.allSatisfy({ $0.rootfsWorkAvoided == .true }) {
            return .true
        }
        if breakdowns.allSatisfy({ $0.rootfsWorkAvoided == .false }) {
            return .false
        }
        return .unknown
    }

    private static func p50Double(_ values: [Double?]) -> Double? {
        let sorted = values.compactMap { $0 }.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        return sorted[sorted.count / 2]
    }

    private static func hotplugDiagnosticsIfNeeded(
        options: Phase6BenchmarkOptions,
        plan: RuntimePlan,
        backend: LinuxPodBackend,
        podExistedBeforeRun: Bool,
        upActionResults: [RuntimeActionResult],
        failure: Error?,
        hotplugIntrospection: [String: String]
    ) -> HotplugLifecycleDiagnostics? {
        switch options.effectiveLifecycleMode {
        case .persistentPodHotplug, .allWarmProjectRuntime:
            break
        case .coldRuntime,
             .imageStoreSeededFreshRuntime,
             .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime,
             .warmPreservedVolume:
            return nil
        }

        let runtimeDirectory = backend.stateStore.runtimeDirectory(for: plan.project)
        let podMarker = backend.stateStore.podMarkerPath(project: plan.project)
        let markerExists = FileManager.default.fileExists(atPath: podMarker.path)
        let failureMessage = failure.map { "\($0)" }
        let addContainerResults = upActionResults.filter { $0.kind == .addContainer }
        let unsupportedHotplugFailure = failureMessage?.contains("hotplug not supported") == true
        let inferredAddContainerFailure = failureMessage?.contains("pod must be initialized") == true
            || failureMessage?.contains("add container") == true
            || failureMessage?.contains("addContainer") == true
            || unsupportedHotplugFailure
        let addContainerAttempted = !addContainerResults.isEmpty || inferredAddContainerFailure
        let podReuseClaim: PodReuseClaim
        if podExistedBeforeRun {
            podReuseClaim = .liveObject
        } else if markerExists {
            podReuseClaim = .markerOnly
        } else {
            podReuseClaim = .unknown
        }
        let addContainerPhase: AddContainerPhase
        if addContainerAttempted {
            addContainerPhase = podExistedBeforeRun ? .afterPodCreate : .beforePodCreate
        } else {
            addContainerPhase = podExistedBeforeRun ? .afterPodCreate : .unknown
        }
        let containerReuseOnly = addContainerResults.contains { $0.metadata["containerReuse"] == "hit" }
        let hotplugAttempted = podExistedBeforeRun && addContainerAttempted && !containerReuseOnly
        let hotplugSucceeded = failure == nil && hotplugAttempted && !addContainerResults.isEmpty
        let mutationBeforeFailure: EvidenceTruthValue
        if failure == nil {
            mutationBeforeFailure = .false
        } else if podExistedBeforeRun {
            mutationBeforeFailure = .true
        } else {
            mutationBeforeFailure = .unknown
        }

        return HotplugLifecycleDiagnostics(
            podMarkerExists: markerExists,
            runtimeDirectoryExists: FileManager.default.fileExists(atPath: runtimeDirectory.path),
            podObjectInitialized: podExistedBeforeRun,
            podObjectPhase: podExistedBeforeRun ? "created" : "uninitialized",
            podCreatedStateKnown: true,
            podActuallyRunning: podExistedBeforeRun,
            podReconnectAttempted: false,
            podReconnectSucceeded: false,
            podReuseClaim: podReuseClaim,
            addContainerAttempted: addContainerAttempted,
            addContainerPhase: addContainerPhase,
            hotplugAttempted: hotplugAttempted,
            hotplugSucceeded: hotplugSucceeded,
            hotplugUnsupported: failureMessage?.contains("pod must be initialized") == true || unsupportedHotplugFailure ? true : nil,
            duplicateContainerDetected: false,
            vmConfigExtensionCount: intMetadata(hotplugIntrospection, "vmConfigExtensionCount"),
            vmConfigExtensionTypes: stringListMetadata(hotplugIntrospection, "vmConfigExtensionTypes"),
            hotplugProviderInstalled: boolMetadata(hotplugIntrospection, "hotplugProviderInstalled"),
            hotplugProviderType: nonEmptyMetadata(hotplugIntrospection, "hotplugProviderType"),
            hotplugProviderStatus: nonEmptyMetadata(hotplugIntrospection, "hotplugProviderStatus"),
            failurePhase: failure == nil ? nil : (inferredAddContainerFailure ? "addContainer" : "unknown"),
            failureErrorType: failure.map { errorType($0) },
            failureErrorMessage: failureMessage,
            mutationBeforeFailure: mutationBeforeFailure
        )
    }

    private static func warmServiceRecreateMetadataIfNeeded(
        options: Phase6BenchmarkOptions,
        plan: RuntimePlan,
        backend: LinuxPodBackend,
        podExistedBeforeRun: Bool
    ) -> WarmServiceRecreateMetadata? {
        guard options.effectiveLifecycleMode == .allWarmProjectRuntime else {
            return nil
        }
        let serviceName = plan.services.first { $0.name == "api" }?.name
            ?? plan.services.first(where: { $0.kind == .service })?.name
        let dbVolumePreserved = plan.volumes.contains { volume in
            FileManager.default.fileExists(
                atPath: backend.stateStore.volumeImagePath(project: plan.project, volume: volume).path
            )
        }
        return WarmServiceRecreateMetadata(
            forcedServiceRecreateRequested: false,
            forcedServiceName: serviceName,
            serviceChanged: false,
            previousServiceStateKnown: podExistedBeforeRun,
            recreateStrategy: .noOp,
            dbVolumePreserved: dbVolumePreserved,
            podPreserved: podExistedBeforeRun,
            serviceRecreateDuration: nil,
            postRecreateReadinessDuration: nil,
            hostPortStatus: "notMeasured",
            loadWindowStatus: "notMeasured",
            noOpWarmReconcile: true,
            notProductViabilityEvidence: true
        )
    }

    private static func doubleMetadata(_ result: RuntimeActionResult, _ key: String) -> Double? {
        result.metadata[key].flatMap(Double.init)
    }

    private static func uint64Metadata(_ result: RuntimeActionResult, _ key: String) -> UInt64? {
        result.metadata[key].flatMap(UInt64.init)
    }

    private static func boolMetadata(_ result: RuntimeActionResult, _ key: String) -> Bool? {
        guard let value = result.metadata[key] else {
            return nil
        }
        return boolMetadataValue(value)
    }

    private static func intMetadata(_ metadata: [String: String], _ key: String) -> Int? {
        metadata[key].flatMap(Int.init)
    }

    private static func boolMetadata(_ metadata: [String: String], _ key: String) -> Bool? {
        guard let value = metadata[key] else {
            return nil
        }
        return boolMetadataValue(value)
    }

    private static func nonEmptyMetadata(_ metadata: [String: String], _ key: String) -> String? {
        guard let value = metadata[key], !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func stringListMetadata(_ metadata: [String: String], _ key: String) -> [String]? {
        guard let value = metadata[key], !value.isEmpty else {
            return []
        }
        return value
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func boolMetadataValue(_ value: String) -> Bool? {
        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func errorType(_ error: Error) -> String {
        let description = "\(error)"
        if description.contains("invalidState") {
            return "invalidState"
        }
        if description.contains("unsupported") {
            return "unsupported"
        }
        return String(describing: type(of: error))
    }

    private static func redactRepositoryPath(_ path: String?) -> String? {
        guard let path else {
            return nil
        }
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL
            .path
        return path.replacingOccurrences(of: repositoryRoot, with: "<repo>")
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
    seedResult: SeedImageStoreCopyResult,
    podExistedBeforeRun: Bool
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
        podExistedBeforeRun: podExistedBeforeRun,
        podReuseVerificationStatus: podExistedBeforeRun ? "liveExecutorState" : "notApplicable",
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
