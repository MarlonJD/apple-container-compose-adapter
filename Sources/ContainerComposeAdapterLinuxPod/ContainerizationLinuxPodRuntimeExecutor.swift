// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import Containerization
import ContainerizationEXT4
import ContainerizationExtras
import Darwin
import Foundation
import Security
import SystemPackage
@preconcurrency import Virtualization

public actor ContainerizationLinuxPodRuntimeExecutor: LinuxPodRuntimeExecuting {
    public static let containerizationVersion = "0.33.4"
    public static let containerizationRevision = "9275f365dd555c8f072e7d250d809f5eb7bdd746"
    public static let defaultInitImageReference = "ghcr.io/apple/containerization/vminit:0.33.4"

    private let initImageReference: String
    private let podCPUs: Int
    private let podMemoryBytes: UInt64
    private let defaultRootfsSizeBytes: UInt64
    private let namedVolumeSizeBytes: UInt64
    private let stateStore = LinuxPodStateStore()
    private var states: [String: ProjectRuntime] = [:]

    public init(
        initImageReference: String = ContainerizationLinuxPodRuntimeExecutor.defaultInitImageReference,
        podCPUs: Int = 4,
        podMemoryBytes: UInt64 = 1024 * 1024 * 1024,
        defaultRootfsSizeBytes: UInt64 = 2 * 1024 * 1024 * 1024,
        namedVolumeSizeBytes: UInt64 = 1024 * 1024 * 1024
    ) {
        self.initImageReference = initImageReference
        self.podCPUs = podCPUs
        self.podMemoryBytes = podMemoryBytes
        self.defaultRootfsSizeBytes = defaultRootfsSizeBytes
        self.namedVolumeSizeBytes = namedVolumeSizeBytes
    }

    public static func currentProcessHasVirtualizationEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.virtualization" as CFString,
            nil
        )
        guard let entitlement,
              CFGetTypeID(entitlement) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((entitlement as! CFBoolean))
    }

    public func execute(_ event: LinuxPodRuntimeEvent) async throws -> RuntimeActionResult {
        var metadata: [String: String] = [:]
        switch event.kind {
        case .createProjectRuntime:
            try await createProjectRuntime(event)
        case .prepareImageRootfs:
            metadata = try await prepareImageRootfs(event)
        case .createNamedVolume:
            try createNamedVolume(event)
        case .validateBindMount:
            try validateBindMount(event)
        case .addContainer:
            metadata = try await addContainer(event)
        case .startContainer:
            try await startContainer(event)
        case .waitForReadiness:
            try await waitForReadiness(event)
        case .runJob:
            metadata = try await runJob(event)
        case .collectLogs:
            try collectLogs(event)
        case .inspectStatus:
            try inspectStatus(event)
        case .stopProjectRuntime:
            try await stopProjectRuntime(event)
        case .deleteProjectRuntime:
            try deleteProjectRuntime(event)
        case .cleanupNamedVolume:
            try cleanupNamedVolume(event)
        case .reportDiagnostic, .renderPlan:
            throw unsupported(event)
        }
        return RuntimeActionResult(
            order: event.order,
            kind: event.kind,
            resourceName: event.resourceName,
            status: "executed",
            metadata: metadata
        )
    }

    // Measurement-harness surface: create the pod VM even when no service
    // container start has triggered it (idle-pod footprint scenario).
    public func ensurePodCreated(project: String) async throws {
        guard var state = states[project] else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod project \(project) has no initialized runtime state."
            )
        }
        if !state.podCreated {
            try await state.pod.create()
            state.podCreated = true
            states[project] = state
        }
    }

    public func hasCreatedPod(project: String) -> Bool {
        states[project]?.podCreated == true
    }

    public func hotplugIntrospectionMetadata(project: String) -> [String: String] {
        guard let state = states[project] else {
            return [
                "vmConfigExtensionCount": "0",
                "vmConfigExtensionTypes": "",
                "hotplugProviderStatus": "state-missing"
            ]
        }
        var metadata: [String: String] = [
            "vmConfigExtensionCount": "\(state.pod.config.extensions.count)",
            "vmConfigExtensionTypes": state.pod.config.extensions
                .map { String(describing: type(of: $0)) }
                .joined(separator: ",")
        ]
        if let snapshot = state.vmIntrospection.snapshot() {
            metadata["vmInstanceType"] = snapshot.vmInstanceType
            metadata["hotplugProviderInstalled"] = "\(snapshot.hotplugProviderInstalled)"
            metadata["hotplugProviderType"] = snapshot.hotplugProviderType ?? ""
            metadata["hotplugProviderStatus"] = snapshot.hotplugProviderInstalled ? "installed" : "missing"
        } else {
            metadata["hotplugProviderStatus"] = "vm-not-created"
        }
        if let lastAttempt = state.lastAddContainerAttemptMetadata {
            metadata.merge(lastAttempt) { current, _ in current }
            metadata["failedAddContainerResourceName"] = lastAttempt["containerID"]
        }
        return metadata
    }

    public func runStage9BHotplugCapabilityProbe(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) async -> [Stage9BHotplugProbeRecord] {
        var records: [Stage9BHotplugProbeRecord] = []
        records.append(await runStage9BPreCreateRegistrationControl(projectPrefix: projectPrefix, runLabel: runLabel, image: image))
        records.append(await runStage9BEmptyPodPostCreateAdd(projectPrefix: projectPrefix, runLabel: runLabel, image: image))
        records.append(await runStage9BNonEmptyPodPostCreateAdd(projectPrefix: projectPrefix, runLabel: runLabel, image: image))
        records.append(await runStage9BDuplicateContainerGuard(projectPrefix: projectPrefix, runLabel: runLabel, image: image))
        records.append(stage9BCleanupProof(projectPrefix: projectPrefix, runLabel: runLabel))
        return records
    }

    public func runStage9DHotplugProviderProbe(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) async -> Stage9DHotplugProviderProbeRecord {
        let context = stage9DContext(projectPrefix: projectPrefix, runLabel: runLabel, image: image)
        var builder = Stage9DRecordBuilder(context: context)

        do {
            try await createStage9DRuntime(context)
            builder.extensionInstalled = true
            builder.linuxPodConfigExtensionCount = stage9DConfigExtensionCount(project: context.projectResource)
            try await prepareStage9DRootfs(context, service: context.initialService)
            try await addStage9DContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.preCreateRegistrationSucceeded = true
            builder.podCreateCalled = true
            try await ensurePodCreated(project: context.projectResource)
            builder.podCreateSucceeded = true
            builder.probeCases.insert(.providerInstallOnly)
            builder.updateProviderEvidence(from: stage9DProbeSnapshot(project: context.projectResource))
            try await startStage9DContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.firstContainerStarted = true
            try await prepareStage9DRootfs(context, service: context.secondService)

            builder.postCreateAddContainerAttempted = true
            do {
                try await addStage9DContainer(context, service: context.secondService, containerID: context.secondContainerID)
                builder.postCreateAddContainerSucceeded = true
                try await startStage9DContainer(context, service: context.secondService, containerID: context.secondContainerID)
                builder.secondContainerStarted = true
                builder.realHotplugSucceeded = true
                builder.probeCases.insert(.providerReceivesHotplug)
                builder.probeCases.insert(.realSecondContainerHotplug)
            } catch {
                builder.recordFailure(error, phase: "addContainer")
                builder.providerInstalledButAttachUnsupported = true
                builder.hotplugUnsupported = stage9DHotplugUnsupported(error)
            }
            builder.updateProviderEvidence(from: stage9DProbeSnapshot(project: context.projectResource))
            builder.updateRootfsEvidence(from: stage9DProbeSnapshot(project: context.projectResource))
        } catch {
            builder.recordFailure(error, phase: builder.podCreateCalled ? "podCreate" : "createProjectRuntime")
        }

        await cleanupStage9DContext(context, builder: &builder)
        builder.updateProviderEvidence(from: stage9DProbeSnapshot(project: context.projectResource))
        builder.updateRootfsEvidence(from: stage9DProbeSnapshot(project: context.projectResource))
        return builder.record()
    }

    public func runStage10ARootfsMaterializationProbe(
        projectPrefix: String,
        runLabel: String,
        image: String,
        strategy requestedStrategy: RootfsMaterializationStrategy
    ) async -> RootfsMaterializationProbeRecord {
        let project = ProjectName("\(projectPrefix)-\(runLabel)-\(requestedStrategy.rawValue)-probe")
        let projectResource = stateStore.projectName(for: project)
        let projectDirectory = stateStore.projectDirectory(for: project)
        let runtimeDirectory = stateStore.runtimeDirectory(for: project)
        let imageStoreDirectory = runtimeDirectory.appendingPathComponent("image-store", isDirectory: true)
        let rootfsCacheURL = stateStore.rootfsCachePath(image: image)
        let projectRootfsURL = stateStore.rootfsPath(project: project, image: image)
        let containerRootfsURL = runtimeDirectory
            .appendingPathComponent("rootfs", isDirectory: true)
            .appendingPathComponent("containers", isDirectory: true)
            .appendingPathComponent("\(projectResource)-probe.ext4")
        let totalStarted = Date()
        var status: Stage10ARootfsMaterializationStatus = .measured
        var imageReferenceLookup: Double?
        var imageStoreLookup: Double?
        var baseRootfsCacheLookup: Double?
        var baseRootfsUnpack: Double?
        var projectMaterialize: RootfsMaterializationResult?
        var containerMaterialize: RootfsMaterializationResult?
        var mountPrepare: Double?
        var projectExists = false
        var containerExists = false
        var containerReadable = false
        var ext4LooksValid: Bool?
        var failureReason: String?

        do {
            try ensureAdapterOwnedRuntimeDirectory(runtimeDirectory)
            try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            let imageStore = try ImageStore(path: imageStoreDirectory)
            let imageStoreStarted = Date()
            let imageValue = try await imageStore.get(reference: image, pull: true)
            imageStoreLookup = elapsedSeconds(since: imageStoreStarted)

            let platformStarted = Date()
            _ = try await imageValue.manifest(for: SystemPlatform.linuxArm.ociPlatform())
            imageReferenceLookup = elapsedSeconds(since: platformStarted)

            try ensureAdapterOwnedCachePath(rootfsCacheURL)
            try FileManager.default.createDirectory(
                at: rootfsCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cacheLookupStarted = Date()
            let cacheHit = FileManager.default.fileExists(atPath: rootfsCacheURL.path)
            baseRootfsCacheLookup = elapsedSeconds(since: cacheLookupStarted)
            if !cacheHit {
                let unpackStarted = Date()
                let unpacker = EXT4Unpacker(blockSizeInBytes: defaultRootfsSizeBytes)
                _ = try await unpacker.unpack(
                    imageValue,
                    for: SystemPlatform.linuxArm.ociPlatform(),
                    at: rootfsCacheURL
                )
                baseRootfsUnpack = elapsedSeconds(since: unpackStarted)
            } else {
                baseRootfsUnpack = 0
            }

            let materializer = RootfsMaterializer()
            projectMaterialize = try await materializer.materialize(
                source: rootfsCacheURL,
                destination: projectRootfsURL,
                strategy: requestedStrategy,
                context: RootfsMaterializationContext(
                    adapterOwnedRoot: stateStore.root,
                    phase: .cachedBaseToProjectRootfs
                )
            )

            let mountPrepareStarted = Date()
            try FileManager.default.createDirectory(
                at: containerRootfsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            mountPrepare = elapsedSeconds(since: mountPrepareStarted)

            containerMaterialize = try await materializer.materialize(
                source: projectRootfsURL,
                destination: containerRootfsURL,
                strategy: requestedStrategy,
                context: RootfsMaterializationContext(
                    adapterOwnedRoot: stateStore.root,
                    phase: .projectRootfsToContainerRootfs
                )
            )
            projectExists = FileManager.default.fileExists(atPath: projectRootfsURL.path)
            containerExists = FileManager.default.fileExists(atPath: containerRootfsURL.path)
            containerReadable = FileManager.default.isReadableFile(atPath: containerRootfsURL.path)
            ext4LooksValid = ext4MagicLooksValid(containerRootfsURL)
        } catch {
            status = .failed
            failureReason = "\(error)"
        }

        let cleanupStarted = Date()
        if FileManager.default.fileExists(atPath: projectDirectory.path) {
            do {
                try FileManager.default.removeItem(at: projectDirectory)
            } catch {
                status = .failed
                failureReason = [failureReason, "cleanup failed: \(error)"].compactMap { $0 }.joined(separator: "; ")
            }
        }
        let cleanupDuration = elapsedSeconds(since: cleanupStarted)
        let leftovers = leftoverPathCount(at: projectDirectory)
        let cleanup = RootfsMaterializationCleanupEvidence(
            cleanupResult: leftovers == 0 ? "clean" : "leftovers",
            cleanupStateDirectoryExistsAfterCleanup: leftovers > 0,
            leftoverPathsCount: leftovers,
            zeroAdapterOwnedLeftovers: leftovers == 0
        )
        let diagnostics = combineStage10ADiagnostics(
            requestedStrategy: requestedStrategy,
            project: projectMaterialize,
            container: containerMaterialize,
            failureReason: failureReason
        )
        let materializationImproved = diagnostics.byteForByteCopyAvoided == .true || diagnostics.rootfsWorkAvoided == .true

        return RootfsMaterializationProbeRecord(
            timestamp: stage10ATimestamp(),
            status: status,
            environment: RootfsMaterializationEnvironment(
                containerizationVersion: Self.containerizationVersion,
                containerizationRevision: Self.containerizationRevision,
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                hostArchitecture: stage9DHostArchitecture(),
                filesystemType: filesystemType(at: stateStore.root),
                adapterOwnedStateRoot: redactStage10APath(stateStore.root.path),
                runtimePath: redactStage10APath(runtimeDirectory.path),
                runtimePathRedacted: redactStage10APath(runtimeDirectory.path) != runtimeDirectory.standardizedFileURL.path
            ),
            strategy: diagnostics,
            paths: RootfsMaterializationPaths(
                sourceRootfsPath: redactStage10APath(rootfsCacheURL.path),
                projectRootfsPath: redactStage10APath(projectRootfsURL.path),
                containerRootfsPath: redactStage10APath(containerRootfsURL.path),
                sourceAndDestinationSameVolume: projectMaterialize?.sourceAndDestinationSameVolume
            ),
            durationsSeconds: RootfsMaterializationDurations(
                imageReferenceLookup: imageReferenceLookup,
                imageStoreLookup: imageStoreLookup,
                baseRootfsCacheLookup: baseRootfsCacheLookup,
                baseRootfsUnpack: baseRootfsUnpack,
                projectRootfsMaterialize: projectMaterialize?.durationSeconds,
                containerRootfsMaterialize: containerMaterialize?.durationSeconds,
                mountPrepare: mountPrepare,
                cleanup: cleanupDuration,
                totalRootfsPrep: elapsedSeconds(since: totalStarted)
            ),
            sizesBytes: RootfsMaterializationSizes(
                sourceRootfs: projectMaterialize?.sourceBytes,
                projectRootfs: projectMaterialize?.destinationBytes,
                containerRootfs: containerMaterialize?.destinationBytes,
                apparentSize: containerMaterialize?.apparentSizeBytes ?? projectMaterialize?.apparentSizeBytes,
                allocatedSize: containerMaterialize?.allocatedSizeBytes ?? projectMaterialize?.allocatedSizeBytes,
                bytesCopiedIfKnown: combinedBytesCopied(projectMaterialize, containerMaterialize)
            ),
            io: RootfsMaterializationIOEvidence(
                blockReadBytesWholeRun: nil,
                blockWriteBytesWholeRun: nil,
                phaseBlockIOAttribution: "notMeasured"
            ),
            correctness: RootfsMaterializationCorrectnessEvidence(
                projectRootfsExists: projectExists,
                containerRootfsExists: containerExists,
                containerRootfsReadable: containerReadable,
                ext4ImageLooksValid: ext4LooksValid,
                noMutationOfBaseRootfs: projectMaterialize?.sourceUnchanged == .true,
                baseRootfsChecksumBefore: nil,
                baseRootfsChecksumAfter: nil,
                baseRootfsUnchanged: projectMaterialize?.sourceUnchanged ?? .unknown
            ),
            cleanup: cleanup,
            interpretation: RootfsMaterializationInterpretation(
                materializationImproved: materializationImproved,
                productReady: false,
                nextRecommendedPath: stage10ANextPath(strategy: diagnostics)
            )
        )
    }

    public func guestStatistics(project: String) async throws -> HostFootprintGuestStats {
        guard let state = states[project], state.podCreated else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod project \(project) has no running pod for statistics."
            )
        }
        let stats = try await state.pod.statistics(categories: .all)
        let cgroupLimit = HostFootprintMetricAccumulator.sumCgroupMemoryLimit(
            stats.compactMap { $0.memory?.limitBytes }
        )
        return HostFootprintGuestStats(
            cgroupMemoryCurrentBytes: HostFootprintMetricAccumulator.sumSaturating(stats.compactMap { $0.memory?.usageBytes }),
            cgroupMemoryLimitBytes: cgroupLimit.bytes,
            cgroupMemoryLimitUnlimited: cgroupLimit.unlimited,
            processCount: HostFootprintMetricAccumulator.sumSaturating(stats.compactMap { $0.process?.current }),
            cpuUsageUsec: HostFootprintMetricAccumulator.sumSaturating(stats.compactMap { $0.cpu?.usageUsec }),
            blockReadBytes: HostFootprintMetricAccumulator.sumSaturating(stats.flatMap { $0.blockIO?.devices ?? [] }.map(\.readBytes)),
            blockWriteBytes: HostFootprintMetricAccumulator.sumSaturating(stats.flatMap { $0.blockIO?.devices ?? [] }.map(\.writeBytes))
        )
    }

    public func execInService(
        project: String,
        service: String,
        processID: String,
        arguments: [String]
    ) async throws -> Int32 {
        guard let state = states[project], state.podCreated else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod project \(project) has no running pod for exec."
            )
        }
        guard let containerID = state.containerByService[service] else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod project \(project) has no container for service \(service)."
            )
        }
        let process = try await state.pod.execInContainer(containerID, processID: processID) { config in
            config.arguments = arguments
        }
        try await process.start()
        let status = try await process.wait(timeoutInSeconds: 600)
        try await process.delete()
        return status.exitCode
    }

    private func runStage9BPreCreateRegistrationControl(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) async -> Stage9BHotplugProbeRecord {
        let context = stage9BContext(
            projectPrefix: projectPrefix,
            runLabel: runLabel,
            probeCase: .preCreateRegistrationControl,
            sequence: 1,
            image: image
        )
        var builder = Stage9BRecordBuilder(context: context)

        do {
            try await createStage9BRuntime(context)
            builder.podObjectCreated = true
            try await prepareStage9BRootfs(context, service: context.initialService)
            try await addStage9BContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.initialContainerRegisteredBeforeCreate = true
            builder.addContainerPhase = .beforePodCreate
            builder.podCreateCalled = true
            try await ensurePodCreated(project: context.projectResource)
            builder.podCreateSucceeded = true
            builder.podObjectPhase = "created"
            builder.podActuallyRunning = true
            try await startStage9BContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.initialContainerStarted = true
        } catch {
            builder.recordFailure(error, phase: builder.podCreateCalled && !builder.podCreateSucceeded ? "podCreate" : "addContainer")
        }
        await cleanupStage9BContext(context, builder: &builder)
        return builder.record()
    }

    private func runStage9BEmptyPodPostCreateAdd(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) async -> Stage9BHotplugProbeRecord {
        let context = stage9BContext(
            projectPrefix: projectPrefix,
            runLabel: runLabel,
            probeCase: .emptyPodPostCreateAddContainer,
            sequence: 2,
            image: image
        )
        var builder = Stage9BRecordBuilder(context: context)

        do {
            try await createStage9BRuntime(context)
            builder.podObjectCreated = true
            try await prepareStage9BRootfs(context, service: context.initialService)
            builder.podCreateCalled = true
            try await ensurePodCreated(project: context.projectResource)
            builder.podCreateSucceeded = true
            builder.podObjectPhase = "created"
            builder.podActuallyRunning = true
            builder.postCreateAddContainerAttempted = true
            builder.hotplugAttempted = true
            builder.addContainerPhase = .afterPodCreateEmptyPod
            do {
                try await addStage9BContainer(context, service: context.initialService, containerID: context.initialContainerID)
                builder.postCreateAddContainerSucceeded = true
                builder.hotplugSucceeded = true
            } catch {
                builder.recordFailure(error, phase: "addContainer")
                builder.hotplugUnsupported = stage9BHotplugUnsupported(error)
            }
        } catch {
            builder.recordFailure(error, phase: builder.podCreateCalled ? "podCreate" : "createProjectRuntime")
        }
        await cleanupStage9BContext(context, builder: &builder)
        return builder.record()
    }

    private func runStage9BNonEmptyPodPostCreateAdd(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) async -> Stage9BHotplugProbeRecord {
        let context = stage9BContext(
            projectPrefix: projectPrefix,
            runLabel: runLabel,
            probeCase: .nonEmptyPodPostCreateAddSecondContainer,
            sequence: 3,
            image: image
        )
        var builder = Stage9BRecordBuilder(context: context)

        do {
            try await createStage9BRuntime(context)
            builder.podObjectCreated = true
            try await prepareStage9BRootfs(context, service: context.initialService)
            try await addStage9BContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.initialContainerRegisteredBeforeCreate = true
            builder.podCreateCalled = true
            try await ensurePodCreated(project: context.projectResource)
            builder.podCreateSucceeded = true
            builder.podObjectPhase = "created"
            builder.podActuallyRunning = true
            try await startStage9BContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.initialContainerStarted = true
            builder.postCreateAddContainerAttempted = true
            builder.hotplugAttempted = true
            builder.addContainerPhase = .afterPodCreateNonEmptyPod
            do {
                try await addStage9BContainer(context, service: context.secondService, containerID: context.secondContainerID)
                builder.postCreateAddContainerSucceeded = true
                builder.hotplugSucceeded = true
            } catch {
                builder.recordFailure(error, phase: "addContainer")
                builder.hotplugUnsupported = stage9BHotplugUnsupported(error)
            }
        } catch {
            builder.recordFailure(error, phase: builder.podCreateCalled ? "podCreate" : "createProjectRuntime")
        }
        await cleanupStage9BContext(context, builder: &builder)
        return builder.record()
    }

    private func runStage9BDuplicateContainerGuard(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) async -> Stage9BHotplugProbeRecord {
        let context = stage9BContext(
            projectPrefix: projectPrefix,
            runLabel: runLabel,
            probeCase: .duplicateContainerIDGuard,
            sequence: 4,
            image: image
        )
        var builder = Stage9BRecordBuilder(context: context)

        do {
            try await createStage9BRuntime(context)
            builder.podObjectCreated = true
            try await prepareStage9BRootfs(context, service: context.initialService)
            try await addStage9BContainer(context, service: context.initialService, containerID: context.initialContainerID)
            builder.initialContainerRegisteredBeforeCreate = true
            builder.postCreateAddContainerAttempted = true
            builder.addContainerPhase = .duplicateContainer
            do {
                try await addStage9BDuplicateContainerBypassingAdapterGuard(
                    context,
                    service: context.initialService,
                    containerID: context.initialContainerID
                )
                builder.postCreateAddContainerSucceeded = true
                builder.duplicateContainerDetected = false
            } catch {
                builder.recordFailure(error, phase: "addContainer")
                builder.duplicateContainerDetected = stage9BDuplicateContainerDetected(error)
                builder.mutationBeforeFailure = .false
            }
        } catch {
            builder.recordFailure(error, phase: "createProjectRuntime")
        }
        await cleanupStage9BContext(context, builder: &builder)
        return builder.record()
    }

    private func stage9BContext(
        projectPrefix: String,
        runLabel: String,
        probeCase: Stage9BHotplugProbeCase,
        sequence: Int,
        image: String
    ) -> Stage9BProbeContext {
        let project = ProjectName("\(projectPrefix)-\(runLabel)-\(String(format: "%02d", sequence))-\(probeCase.runtimeResourceSuffix)")
        let projectResource = stateStore.projectName(for: project)
        let initialService = ServicePlan(
            name: "initial",
            image: image,
            command: ["python", "-c", "import time; time.sleep(30)"]
        )
        let secondService = ServicePlan(
            name: "second",
            image: image,
            command: ["python", "-c", "print('stage9b-second')"]
        )
        return Stage9BProbeContext(
            project: project,
            projectResource: projectResource,
            probeCase: probeCase,
            initialService: initialService,
            secondService: secondService,
            initialContainerID: "\(projectResource)-initial",
            secondContainerID: "\(projectResource)-second",
            runtimeDirectory: stateStore.runtimeDirectory(for: project),
            initfsPath: stateStore.initfsPath(project: project),
            initfsCachePath: stateStore.initfsCachePath(),
            rootfsPath: stateStore.rootfsPath(project: project, image: image),
            rootfsCachePath: stateStore.rootfsCachePath(image: image)
        )
    }

    private func stage9DContext(
        projectPrefix: String,
        runLabel: String,
        image: String
    ) -> Stage9DProbeContext {
        let project = Stage9DHotplugProviderProbeRuntimeNames.projectName(
            projectPrefix: projectPrefix,
            runLabel: runLabel
        )
        let projectResource = stateStore.projectName(for: project)
        let initialService = ServicePlan(
            name: "initial",
            image: image,
            command: ["python", "-c", "import time; time.sleep(30)"]
        )
        let secondService = ServicePlan(
            name: "second",
            image: image,
            command: ["python", "-c", "print('stage9d-second')"]
        )
        return Stage9DProbeContext(
            project: project,
            projectResource: projectResource,
            initialService: initialService,
            secondService: secondService,
            initialContainerID: Stage9DHotplugProviderProbeRuntimeNames.initialContainerID(projectResource: projectResource),
            secondContainerID: Stage9DHotplugProviderProbeRuntimeNames.secondContainerID(projectResource: projectResource),
            runtimeDirectory: stateStore.runtimeDirectory(for: project),
            initfsPath: stateStore.initfsPath(project: project),
            initfsCachePath: stateStore.initfsCachePath(),
            rootfsPath: stateStore.rootfsPath(project: project, image: image),
            rootfsCachePath: stateStore.rootfsCachePath(image: image)
        )
    }

    private func createStage9BRuntime(_ context: Stage9BProbeContext) async throws {
        try await createProjectRuntime(
            stage9BEvent(
                context: context,
                kind: .createProjectRuntime,
                resourceName: context.projectResource,
                metadata: [
                    "state": context.runtimeDirectory.path,
                    "hosts": "127.0.0.1 initial second",
                    "initfs": context.initfsPath.path,
                    "initfsCache": context.initfsCachePath.path,
                    "podLifecycle": "stage9b-probe"
                ]
            )
        )
    }

    private func createStage9DRuntime(_ context: Stage9DProbeContext) async throws {
        try await createProjectRuntime(
            stage9DEvent(
                context: context,
                kind: .createProjectRuntime,
                resourceName: context.projectResource,
                metadata: [
                    "state": context.runtimeDirectory.path,
                    "hosts": "127.0.0.1 initial second",
                    "initfs": context.initfsPath.path,
                    "initfsCache": context.initfsCachePath.path,
                    "podLifecycle": "stage9d-hotplug-provider-probe",
                    "stage9DHotplugProviderProbe": "true"
                ]
            )
        )
    }

    private func prepareStage9BRootfs(_ context: Stage9BProbeContext, service: ServicePlan) async throws {
        _ = try await prepareImageRootfs(
            stage9BEvent(
                context: context,
                kind: .prepareImageRootfs,
                resourceName: service.image,
                metadata: [
                    "rootfs": context.rootfsPath.path,
                    "rootfsCache": context.rootfsCachePath.path
                ],
                service: service
            )
        )
    }

    private func prepareStage9DRootfs(_ context: Stage9DProbeContext, service: ServicePlan) async throws {
        _ = try await prepareImageRootfs(
            stage9DEvent(
                context: context,
                kind: .prepareImageRootfs,
                resourceName: service.image,
                metadata: [
                    "rootfs": context.rootfsPath.path,
                    "rootfsCache": context.rootfsCachePath.path
                ],
                service: service
            )
        )
    }

    private func addStage9BContainer(
        _ context: Stage9BProbeContext,
        service: ServicePlan,
        containerID: String
    ) async throws {
        _ = try await addContainer(
            stage9BEvent(
                context: context,
                kind: .addContainer,
                resourceName: containerID,
                metadata: [
                    "image": service.image,
                    "service": service.name,
                    "podAttachment": "stage9b-probe"
                ],
                service: service
            )
        )
    }

    private func addStage9DContainer(
        _ context: Stage9DProbeContext,
        service: ServicePlan,
        containerID: String
    ) async throws {
        _ = try await addContainer(
            stage9DEvent(
                context: context,
                kind: .addContainer,
                resourceName: containerID,
                metadata: [
                    "image": service.image,
                    "service": service.name,
                    "podAttachment": "stage9d-hotplug-provider-probe"
                ],
                service: service
            )
        )
    }

    private func startStage9BContainer(
        _ context: Stage9BProbeContext,
        service: ServicePlan,
        containerID: String
    ) async throws {
        try await startContainer(
            stage9BEvent(
                context: context,
                kind: .startContainer,
                resourceName: containerID,
                metadata: ["service": service.name],
                service: service
            )
        )
    }

    private func startStage9DContainer(
        _ context: Stage9DProbeContext,
        service: ServicePlan,
        containerID: String
    ) async throws {
        try await startContainer(
            stage9DEvent(
                context: context,
                kind: .startContainer,
                resourceName: containerID,
                metadata: ["service": service.name],
                service: service
            )
        )
    }

    private func addStage9BDuplicateContainerBypassingAdapterGuard(
        _ context: Stage9BProbeContext,
        service: ServicePlan,
        containerID: String
    ) async throws {
        let state = try state(for: stage9BEvent(context: context, kind: .addContainer, resourceName: containerID))
        let cloneURL = context.runtimeDirectory
            .appendingPathComponent("rootfs", isDirectory: true)
            .appendingPathComponent("containers", isDirectory: true)
            .appendingPathComponent("\(containerID).ext4")
        try await state.pod.addContainer(
            containerID,
            rootfs: Mount.block(format: "ext4", source: cloneURL.path, destination: "/")
        ) { config in
            config.process = LinuxProcessConfiguration(arguments: service.command)
            config.hostname = service.name
        }
    }

    private func cleanupStage9BContext(
        _ context: Stage9BProbeContext,
        builder: inout Stage9BRecordBuilder
    ) async {
        do {
            try await stopProjectRuntime(
                stage9BEvent(
                    context: context,
                    kind: .stopProjectRuntime,
                    resourceName: context.projectResource,
                    metadata: ["state": context.runtimeDirectory.path]
                )
            )
        } catch {
            builder.recordCleanupFailure(error)
        }
        do {
            try deleteProjectRuntime(
                stage9BEvent(
                    context: context,
                    kind: .deleteProjectRuntime,
                    resourceName: context.projectResource,
                    metadata: ["state": context.runtimeDirectory.path]
                )
            )
        } catch {
            builder.recordCleanupFailure(error)
        }
        let leftovers = leftoverPathCount(at: stateStore.projectDirectory(for: context.project))
        builder.cleanupStateDirectoryExistsAfterCleanup = leftovers > 0
        builder.leftoverPathsCount = leftovers
        builder.cleanupResult = leftovers == 0 && builder.cleanupResult != "cleanupFailed" ? "clean" : "leftovers"
    }

    private func cleanupStage9DContext(
        _ context: Stage9DProbeContext,
        builder: inout Stage9DRecordBuilder
    ) async {
        do {
            try await stopProjectRuntime(
                stage9DEvent(
                    context: context,
                    kind: .stopProjectRuntime,
                    resourceName: context.projectResource,
                    metadata: ["state": context.runtimeDirectory.path]
                )
            )
        } catch {
            builder.recordCleanupFailure(error)
        }
        do {
            try deleteProjectRuntime(
                stage9DEvent(
                    context: context,
                    kind: .deleteProjectRuntime,
                    resourceName: context.projectResource,
                    metadata: ["state": context.runtimeDirectory.path]
                )
            )
        } catch {
            builder.recordCleanupFailure(error)
        }
        let leftovers = leftoverPathCount(at: stateStore.projectDirectory(for: context.project))
        builder.cleanupStateDirectoryExistsAfterCleanup = leftovers > 0
        builder.leftoverPathsCount = leftovers
        builder.zeroAdapterOwnedLeftovers = leftovers == 0
        builder.cleanupResult = leftovers == 0 && builder.cleanupResult != "cleanupFailed" ? "clean" : "leftovers"
    }

    private func stage9BCleanupProof(
        projectPrefix: String,
        runLabel: String
    ) -> Stage9BHotplugProbeRecord {
        let resourcePrefix = ProjectName("\(projectPrefix)-\(runLabel)").adapterOwnedName(prefix: LinuxPodStateStore.ownedPrefix)
        let leftovers = stage9BLeftoverPathCount(resourcePrefix: resourcePrefix)
        return Stage9BHotplugProbeRecord(
            timestamp: stage9BTimestamp(),
            project: resourcePrefix,
            probeCase: .cleanupProof,
            podObjectCreated: false,
            podCreateCalled: false,
            podCreateSucceeded: false,
            podObjectPhase: nil,
            podCreatedStateKnown: true,
            podActuallyRunning: false,
            initialContainerRegisteredBeforeCreate: false,
            initialContainerStarted: false,
            postCreateAddContainerAttempted: false,
            postCreateAddContainerSucceeded: false,
            addContainerPhase: .unknown,
            hotplugAttempted: false,
            hotplugSucceeded: false,
            hotplugUnsupported: false,
            duplicateContainerDetected: false,
            failurePhase: nil,
            failureErrorType: nil,
            failureErrorMessage: nil,
            mutationBeforeFailure: .false,
            cleanupResult: leftovers == 0 ? "clean" : "leftovers",
            cleanupStateDirectoryExistsAfterCleanup: leftovers > 0,
            leftoverPathsCount: leftovers,
            runtimePackageVersion: Self.containerizationVersion,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            containerizationVersion: Self.containerizationVersion
        )
    }

    private func stage9BEvent(
        context: Stage9BProbeContext,
        kind: PlannedActionKind,
        resourceName: String? = nil,
        metadata: [String: String] = [:],
        service: ServicePlan? = nil
    ) -> LinuxPodRuntimeEvent {
        LinuxPodRuntimeEvent(
            project: context.projectResource,
            action: PlannedAction(
                order: 0,
                kind: kind,
                resourceName: resourceName,
                description: "Stage 9B hotplug probe \(context.probeCase.rawValue)",
                mutatesRuntime: true,
                metadata: metadata
            ),
            service: service
        )
    }

    private func stage9DEvent(
        context: Stage9DProbeContext,
        kind: PlannedActionKind,
        resourceName: String? = nil,
        metadata: [String: String] = [:],
        service: ServicePlan? = nil
    ) -> LinuxPodRuntimeEvent {
        LinuxPodRuntimeEvent(
            project: context.projectResource,
            action: PlannedAction(
                order: 0,
                kind: kind,
                resourceName: resourceName,
                description: "Stage 9D hotplug provider feasibility probe",
                mutatesRuntime: true,
                metadata: metadata
            ),
            service: service
        )
    }

    private func stage9DConfigExtensionCount(project: String) -> Int {
        states[project]?.pod.config.extensions.count ?? 0
    }

    private func stage9DProbeSnapshot(project: String) -> CCAHotplugFeasibilitySnapshot? {
        states[project]?.stage9DProbeRecorder?.snapshot()
    }

    private func leftoverPathCount(at url: URL) -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return 1
        }
        var count = 1
        for _ in enumerator {
            count += 1
        }
        return count
    }

    private func stage9BLeftoverPathCount(resourcePrefix: String) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: stateStore.root,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return contents
            .filter { $0.lastPathComponent.hasPrefix(resourcePrefix) }
            .map(leftoverPathCount(at:))
            .reduce(0, +)
    }

    private func stage9BHotplugUnsupported(_ error: Error) -> Bool {
        let description = "\(error)"
        return description.contains("pod must be initialized to add container")
            || description.contains("hotplug not supported")
            || description.contains("unsupported")
    }

    private func stage9BDuplicateContainerDetected(_ error: Error) -> Bool {
        let description = "\(error)"
        return description.contains("already exists")
            || description.contains("invalidArgument")
    }

    private func stage9DHotplugUnsupported(_ error: Error) -> Bool {
        let description = "\(error)"
        return description.contains("unsupported")
            || description.contains("hotplug")
            || description.contains("attach")
    }

    private func createProjectRuntime(_ event: LinuxPodRuntimeEvent) async throws {
        if states[event.project] != nil {
            return
        }
        let runtimeDirectory = try runtimeDirectory(from: event)
        try ensureAdapterOwnedRuntimeDirectory(runtimeDirectory)
        try ensureVirtualizationEntitlement()
        let kernel = try findKernel()

        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let imageStore = try ImageStore(path: runtimeDirectory.appendingPathComponent("image-store", isDirectory: true))
        let initImage = try await imageStore.getInitImage(reference: initImageReference)
        let initfs = try await prepareInitfs(
            event: event,
            initImage: initImage,
            runtimeDirectory: runtimeDirectory
        )
        var kernelConfig = Kernel(path: kernel, platform: .linuxArm)
        kernelConfig.commandLine.addDebug()
        let vmIntrospection = VMIntrospectionRecorder()
        let stage9DProbeRecorder = event.metadata["stage9DHotplugProviderProbe"] == "true"
            ? CCAHotplugFeasibilityRecorder(repositoryRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
            : nil
        let vmm = IntrospectingVZVirtualMachineManager(
            base: VZVirtualMachineManager(kernel: kernelConfig, initialFilesystem: initfs),
            recorder: vmIntrospection
        )
        let pod = try LinuxPod(event.project, vmm: vmm) { config in
            config.cpus = podCPUs
            config.memoryInBytes = podMemoryBytes
            config.hostname = event.project
            config.hosts = hosts(from: event)
            config.bootLog = .file(
                path: runtimeDirectory.appendingPathComponent("boot.log"),
                append: false
            )
            if let stage9DProbeRecorder {
                config.extensions.append(CCAHotplugFeasibilityExtension(recorder: stage9DProbeRecorder))
            }
        }
        states[event.project] = ProjectRuntime(
            runtimeDirectory: runtimeDirectory,
            imageStore: imageStore,
            pod: pod,
            vmIntrospection: vmIntrospection,
            stage9DProbeRecorder: stage9DProbeRecorder
        )
    }

    private func prepareImageRootfs(_ event: LinuxPodRuntimeEvent) async throws -> [String: String] {
        var state = try state(for: event)
        var metadata: [String: String] = [:]
        guard let image = event.resourceName, !image.isEmpty else {
            throw unsupported(event, reason: "missing image reference")
        }
        guard let rootfsValue = event.metadata["rootfs"], !rootfsValue.isEmpty else {
            throw unsupported(event, reason: "missing rootfs path")
        }
        let rootfsURL = URL(fileURLWithPath: rootfsValue)
        let rootfsCacheURL = event.metadata["rootfsCache"].map { URL(fileURLWithPath: $0) }
        metadata["image"] = image
        metadata["rootfsDestinationPath"] = rootfsURL.path
        metadata["rootfsMountType"] = "block"
        metadata["rootfsMountFormat"] = "ext4"
        metadata["rootfsMountIsBlock"] = "true"
        try FileManager.default.createDirectory(
            at: rootfsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let imageResolveStarted = Date()
        let imageValue = try await state.imageStore.get(reference: image, pull: true)
        metadata["imageReferenceResolveDuration"] = durationString(since: imageResolveStarted)
        let platformValidationStarted = Date()
        if let imageConfig = try await imageValue.config(for: SystemPlatform.linuxArm.ociPlatform()).config {
            state.defaultsByImage[image] = ImageRuntimeDefaults(
                process: LinuxProcessConfiguration(from: imageConfig),
                declaredVolumes: try await declaredVolumes(for: imageValue)
            )
        }
        metadata["platformValidationDuration"] = durationString(since: platformValidationStarted)
        if let rootfsCacheURL {
            try ensureAdapterOwnedCachePath(rootfsCacheURL)
            try FileManager.default.createDirectory(
                at: rootfsCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cacheLookupStarted = Date()
            let cacheHit = FileManager.default.fileExists(atPath: rootfsCacheURL.path)
            metadata["baseRootfsCacheLookupDuration"] = durationString(since: cacheLookupStarted)
            metadata["baseRootfsCacheHit"] = "\(cacheHit)"
            metadata["rootfsSourcePath"] = rootfsCacheURL.path
            metadata["rootfsCacheClaim"] = cacheHit ? RootfsCacheClaim.baseArtifactHit.rawValue : RootfsCacheClaim.noHit.rawValue
            if !cacheHit {
                let unpackStarted = Date()
                let unpacker = EXT4Unpacker(blockSizeInBytes: defaultRootfsSizeBytes)
                _ = try await unpacker.unpack(
                    imageValue,
                    for: SystemPlatform.linuxArm.ociPlatform(),
                    at: rootfsCacheURL
                )
                metadata["baseRootfsCreateOrUnpackDuration"] = durationString(since: unpackStarted)
            } else {
                metadata["baseRootfsCreateOrUnpackDuration"] = "0.000000"
            }
            let copyStarted = Date()
            try copyReplacing(source: rootfsCacheURL, destination: rootfsURL)
            metadata["containerRootfsMaterializeDuration"] = durationString(since: copyStarted)
            metadata["containerRootfsCopyDuration"] = metadata["containerRootfsMaterializeDuration"]
            metadata["rootfsMaterializationStrategy"] = RootfsMaterializationStrategy.copy.rawValue
            metadata["rootfsWorkAvoided"] = EvidenceTruthValue.false.rawValue
            if let bytesCopied = fileSize(rootfsURL) {
                metadata["rootfsBytesCopied"] = "\(bytesCopied)"
            }
        } else if !FileManager.default.fileExists(atPath: rootfsURL.path) {
            let unpackStarted = Date()
            let unpacker = EXT4Unpacker(blockSizeInBytes: defaultRootfsSizeBytes)
            _ = try await unpacker.unpack(
                imageValue,
                for: SystemPlatform.linuxArm.ociPlatform(),
                at: rootfsURL
            )
            metadata["baseRootfsCreateOrUnpackDuration"] = durationString(since: unpackStarted)
            metadata["rootfsSourcePath"] = image
            metadata["rootfsCacheClaim"] = RootfsCacheClaim.noHit.rawValue
            metadata["rootfsMaterializationStrategy"] = RootfsMaterializationStrategy.unpack.rawValue
            metadata["rootfsWorkAvoided"] = EvidenceTruthValue.false.rawValue
            if let bytesCopied = fileSize(rootfsURL) {
                metadata["rootfsBytesCopied"] = "\(bytesCopied)"
            }
        } else {
            metadata["baseRootfsCacheHit"] = "true"
            metadata["rootfsSourcePath"] = rootfsURL.path
            metadata["rootfsCacheClaim"] = RootfsCacheClaim.fullContainerRootfsHit.rawValue
            metadata["rootfsMaterializationStrategy"] = RootfsMaterializationStrategy.reuse.rawValue
            metadata["rootfsWorkAvoided"] = EvidenceTruthValue.true.rawValue
        }
        state.rootfsPathByImage[image] = rootfsURL
        states[event.project] = state
        return metadata
    }

    private func prepareInitfs(
        event: LinuxPodRuntimeEvent,
        initImage: InitImage,
        runtimeDirectory: URL
    ) async throws -> Mount {
        let runtimeURL = URL(
            fileURLWithPath: event.metadata["initfs"] ?? runtimeDirectory.appendingPathComponent("initfs.ext4").path
        )
        try FileManager.default.createDirectory(
            at: runtimeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let cacheValue = event.metadata["initfsCache"], !cacheValue.isEmpty else {
            return try await initImage.initBlock(at: runtimeURL, for: .linuxArm)
        }

        let cacheURL = URL(fileURLWithPath: cacheValue)
        try ensureAdapterOwnedCachePath(cacheURL)
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            _ = try await initImage.initBlock(at: cacheURL, for: .linuxArm)
        }
        try copyReplacing(source: cacheURL, destination: runtimeURL)
        return .block(
            format: "ext4",
            source: runtimeURL.path,
            destination: "/",
            options: ["ro"]
        )
    }

    // Each container gets a private materialized copy of the prepared base image rootfs.
    // Attaching one ext4 block image read-write to multiple containers would
    // corrupt the filesystem; Stage 10A probes whether clone/COW can safely
    // replace this baseline copy path.
    private func containerRootfs(
        for service: ServicePlan,
        containerID: String,
        in state: ProjectRuntime
    ) throws -> (mount: Mount, metadata: [String: String]) {
        var metadata: [String: String] = [
            "service": service.name,
            "image": service.image
        ]
        guard let baseURL = state.rootfsPathByImage[service.image] else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod rootfs for \(service.image) was not prepared before adding \(service.name)."
            )
        }
        let mountPrepareStarted = Date()
        let containersDirectory = state.runtimeDirectory
            .appendingPathComponent("rootfs", isDirectory: true)
            .appendingPathComponent("containers", isDirectory: true)
        try FileManager.default.createDirectory(at: containersDirectory, withIntermediateDirectories: true)
        metadata["containerRootfsMountPrepareDuration"] = durationString(since: mountPrepareStarted)
        let cloneURL = containersDirectory.appendingPathComponent("\(containerID).ext4")
        if FileManager.default.fileExists(atPath: cloneURL.path) {
            try FileManager.default.removeItem(at: cloneURL)
        }
        let copyStarted = Date()
        try FileManager.default.copyItem(at: baseURL, to: cloneURL)
        metadata["containerRootfsMaterializeDuration"] = durationString(since: copyStarted)
        metadata["containerRootfsCopyDuration"] = metadata["containerRootfsMaterializeDuration"]
        metadata["rootfsSourcePath"] = baseURL.path
        metadata["rootfsDestinationPath"] = cloneURL.path
        metadata["rootfsMountType"] = "block"
        metadata["rootfsMountFormat"] = "ext4"
        metadata["rootfsMountIsBlock"] = "true"
        metadata["rootfsMaterializationStrategy"] = RootfsMaterializationStrategy.copy.rawValue
        metadata["rootfsWorkAvoided"] = EvidenceTruthValue.false.rawValue
        metadata["rootfsCacheClaim"] = RootfsCacheClaim.baseArtifactHit.rawValue
        if let bytesCopied = fileSize(cloneURL) {
            metadata["rootfsBytesCopied"] = "\(bytesCopied)"
        }
        return (
            Mount.block(
                format: "ext4",
                source: cloneURL.path,
                destination: "/"
            ),
            metadata
        )
    }

    private func createNamedVolume(_ event: LinuxPodRuntimeEvent) throws {
        var state = try state(for: event)
        guard let name = event.resourceName, let path = event.metadata["path"] else {
            throw unsupported(event, reason: "missing named volume metadata")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try ensureAdapterOwnedVolumePath(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Named volumes are guest-local ext4 block images, not virtiofs shares:
        // shared directories reject the chown/chmod that image entrypoints such
        // as postgres run against their data directories.
        let imageURL = url.appendingPathComponent("volume.ext4")
        if !FileManager.default.fileExists(atPath: imageURL.path) {
            let formatter = try EXT4.Formatter(
                FilePath(imageURL.path),
                minDiskSize: namedVolumeSizeBytes
            )
            // Drop the formatter-created /lost+found: initdb-style entrypoints
            // require an empty data directory at the mount point.
            try formatter.unlink(path: FilePath("/lost+found"))
            try formatter.close()
        }
        state.volumePaths[name] = url
        states[event.project] = state
    }

    private func validateBindMount(_ event: LinuxPodRuntimeEvent) throws {
        guard let source = event.resourceName else {
            throw unsupported(event, reason: "missing bind mount source")
        }
        let path = NSString(string: source).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Bind mount source \(source) disappeared before LinuxPod execution."
            )
        }
    }

    private func addContainer(_ event: LinuxPodRuntimeEvent) async throws -> [String: String] {
        var state = try state(for: event)
        guard let service = event.service else {
            throw unsupported(event, reason: "missing service plan")
        }
        guard let containerID = event.resourceName else {
            throw unsupported(event, reason: "missing container resource name")
        }
        if state.containers.contains(containerID) {
            return [
                "containerReuse": "hit",
                "podAttachment": state.podCreated ? "reused-existing-pod" : "registered-before-create"
            ]
        }
        let rootfs = try containerRootfs(for: service, containerID: containerID, in: state)

        let mounts = try containerMounts(for: service, in: state)
        let logCapture = RuntimeLogCapture()
        var process = try processConfiguration(for: service, in: state)
        var metadata = containerMetadata(for: service, process: process, state: state)
        metadata.merge(rootfs.metadata) { current, _ in current }
        metadata["containerID"] = containerID
        let logsDirectory = state.runtimeDirectory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let stdoutLog = logsDirectory.appendingPathComponent("\(service.name).stdout.log")
        let stderrLog = logsDirectory.appendingPathComponent("\(service.name).stderr.log")
        process.stdout = try LinuxPodLogWriter(capture: logCapture, stream: .stdout, fileURL: stdoutLog)
        process.stderr = try LinuxPodLogWriter(capture: logCapture, stream: .stderr, fileURL: stderrLog)
        metadata["logStdout"] = "logs/\(service.name).stdout.log"
        metadata["logStderr"] = "logs/\(service.name).stderr.log"
        let resolvedProcess = process
        do {
            try await state.pod.addContainer(containerID, rootfs: rootfs.mount) { config in
                config.process = resolvedProcess
                config.mounts += mounts
                config.hostname = service.name
            }
        } catch {
            state.lastAddContainerAttemptMetadata = metadata
            states[event.project] = state
            throw error
        }
        state.lastAddContainerAttemptMetadata = nil
        state.containers.insert(containerID)
        state.containerByService[service.name] = containerID
        state.logCaptureByService[service.name] = logCapture
        states[event.project] = state
        return metadata
    }

    private func declaredVolumes(for image: Image) async throws -> [String] {
        let manifest = try await image.manifest(for: SystemPlatform.linuxArm.ociPlatform())
        let configContent = try await image.getContent(digest: manifest.config.digest)
        guard let object = try JSONSerialization.jsonObject(with: configContent.data()) as? [String: Any],
              let config = object["config"] as? [String: Any],
              let volumes = config["Volumes"] as? [String: Any] else {
            return []
        }
        return volumes.keys.sorted()
    }

    private func processConfiguration(
        for service: ServicePlan,
        in state: ProjectRuntime
    ) throws -> LinuxProcessConfiguration {
        var process: LinuxProcessConfiguration
        if service.command.isEmpty {
            guard let imageDefaults = state.defaultsByImage[service.image] else {
                throw RuntimeBackendError.runtimeUnavailable(
                    "LinuxPod image defaults for \(service.image) were not resolved before adding \(service.name)."
                )
            }
            process = imageDefaults.process
            guard !process.arguments.isEmpty else {
                throw RuntimeBackendError.runtimeUnavailable(
                    "Image \(service.image) has no Entrypoint or Cmd for LinuxPod service \(service.name)."
                )
            }
        } else {
            process = LinuxProcessConfiguration(arguments: service.command)
        }
        process.environmentVariables = mergeEnvironment(
            base: process.environmentVariables,
            overrides: service.environment
        )
        return process
    }

    private func mergeEnvironment(
        base: [String],
        overrides: [EnvironmentVariable]
    ) -> [String] {
        var orderedKeys: [String] = []
        var valuesByKey: [String: String] = [:]

        func append(_ key: String, value: String) {
            if valuesByKey[key] == nil {
                orderedKeys.append(key)
            }
            valuesByKey[key] = value
        }

        for entry in base {
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let keyPart = parts.first else {
                continue
            }
            let value = parts.count == 2 ? String(parts[1]) : ""
            append(String(keyPart), value: value)
        }
        for override in overrides {
            append(override.key, value: override.value)
        }
        return orderedKeys.map { key in
            "\(key)=\(valuesByKey[key] ?? "")"
        }
    }

    private func containerMetadata(
        for service: ServicePlan,
        process: LinuxProcessConfiguration,
        state: ProjectRuntime
    ) -> [String: String] {
        let imageDefaults = state.defaultsByImage[service.image]
        return [
            "process": service.command.isEmpty ? "image-defaults" : "explicit-command",
            "arguments": process.arguments.joined(separator: " "),
            "workingDirectory": process.workingDirectory,
            "imageDefaultEnvironmentCount": "\(imageDefaults?.process.environmentVariables.count ?? 0)",
            "imageDeclaredVolumes": imageDefaults?.declaredVolumes.joined(separator: ",") ?? ""
        ]
    }

    private func startContainer(_ event: LinuxPodRuntimeEvent) async throws {
        var state = try state(for: event)
        guard let containerID = event.resourceName else {
            throw unsupported(event, reason: "missing container resource name")
        }
        if state.startedContainers.contains(containerID) {
            return
        }
        if !state.podCreated {
            try await state.pod.create()
            state.podCreated = true
        }
        try await state.pod.startContainer(containerID)
        state.startedContainers.insert(containerID)
        states[event.project] = state
    }

    private func waitForReadiness(_ event: LinuxPodRuntimeEvent) async throws {
        let state = try state(for: event)
        guard let service = event.service else {
            throw unsupported(event, reason: "missing service plan")
        }
        for readiness in service.readiness {
            switch readiness.kind {
            case .serviceStarted:
                continue
            case .serviceHealthy:
                try await runHealthcheck(readiness, service: service, state: state)
            case .serviceCompletedSuccessfully:
                guard state.completedJobs.contains(service.name) else {
                    throw RuntimeBackendError.runtimeUnavailable(
                        "LinuxPod job \(service.name) has not completed successfully."
                    )
                }
            }
        }
    }

    private func runJob(_ event: LinuxPodRuntimeEvent) async throws -> [String: String] {
        var state = try state(for: event)
        guard let service = event.service else {
            throw unsupported(event, reason: "missing job service plan")
        }
        guard let containerID = event.resourceName else {
            throw unsupported(event, reason: "missing job container resource name")
        }
        if state.completedJobs.contains(service.name) {
            return [
                "exitCode": "0",
                "logs": "reused-completed-job",
                "jobReuse": "completed-before-run"
            ]
        }
        if !state.podCreated {
            try await state.pod.create()
            state.podCreated = true
        }
        try await state.pod.startContainer(containerID)
        state.startedContainers.insert(containerID)
        let status = try await state.pod.waitContainer(containerID)
        guard status.exitCode == 0 else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod job \(service.name) exited with status \(status.exitCode). \(serviceLogContext(service, state: state))"
            )
        }
        state.completedJobs.insert(service.name)
        let metadata = state.logCaptureByService[service.name]?.evidenceMetadata(exitCode: status.exitCode) ?? [
            "exitCode": "\(status.exitCode)",
            "logs": "not-captured"
        ]
        states[event.project] = state
        return metadata
    }

    private func collectLogs(_ event: LinuxPodRuntimeEvent) throws {
        let state = try state(for: event)
        guard let containerID = event.resourceName, state.containers.contains(containerID) else {
            throw unsupported(event, reason: "unknown container for logs")
        }
    }

    private func inspectStatus(_ event: LinuxPodRuntimeEvent) throws {
        _ = states[event.project]
    }

    private func stopProjectRuntime(_ event: LinuxPodRuntimeEvent) async throws {
        guard var state = states[event.project] else {
            let runtimeDirectory = try runtimeDirectory(from: event)
            try ensureAdapterOwnedRuntimeDirectory(runtimeDirectory)
            return
        }
        if state.podCreated {
            try await state.pod.stop()
            state.podCreated = false
        }
        states[event.project] = state
    }

    private func deleteProjectRuntime(_ event: LinuxPodRuntimeEvent) throws {
        let runtimeDirectory = try runtimeDirectory(from: event)
        try ensureAdapterOwnedRuntimeDirectory(runtimeDirectory)
        if FileManager.default.fileExists(atPath: runtimeDirectory.path) {
            try FileManager.default.removeItem(at: runtimeDirectory)
        }
        try stateStore.removeEmptyProjectDirectories(
            projectDirectory: runtimeDirectory.deletingLastPathComponent()
        )
        states[event.project] = nil
    }

    private func cleanupNamedVolume(_ event: LinuxPodRuntimeEvent) throws {
        guard let path = event.metadata["path"] else {
            throw unsupported(event, reason: "missing named volume cleanup path")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try ensureAdapterOwnedVolumePath(url)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let projectDirectory = url
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try stateStore.removeEmptyProjectDirectories(projectDirectory: projectDirectory)
    }

    private func containerMounts(for service: ServicePlan, in state: ProjectRuntime) throws -> [Mount] {
        try service.mounts.map { mount in
            let options = mount.readOnly ? ["ro"] : []
            switch mount.kind {
            case .bind:
                let source = NSString(string: mount.source).expandingTildeInPath
                return Mount.share(
                    source: URL(fileURLWithPath: source).standardizedFileURL.path,
                    destination: mount.target,
                    options: options
                )
            case .namedVolume:
                guard let volumePath = state.volumePaths[mount.source] else {
                    throw RuntimeBackendError.runtimeUnavailable(
                        "Named volume \(mount.source) was not prepared before adding \(service.name)."
                    )
                }
                return Mount.block(
                    format: "ext4",
                    source: volumePath.appendingPathComponent("volume.ext4").path,
                    destination: mount.target,
                    options: options
                )
            }
        }
    }

    private func hosts(from event: LinuxPodRuntimeEvent) -> Hosts? {
        guard let hostsValue = event.metadata["hosts"] else {
            return nil
        }
        let parts = hostsValue.split(separator: " ").map(String.init)
        guard let ipAddress = parts.first, parts.count > 1 else {
            return nil
        }
        return Hosts(
            entries: Hosts.default.entries + [
                Hosts.Entry(
                    ipAddress: ipAddress,
                    hostnames: Array(parts.dropFirst()),
                    comment: "Container Compose Adapter services"
                )
            ],
            comment: "Container Compose Adapter"
        )
    }

    private func runHealthcheck(
        _ readiness: ReadinessProbe,
        service: ServicePlan,
        state: ProjectRuntime
    ) async throws {
        guard !readiness.command.isEmpty else {
            throw unsupportedReadiness(service, readiness: readiness, reason: "missing healthcheck command")
        }
        guard let containerID = state.containerByService[service.name] else {
            throw unsupportedReadiness(service, readiness: readiness, reason: "unknown service container")
        }

        let deadline = Date().addingTimeInterval(TimeInterval(readiness.timeoutSeconds))
        var attempt = 0
        repeat {
            attempt += 1
            do {
                let process = try await state.pod.execInContainer(
                    containerID,
                    processID: "readiness-\(service.name)-\(attempt)"
                ) { config in
                    config.arguments = readiness.command
                }
                try await process.start()
                let status = try await process.wait(timeoutInSeconds: 5)
                try await process.delete()
                if status.exitCode == 0 {
                    return
                }
            } catch {
                throw RuntimeBackendError.runtimeUnavailable(
                    "LinuxPod service \(service.name) readiness probe \(attempt) failed: \(error). \(serviceLogContext(service, state: state))"
                )
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } while Date() < deadline

        throw RuntimeBackendError.runtimeUnavailable(
            "LinuxPod service \(service.name) did not pass \(readiness.kind.rawValue) within \(readiness.timeoutSeconds)s. \(serviceLogContext(service, state: state))"
        )
    }

    private func serviceLogContext(_ service: ServicePlan, state: ProjectRuntime) -> String {
        guard let capture = state.logCaptureByService[service.name] else {
            return "Service logs: not-captured."
        }
        return "Service stdout tail: \(capture.stdoutTail()) Service stderr tail: \(capture.stderrTail())"
    }

    private func unsupportedReadiness(
        _ service: ServicePlan,
        readiness: ReadinessProbe,
        reason: String
    ) -> RuntimeBackendError {
        .runtimeUnavailable(
            "LinuxPod readiness \(readiness.kind.rawValue) for \(service.name) is unavailable: \(reason)."
        )
    }

    private func runtimeDirectory(from event: LinuxPodRuntimeEvent) throws -> URL {
        guard let state = event.metadata["state"], !state.isEmpty else {
            throw unsupported(event, reason: "missing runtime state path")
        }
        return URL(fileURLWithPath: state, isDirectory: true)
    }

    private func state(for event: LinuxPodRuntimeEvent) throws -> ProjectRuntime {
        guard let state = states[event.project] else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod project \(event.project) has no initialized runtime state."
            )
        }
        return state
    }

    private func findKernel() throws -> URL {
        let kernelsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.container/kernels")
        let kernels = (try? FileManager.default.contentsOfDirectory(
            at: kernelsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let candidates = kernels.filter { $0.lastPathComponent.hasPrefix("vmlinux") }
        guard let latest = candidates.sorted(by: { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }).first else {
            throw RuntimeBackendError.runtimeUnavailable("No vmlinux kernel found under \(kernelsDirectory.path).")
        }
        return latest
    }

    private func ensureVirtualizationEntitlement() throws {
        guard let task = SecTaskCreateFromSelf(nil) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Unable to inspect process entitlements before LinuxPod VM creation."
            )
        }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.virtualization" as CFString,
            nil
        )
        guard let entitlement,
              CFGetTypeID(entitlement) == CFBooleanGetTypeID(),
              CFBooleanGetValue((entitlement as! CFBoolean)) else {
            throw RuntimeBackendError.runtimeUnavailable(
                RuntimePrerequisiteMessages.virtualizationEntitlementMissing
            )
        }
    }

    private func ensureAdapterOwnedRuntimeDirectory(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard standardized.lastPathComponent == "runtime",
              standardized.deletingLastPathComponent().lastPathComponent.hasPrefix(LinuxPodStateStore.ownedPrefix) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing to mutate non-adapter runtime path \(url.path)."
            )
        }
    }

    private func ensureAdapterOwnedCachePath(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        guard standardized.pathExtension == "ext4",
              components.contains(".container-compose-adapter"),
              components.contains("cache") else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing to mutate non-adapter cache path \(url.path)."
            )
        }
    }

    private func ensureAdapterOwnedVolumePath(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        let volumes = standardized.deletingLastPathComponent()
        let project = volumes.deletingLastPathComponent()
        guard volumes.lastPathComponent == "volumes",
              project.lastPathComponent.hasPrefix(LinuxPodStateStore.ownedPrefix) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing to mutate non-adapter volume path \(url.path)."
            )
        }
    }

    private func unsupported(_ event: LinuxPodRuntimeEvent, reason: String? = nil) -> RuntimeBackendError {
        let suffix = reason.map { ": \($0)" } ?? "."
        return .runtimeUnavailable("LinuxPod runtime action \(event.kind.rawValue) is not available in the Phase 3 executor\(suffix)")
    }

    private func combineStage10ADiagnostics(
        requestedStrategy: RootfsMaterializationStrategy,
        project: RootfsMaterializationResult?,
        container: RootfsMaterializationResult?,
        failureReason: String?
    ) -> RootfsMaterializationDiagnostics {
        let results = [project, container].compactMap { $0 }
        guard !results.isEmpty else {
            return RootfsMaterializationDiagnostics(
                requestedStrategy: requestedStrategy,
                actualStrategy: .unknown,
                fallbackStrategy: nil,
                fallbackReason: failureReason,
                cloneSupported: false,
                cloneAttempted: false,
                cloneReturnedSuccess: false,
                cloneVerified: false,
                cloneVerificationStrength: .unknown,
                cloneSucceeded: false,
                copyAttempted: false,
                copySucceeded: false,
                publicCloneAPIMissing: false,
                byteForByteCopyAvoided: .unknown,
                rootfsWorkAvoided: .unknown
            )
        }
        let fallbackReasons = results.compactMap(\.fallbackReason) + [failureReason].compactMap { $0 }
        let cloneSucceeded = results.allSatisfy(\.cloneSucceeded)
        let cloneVerified = cloneSucceeded && results.allSatisfy(\.cloneVerified)
        let copyAttempted = results.contains(where: \.copyAttempted)
        let copySucceeded = copyAttempted && results.filter(\.copyAttempted).allSatisfy(\.copySucceeded)
        let actualStrategy: RootfsMaterializationStrategy
        if cloneSucceeded {
            actualStrategy = requestedStrategy == .auto ? results.last?.actualStrategy ?? .clonefile : requestedStrategy
        } else if copySucceeded {
            actualStrategy = .fullCopy
        } else {
            actualStrategy = results.last?.actualStrategy ?? .unknown
        }
        return RootfsMaterializationDiagnostics(
            requestedStrategy: requestedStrategy,
            actualStrategy: actualStrategy,
            fallbackStrategy: results.compactMap(\.fallbackStrategy).first,
            fallbackReason: fallbackReasons.isEmpty ? nil : fallbackReasons.joined(separator: "; "),
            cloneSupported: results.allSatisfy(\.cloneSupported),
            cloneAttempted: results.contains(where: \.cloneAttempted),
            cloneReturnedSuccess: results.contains(where: \.cloneReturnedSuccess),
            cloneVerified: cloneVerified,
            cloneVerificationStrength: cloneVerified ? strongestCommonCloneVerification(results) : .notApplicable,
            cloneSucceeded: cloneSucceeded,
            copyAttempted: copyAttempted,
            copySucceeded: copySucceeded,
            publicCloneAPIMissing: results.contains(where: \.publicCloneAPIMissing),
            byteForByteCopyAvoided: combinedTruth(results.map(\.byteForByteCopyAvoided)),
            rootfsWorkAvoided: combinedTruth(results.map(\.rootfsWorkAvoided))
        )
    }

    private func strongestCommonCloneVerification(_ results: [RootfsMaterializationResult]) -> RootfsCloneVerificationStrength {
        if results.allSatisfy({ $0.cloneVerificationStrength == .strong }) {
            return .strong
        }
        if results.allSatisfy({ $0.cloneVerificationStrength == .strong || $0.cloneVerificationStrength == .weak }) {
            return .weak
        }
        return .unknown
    }

    private func combinedTruth(_ values: [EvidenceTruthValue]) -> EvidenceTruthValue {
        guard !values.isEmpty else {
            return .unknown
        }
        if values.allSatisfy({ $0 == .true }) {
            return .true
        }
        if values.allSatisfy({ $0 == .false }) {
            return .false
        }
        return .unknown
    }

    private func combinedBytesCopied(
        _ project: RootfsMaterializationResult?,
        _ container: RootfsMaterializationResult?
    ) -> UInt64? {
        let values = [project?.bytesCopiedIfKnown, container?.bytesCopiedIfKnown].compactMap { $0 }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0) { partial, value in
            let sum = partial.addingReportingOverflow(value)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }

    private func stage10ANextPath(strategy: RootfsMaterializationDiagnostics) -> RootfsMaterializationNextRecommendedPath {
        guard strategy.byteForByteCopyAvoided == .true || strategy.rootfsWorkAvoided == .true else {
            if strategy.publicCloneAPIMissing || strategy.fallbackStrategy == .fullCopy {
                return .investigateWritableLayer
            }
            return .keepFullCopy
        }
        switch strategy.actualStrategy {
        case .apfsClone:
            return .useAPFSCloneForRootfs
        case .copyfileClone:
            return .useCopyfileCloneForRootfs
        case .clonefile, .auto, .clone:
            return .useClonefileForRootfs
        case .fullCopy,
             .fileManagerCopy,
             .unsupported,
             .unpack,
             .copy,
             .reuse,
             .unknown:
            return .unknown
        }
    }

    private func ext4MagicLooksValid(_ url: URL) -> Bool? {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer {
            try? handle.close()
        }
        do {
            try handle.seek(toOffset: 1080)
            let data = try handle.read(upToCount: 2)
            return data == Data([0x53, 0xEF])
        } catch {
            return nil
        }
    }

    private func filesystemType(at _: URL) -> String? {
        nil
    }

    private func redactStage10APath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let rootPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .standardizedFileURL
            .path
        if standardized == rootPath {
            return "<repo>"
        }
        if standardized.hasPrefix(rootPath + "/") {
            return "<repo>" + String(standardized.dropFirst(rootPath.count))
        }
        return standardized
    }

    private func elapsedSeconds(since start: Date) -> Double {
        Date().timeIntervalSince(start)
    }

    private func copyReplacing(source: URL, destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func durationString(since start: Date) -> String {
        String(format: "%.6f", Date().timeIntervalSince(start))
    }

    private func fileSize(_ url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return UInt64(fileSize)
    }
}

private struct ProjectRuntime: Sendable {
    let runtimeDirectory: URL
    let imageStore: ImageStore
    let pod: LinuxPod
    let vmIntrospection: VMIntrospectionRecorder
    let stage9DProbeRecorder: CCAHotplugFeasibilityRecorder?
    var podCreated = false
    var rootfsPathByImage: [String: URL] = [:]
    var defaultsByImage: [String: ImageRuntimeDefaults] = [:]
    var volumePaths: [String: URL] = [:]
    var containers: Set<String> = []
    var startedContainers: Set<String> = []
    var containerByService: [String: String] = [:]
    var completedJobs: Set<String> = []
    var logCaptureByService: [String: RuntimeLogCapture] = [:]
    var lastAddContainerAttemptMetadata: [String: String]?
}

private struct VMIntrospectionSnapshot: Sendable {
    let vmInstanceType: String
    let hotplugProviderInstalled: Bool
    let hotplugProviderType: String?
}

private final class VMIntrospectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var latestSnapshot: VMIntrospectionSnapshot?

    func record(instance: any VirtualMachineInstance) {
        let vzInstance = instance as? VZVirtualMachineInstance
        let provider = vzInstance?.hotplugProvider
        let snapshot = VMIntrospectionSnapshot(
            vmInstanceType: String(describing: type(of: instance)),
            hotplugProviderInstalled: provider != nil,
            hotplugProviderType: provider.map { String(describing: type(of: $0)) }
        )
        lock.lock()
        latestSnapshot = snapshot
        lock.unlock()
    }

    func snapshot() -> VMIntrospectionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return latestSnapshot
    }
}

private struct IntrospectingVZVirtualMachineManager: VirtualMachineManager {
    let base: VZVirtualMachineManager
    let recorder: VMIntrospectionRecorder

    func create(config: some VMCreationConfig) throws -> any VirtualMachineInstance {
        let instance = try base.create(config: config)
        recorder.record(instance: instance)
        return instance
    }
}

private struct CCAHotplugFeasibilitySnapshot: Sendable {
    var extensionInstalled = false
    var extensionType: String?
    var vmConfigExtensionCount = 0
    var vmInstanceType: String?
    var hotplugProviderInstalled = false
    var hotplugProviderType: String?
    var providerDidCreateCalled = false
    var providerHotplugCalled = false
    var providerHotplugVirtioFSCalled = false
    var providerReleaseHotplugCalled = false
    var providerReleaseVirtioFSCalled = false
    var providerCleanupCalled = false
    var rootfsMountType: String?
    var rootfsIsBlock: Bool?
    var rootfsIsExt4: Bool?
    var rootfsSourcePath: String?
    var rootfsSourcePathRedacted = true
    var rootfsAttachStrategy: Stage9DRootfsAttachStrategy = .none
    var attachedFilesystemSource: String?
    var attachedFilesystemSourceKnown = false
    var attachedDeviceDetached: Bool?
    var failureMessage: String?
}

private final class CCAHotplugFeasibilityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let repositoryRoot: URL
    private var state = CCAHotplugFeasibilitySnapshot()

    init(repositoryRoot: URL) {
        self.repositoryRoot = repositoryRoot.standardizedFileURL
    }

    func recordConfigured(extensionType: String, vmConfigExtensionCount: Int) {
        lock.lock()
        state.extensionInstalled = true
        state.extensionType = extensionType
        state.vmConfigExtensionCount = vmConfigExtensionCount
        state.rootfsAttachStrategy = .vzUSBMassStorage
        lock.unlock()
    }

    func recordDidCreate(instance: VZVirtualMachineInstance, providerType: String) {
        lock.lock()
        state.providerDidCreateCalled = true
        state.vmInstanceType = String(describing: type(of: instance))
        state.hotplugProviderInstalled = true
        state.hotplugProviderType = providerType
        lock.unlock()
    }

    func recordHotplugRequest(_ block: Mount) {
        lock.lock()
        state.providerHotplugCalled = true
        state.rootfsMountType = block.type
        state.rootfsIsBlock = block.isBlock
        state.rootfsIsExt4 = block.type == "ext4"
        state.rootfsSourcePath = redact(path: block.source)
        state.rootfsSourcePathRedacted = state.rootfsSourcePath != block.source
        state.rootfsAttachStrategy = .vzUSBMassStorage
        lock.unlock()
    }

    func recordAttachDetached() {
        lock.lock()
        state.attachedDeviceDetached = true
        lock.unlock()
    }

    func recordAttachFailure(_ error: Error) {
        lock.lock()
        state.attachedDeviceDetached = false
        state.failureMessage = "\(error)"
        lock.unlock()
    }

    func recordProviderFailure(_ message: String) {
        lock.lock()
        state.failureMessage = message
        lock.unlock()
    }

    func recordHotplugVirtioFS() {
        lock.lock()
        state.providerHotplugVirtioFSCalled = true
        lock.unlock()
    }

    func recordReleaseHotplug() {
        lock.lock()
        state.providerReleaseHotplugCalled = true
        lock.unlock()
    }

    func recordReleaseVirtioFS() {
        lock.lock()
        state.providerReleaseVirtioFSCalled = true
        lock.unlock()
    }

    func recordCleanup() {
        lock.lock()
        state.providerCleanupCalled = true
        lock.unlock()
    }

    func snapshot() -> CCAHotplugFeasibilitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private func redact(path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let rootPath = repositoryRoot.path
        if standardized == rootPath {
            return "<repo>"
        }
        if standardized.hasPrefix(rootPath + "/") {
            return "<repo>" + String(standardized.dropFirst(rootPath.count))
        }
        return standardized
    }
}

private final class CCAHotplugFeasibilityExtension: VZInstanceExtension, @unchecked Sendable {
    private let recorder: CCAHotplugFeasibilityRecorder

    init(recorder: CCAHotplugFeasibilityRecorder) {
        self.recorder = recorder
    }

    func configureVZ(
        _ config: inout VZVirtualMachineConfiguration,
        allocator: any AddressAllocator<Character>,
        storageDeviceCount: Int,
        mountsByID: [String: [Mount]]
    ) throws {
        config.usbControllers = config.usbControllers + [VZXHCIControllerConfiguration()]
        recorder.recordConfigured(
            extensionType: String(describing: Self.self),
            vmConfigExtensionCount: 1
        )
    }

    func didCreate(_ instance: VZVirtualMachineInstance) throws {
        let provider = CCAHotplugFeasibilityProvider(instance: instance, recorder: recorder)
        instance.hotplugProvider = provider
        recorder.recordDidCreate(
            instance: instance,
            providerType: String(describing: CCAHotplugFeasibilityProvider.self)
        )
    }

    func willStop(_ instance: VZVirtualMachineInstance) async throws {
        instance.hotplugProvider?.cleanup()
    }
}

private final class CCAHotplugFeasibilityProvider: HotplugProvider, @unchecked Sendable {
    private let instance: VZVirtualMachineInstance
    private let recorder: CCAHotplugFeasibilityRecorder

    init(instance: VZVirtualMachineInstance, recorder: CCAHotplugFeasibilityRecorder) {
        self.instance = instance
        self.recorder = recorder
    }

    func hotplug(_ block: Mount, id: String) async throws -> AttachedFilesystem {
        recorder.recordHotplugRequest(block)
        do {
            try await attachAndDetachUSBMassStorage(block)
            recorder.recordProviderFailure(
                "public USB mass-storage attach succeeded, but LinuxPod requires a known guest block path before returning AttachedFilesystem"
            )
            throw CCAHotplugFeasibilityProviderError.unsupportedRootfsBlockHotplug(
                "public USB mass-storage attach succeeded, but no safe public mapping to LinuxPod's expected guest block device path was available"
            )
        } catch let error as CCAHotplugFeasibilityProviderError {
            throw error
        } catch {
            recorder.recordAttachFailure(error)
            throw CCAHotplugFeasibilityProviderError.unsupportedRootfsBlockHotplug(
                "public USB mass-storage attach failed before a LinuxPod-compatible rootfs device could be returned: \(error)"
            )
        }
    }

    func registerMounts(id: String, rootfs: AttachedFilesystem, additionalMounts: [Mount]) throws {}

    func releaseHotplug(id: String) async throws {
        recorder.recordReleaseHotplug()
    }

    func hotplugVirtioFS(_ mounts: [Mount], id: String) async throws {
        recorder.recordHotplugVirtioFS()
    }

    func releaseVirtioFS(id: String) async throws {
        recorder.recordReleaseVirtioFS()
    }

    func cleanup() {
        recorder.recordCleanup()
    }

    private func attachAndDetachUSBMassStorage(_ block: Mount) async throws {
        guard block.isBlock else {
            throw CCAHotplugFeasibilityProviderError.unsupportedRootfsBlockHotplug(
                "provider received a non-block rootfs mount"
            )
        }
        let attachment = try VZDiskImageStorageDeviceAttachment(
            url: URL(fileURLWithPath: block.source),
            readOnly: false
        )
        let configuration = VZUSBMassStorageDeviceConfiguration(attachment: attachment)
        let device = VZUSBMassStorageDevice(configuration: configuration)
        let controller = try await firstUSBController()
        let controllerBox = CCAUncheckedSendableBox(controller)
        let deviceBox = CCAUncheckedSendableBox(device)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            instance.vmQueue.async {
                controllerBox.value.attach(device: deviceBox.value) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                instance.vmQueue.async {
                    controllerBox.value.detach(device: deviceBox.value) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            recorder.recordAttachDetached()
        } catch {
            recorder.recordAttachFailure(error)
            throw error
        }
    }

    private func firstUSBController() async throws -> VZUSBController {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<VZUSBController, Error>) in
            instance.vmQueue.async {
                guard let controller = self.instance.vzVirtualMachine.usbControllers.first else {
                    continuation.resume(
                        throwing: CCAHotplugFeasibilityProviderError.unsupportedRootfsBlockHotplug(
                            "no VZUSBController was available on the running VM"
                        )
                    )
                    return
                }
                continuation.resume(returning: controller)
            }
        }
    }
}

private struct CCAUncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private enum CCAHotplugFeasibilityProviderError: Error, CustomStringConvertible {
    case unsupportedRootfsBlockHotplug(String)

    var description: String {
        switch self {
        case .unsupportedRootfsBlockHotplug(let message):
            return "unsupported: \"\(message)\""
        }
    }
}

private struct ImageRuntimeDefaults: Sendable {
    let process: LinuxProcessConfiguration
    let declaredVolumes: [String]
}

private struct Stage9DProbeContext: Sendable {
    let project: ProjectName
    let projectResource: String
    let initialService: ServicePlan
    let secondService: ServicePlan
    let initialContainerID: String
    let secondContainerID: String
    let runtimeDirectory: URL
    let initfsPath: URL
    let initfsCachePath: URL
    let rootfsPath: URL
    let rootfsCachePath: URL
}

private struct Stage9DRecordBuilder {
    let context: Stage9DProbeContext
    var status: Stage9DProbeStatus = .measured
    var probeCases: Set<Stage9DProbeCase> = []
    var extensionInstalled = false
    var extensionType: String?
    var linuxPodConfigExtensionCount = 0
    var vmConfigExtensionCount = 0
    var vmInstanceType: String?
    var hotplugProviderInstalled = false
    var hotplugProviderType: String?
    var providerDidCreateCalled = false
    var providerHotplugCalled = false
    var providerHotplugVirtioFSCalled = false
    var providerReleaseHotplugCalled = false
    var providerReleaseVirtioFSCalled = false
    var providerCleanupCalled = false
    var rootfsMountType: String?
    var rootfsIsBlock: Bool?
    var rootfsIsExt4: Bool?
    var rootfsSourcePath: String?
    var rootfsSourcePathRedacted = true
    var rootfsAttachStrategy: Stage9DRootfsAttachStrategy = .none
    var attachedFilesystemSource: String?
    var attachedFilesystemSourceKnown = false
    var preCreateRegistrationSucceeded = false
    var podCreateCalled = false
    var podCreateSucceeded = false
    var firstContainerStarted = false
    var postCreateAddContainerAttempted = false
    var postCreateAddContainerSucceeded = false
    var secondContainerStarted = false
    var realHotplugSucceeded = false
    var hotplugUnsupported = false
    var providerInstalledButAttachUnsupported = false
    var publicBlockHotplugAPIMissing = false
    var failurePhase: String?
    var failureErrorType: String?
    var failureErrorMessage: String?
    var blocker: Stage9DBlocker = .none
    var cleanupResult = "clean"
    var cleanupStateDirectoryExistsAfterCleanup = false
    var leftoverPathsCount = 0
    var attachedDeviceDetached: Bool?
    var zeroAdapterOwnedLeftovers = true

    mutating func updateProviderEvidence(from snapshot: CCAHotplugFeasibilitySnapshot?) {
        guard let snapshot else {
            return
        }
        extensionInstalled = snapshot.extensionInstalled
        extensionType = snapshot.extensionType
        vmConfigExtensionCount = snapshot.vmConfigExtensionCount
        vmInstanceType = snapshot.vmInstanceType
        hotplugProviderInstalled = snapshot.hotplugProviderInstalled
        hotplugProviderType = snapshot.hotplugProviderType
        providerDidCreateCalled = snapshot.providerDidCreateCalled
        providerHotplugCalled = snapshot.providerHotplugCalled
        providerHotplugVirtioFSCalled = snapshot.providerHotplugVirtioFSCalled
        providerReleaseHotplugCalled = snapshot.providerReleaseHotplugCalled
        providerReleaseVirtioFSCalled = snapshot.providerReleaseVirtioFSCalled
        providerCleanupCalled = snapshot.providerCleanupCalled
        attachedDeviceDetached = snapshot.attachedDeviceDetached
        if providerHotplugCalled {
            probeCases.insert(.providerReceivesHotplug)
        }
    }

    mutating func updateRootfsEvidence(from snapshot: CCAHotplugFeasibilitySnapshot?) {
        guard let snapshot else {
            return
        }
        rootfsMountType = snapshot.rootfsMountType
        rootfsIsBlock = snapshot.rootfsIsBlock
        rootfsIsExt4 = snapshot.rootfsIsExt4
        rootfsSourcePath = snapshot.rootfsSourcePath
        rootfsSourcePathRedacted = snapshot.rootfsSourcePathRedacted
        rootfsAttachStrategy = snapshot.rootfsAttachStrategy
        attachedFilesystemSource = snapshot.attachedFilesystemSource
        attachedFilesystemSourceKnown = snapshot.attachedFilesystemSourceKnown
        if let failureMessage = snapshot.failureMessage, failureErrorMessage == nil {
            failureErrorMessage = failureMessage
        }
    }

    mutating func recordFailure(_ error: Error, phase: String) {
        status = .failed
        failurePhase = phase
        failureErrorType = stage9DErrorType(error)
        failureErrorMessage = "\(error)"
        if blocker == .none {
            blocker = stage9DBlocker(error)
        }
        if blocker == .publicBlockHotplugAPIMissing || blocker == .unsupportedRootfsBlockHotplug {
            publicBlockHotplugAPIMissing = true
        }
    }

    mutating func recordCleanupFailure(_ error: Error) {
        cleanupResult = "cleanupFailed"
        zeroAdapterOwnedLeftovers = false
        if failurePhase == nil {
            recordFailure(error, phase: "cleanup")
        }
    }

    func record() -> Stage9DHotplugProviderProbeRecord {
        let orderedCases = Stage9DProbeCase.allCases.filter { probeCases.contains($0) }
        let provider = Stage9DProviderEvidence(
            extensionInstalled: extensionInstalled,
            extensionType: extensionType,
            linuxPodConfigExtensionCount: linuxPodConfigExtensionCount,
            vmConfigExtensionCount: vmConfigExtensionCount,
            vmInstanceType: vmInstanceType,
            hotplugProviderInstalled: hotplugProviderInstalled,
            hotplugProviderType: hotplugProviderType,
            providerDidCreateCalled: providerDidCreateCalled,
            providerHotplugCalled: providerHotplugCalled,
            providerHotplugVirtioFSCalled: providerHotplugVirtioFSCalled,
            providerReleaseHotplugCalled: providerReleaseHotplugCalled,
            providerReleaseVirtioFSCalled: providerReleaseVirtioFSCalled
        )
        let rootfs = Stage9DRootfsEvidence(
            rootfsMountType: rootfsMountType,
            rootfsIsBlock: rootfsIsBlock,
            rootfsIsExt4: rootfsIsExt4,
            rootfsSourcePath: rootfsSourcePath,
            rootfsSourcePathRedacted: rootfsSourcePathRedacted,
            rootfsAttachStrategy: rootfsAttachStrategy,
            attachedFilesystemSource: attachedFilesystemSource,
            attachedFilesystemSourceKnown: attachedFilesystemSourceKnown
        )
        let effectiveBlocker = realHotplugSucceeded ? .none : blocker
        let hotplug = Stage9DHotplugEvidence(
            preCreateRegistrationSucceeded: preCreateRegistrationSucceeded,
            podCreateSucceeded: podCreateSucceeded,
            firstContainerStarted: firstContainerStarted,
            postCreateAddContainerAttempted: postCreateAddContainerAttempted,
            postCreateAddContainerReachedProvider: providerHotplugCalled,
            postCreateAddContainerSucceeded: postCreateAddContainerSucceeded,
            secondContainerStarted: secondContainerStarted,
            realHotplugSucceeded: realHotplugSucceeded,
            hotplugUnsupported: hotplugUnsupported,
            providerInstalledButAttachUnsupported: providerInstalledButAttachUnsupported,
            publicBlockHotplugAPIMissing: publicBlockHotplugAPIMissing,
            failurePhase: failurePhase,
            failureErrorType: failureErrorType,
            failureErrorMessage: failureErrorMessage,
            blocker: effectiveBlocker
        )
        let cleanup = Stage9DCleanupEvidence(
            cleanupResult: cleanupResult,
            cleanupStateDirectoryExistsAfterCleanup: cleanupStateDirectoryExistsAfterCleanup,
            leftoverPathsCount: leftoverPathsCount,
            providerReleaseCalled: providerCleanupCalled,
            attachedDeviceDetached: attachedDeviceDetached,
            zeroAdapterOwnedLeftovers: zeroAdapterOwnedLeftovers
        )
        let interpretation = Stage9DInterpretationEvidence(
            productHotplugAvailable: realHotplugSucceeded && secondContainerStarted && cleanupResult == "clean",
            productShouldDependOnHotplug: false,
            nextRecommendedPath: nextRecommendedPath(realHotplugSucceeded: realHotplugSucceeded, blocker: effectiveBlocker)
        )
        return Stage9DHotplugProviderProbeRecord(
            timestamp: stage9DTimestamp(),
            status: status,
            containerizationVersion: ContainerizationLinuxPodRuntimeExecutor.containerizationVersion,
            containerizationRevision: ContainerizationLinuxPodRuntimeExecutor.containerizationRevision,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hostArchitecture: stage9DHostArchitecture(),
            probeCases: orderedCases,
            provider: provider,
            rootfs: rootfs,
            hotplug: hotplug,
            cleanup: cleanup,
            interpretation: interpretation,
            hostPortTTFBSeconds: nil,
            hostPortProbeStatus: "notMeasured",
            loadWindowSeconds: nil,
            loadWindowStatus: "notMeasured"
        )
    }

    private func nextRecommendedPath(
        realHotplugSucceeded: Bool,
        blocker: Stage9DBlocker
    ) -> Stage9DNextRecommendedPath {
        if realHotplugSucceeded {
            return .forcedWarmServiceRecreateWithHotplug
        }
        switch blocker {
        case .providerNotInstalled, .linuxPodLifecycle, .unknown:
            return .providerSpikeNeedsMoreWork
        case .providerInstalledButAttachNotImplemented,
             .publicBlockHotplugAPIMissing,
             .unsupportedRootfsBlockHotplug,
             .virtiofsOnlyProviderInsufficient,
             .upstreamRuntimeLimitation:
            return .upstreamIssue
        case .none:
            return .providerSpikeNeedsMoreWork
        }
    }
}

private func stage9DTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func stage10ATimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func stage9DHostArchitecture() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}

private func stage9DErrorType(_ error: Error) -> String {
    let description = "\(error)"
    if description.contains("unsupported") {
        return "unsupported"
    }
    if description.contains("invalidState") {
        return "invalidState"
    }
    if description.contains("invalidArgument") {
        return "invalidArgument"
    }
    if description.contains("notFound") {
        return "notFound"
    }
    return String(describing: type(of: error))
}

private func stage9DBlocker(_ error: Error) -> Stage9DBlocker {
    let description = "\(error)"
    if description.contains("no VZUSBController") {
        return .publicBlockHotplugAPIMissing
    }
    if description.contains("guest block device path") || description.contains("rootfs block") {
        return .unsupportedRootfsBlockHotplug
    }
    if description.contains("hotplug not supported") {
        return .providerNotInstalled
    }
    if description.contains("pod must be initialized") {
        return .linuxPodLifecycle
    }
    return .unknown
}

private struct Stage9BProbeContext: Sendable {
    let project: ProjectName
    let projectResource: String
    let probeCase: Stage9BHotplugProbeCase
    let initialService: ServicePlan
    let secondService: ServicePlan
    let initialContainerID: String
    let secondContainerID: String
    let runtimeDirectory: URL
    let initfsPath: URL
    let initfsCachePath: URL
    let rootfsPath: URL
    let rootfsCachePath: URL
}

private struct Stage9BRecordBuilder {
    let context: Stage9BProbeContext
    var podObjectCreated = false
    var podCreateCalled = false
    var podCreateSucceeded = false
    var podObjectPhase: String?
    var podCreatedStateKnown = true
    var podActuallyRunning: Bool? = false
    var initialContainerRegisteredBeforeCreate = false
    var initialContainerStarted = false
    var postCreateAddContainerAttempted = false
    var postCreateAddContainerSucceeded = false
    var addContainerPhase: Stage9BAddContainerPhase = .unknown
    var hotplugAttempted = false
    var hotplugSucceeded = false
    var hotplugUnsupported = false
    var duplicateContainerDetected = false
    var failurePhase: String?
    var failureErrorType: String?
    var failureErrorMessage: String?
    var mutationBeforeFailure: EvidenceTruthValue = .false
    var cleanupResult = "clean"
    var cleanupStateDirectoryExistsAfterCleanup = false
    var leftoverPathsCount = 0

    mutating func recordFailure(_ error: Error, phase: String) {
        failurePhase = phase
        failureErrorType = stage9BErrorType(error)
        failureErrorMessage = "\(error)"
        if podCreateSucceeded || podActuallyRunning == true {
            mutationBeforeFailure = .true
        }
    }

    mutating func recordCleanupFailure(_ error: Error) {
        cleanupResult = "cleanupFailed"
        if failurePhase == nil {
            failurePhase = "cleanup"
            failureErrorType = stage9BErrorType(error)
            failureErrorMessage = "\(error)"
        }
    }

    func record() -> Stage9BHotplugProbeRecord {
        Stage9BHotplugProbeRecord(
            timestamp: stage9BTimestamp(),
            project: context.projectResource,
            probeCase: context.probeCase,
            podObjectCreated: podObjectCreated,
            podCreateCalled: podCreateCalled,
            podCreateSucceeded: podCreateSucceeded,
            podObjectPhase: podObjectPhase,
            podCreatedStateKnown: podCreatedStateKnown,
            podActuallyRunning: podActuallyRunning,
            initialContainerRegisteredBeforeCreate: initialContainerRegisteredBeforeCreate,
            initialContainerStarted: initialContainerStarted,
            postCreateAddContainerAttempted: postCreateAddContainerAttempted,
            postCreateAddContainerSucceeded: postCreateAddContainerSucceeded,
            addContainerPhase: addContainerPhase,
            hotplugAttempted: hotplugAttempted,
            hotplugSucceeded: hotplugSucceeded,
            hotplugUnsupported: hotplugUnsupported,
            duplicateContainerDetected: duplicateContainerDetected,
            failurePhase: failurePhase,
            failureErrorType: failureErrorType,
            failureErrorMessage: failureErrorMessage,
            mutationBeforeFailure: mutationBeforeFailure,
            cleanupResult: cleanupResult,
            cleanupStateDirectoryExistsAfterCleanup: cleanupStateDirectoryExistsAfterCleanup,
            leftoverPathsCount: leftoverPathsCount,
            runtimePackageVersion: ContainerizationLinuxPodRuntimeExecutor.containerizationVersion,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            containerizationVersion: ContainerizationLinuxPodRuntimeExecutor.containerizationVersion
        )
    }
}

private func stage9BTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func stage9BErrorType(_ error: Error) -> String {
    let description = "\(error)"
    if description.contains("invalidState") {
        return "invalidState"
    }
    if description.contains("unsupported") {
        return "unsupported"
    }
    if description.contains("invalidArgument") {
        return "invalidArgument"
    }
    if description.contains("notFound") {
        return "notFound"
    }
    return String(describing: type(of: error))
}

private final class LinuxPodLogWriter: Writer, @unchecked Sendable {
    enum Stream {
        case stdout
        case stderr
    }

    private let capture: RuntimeLogCapture
    private let stream: Stream
    private let fileHandle: FileHandle?

    init(capture: RuntimeLogCapture, stream: Stream, fileURL: URL? = nil) throws {
        self.capture = capture
        self.stream = stream
        if let fileURL {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
        } else {
            self.fileHandle = nil
        }
    }

    func write(_ data: Data) throws {
        switch stream {
        case .stdout:
            capture.appendStdout(data)
        case .stderr:
            capture.appendStderr(data)
        }
        try fileHandle?.write(contentsOf: data)
    }

    func close() throws {
        try fileHandle?.close()
    }
}
