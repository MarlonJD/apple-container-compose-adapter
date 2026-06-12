// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import Containerization
import ContainerizationEXT4
import Foundation
import Security
import SystemPackage

public actor ContainerizationLinuxPodRuntimeExecutor: LinuxPodRuntimeExecuting {
    public static let containerizationVersion = "0.26.5"
    public static let defaultInitImageReference = "ghcr.io/apple/containerization/vminit:0.26.5"

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
            try await prepareImageRootfs(event)
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

    private func createProjectRuntime(_ event: LinuxPodRuntimeEvent) async throws {
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
        let vmm = VZVirtualMachineManager(kernel: kernelConfig, initialFilesystem: initfs)
        let pod = try LinuxPod(event.project, vmm: vmm) { config in
            config.cpus = podCPUs
            config.memoryInBytes = podMemoryBytes
            config.hostname = event.project
            config.hosts = hosts(from: event)
            config.bootLog = .file(
                path: runtimeDirectory.appendingPathComponent("boot.log"),
                append: false
            )
        }
        states[event.project] = ProjectRuntime(
            runtimeDirectory: runtimeDirectory,
            imageStore: imageStore,
            pod: pod
        )
    }

    private func prepareImageRootfs(_ event: LinuxPodRuntimeEvent) async throws {
        var state = try state(for: event)
        guard let image = event.resourceName, !image.isEmpty else {
            throw unsupported(event, reason: "missing image reference")
        }
        guard let rootfsValue = event.metadata["rootfs"], !rootfsValue.isEmpty else {
            throw unsupported(event, reason: "missing rootfs path")
        }
        let rootfsURL = URL(fileURLWithPath: rootfsValue)
        let rootfsCacheURL = event.metadata["rootfsCache"].map { URL(fileURLWithPath: $0) }
        try FileManager.default.createDirectory(
            at: rootfsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let imageValue = try await state.imageStore.get(reference: image, pull: true)
        if let imageConfig = try await imageValue.config(for: SystemPlatform.linuxArm.ociPlatform()).config {
            state.defaultsByImage[image] = ImageRuntimeDefaults(
                process: LinuxProcessConfiguration(from: imageConfig),
                declaredVolumes: try await declaredVolumes(for: imageValue)
            )
        }
        if let rootfsCacheURL {
            try ensureAdapterOwnedCachePath(rootfsCacheURL)
            try FileManager.default.createDirectory(
                at: rootfsCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: rootfsCacheURL.path) {
                let unpacker = EXT4Unpacker(blockSizeInBytes: defaultRootfsSizeBytes)
                _ = try await unpacker.unpack(
                    imageValue,
                    for: SystemPlatform.linuxArm.ociPlatform(),
                    at: rootfsCacheURL
                )
            }
            try copyReplacing(source: rootfsCacheURL, destination: rootfsURL)
        } else if !FileManager.default.fileExists(atPath: rootfsURL.path) {
            let unpacker = EXT4Unpacker(blockSizeInBytes: defaultRootfsSizeBytes)
            _ = try await unpacker.unpack(
                imageValue,
                for: SystemPlatform.linuxArm.ociPlatform(),
                at: rootfsURL
            )
        }
        state.rootfsPathByImage[image] = rootfsURL
        states[event.project] = state
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

    // Each container gets a private clone of the prepared base image rootfs.
    // Attaching one ext4 block image read-write to multiple containers would
    // corrupt the filesystem; APFS clones keep the copies cheap.
    private func containerRootfs(
        for service: ServicePlan,
        containerID: String,
        in state: ProjectRuntime
    ) throws -> Mount {
        guard let baseURL = state.rootfsPathByImage[service.image] else {
            throw RuntimeBackendError.runtimeUnavailable(
                "LinuxPod rootfs for \(service.image) was not prepared before adding \(service.name)."
            )
        }
        let containersDirectory = state.runtimeDirectory
            .appendingPathComponent("rootfs", isDirectory: true)
            .appendingPathComponent("containers", isDirectory: true)
        try FileManager.default.createDirectory(at: containersDirectory, withIntermediateDirectories: true)
        let cloneURL = containersDirectory.appendingPathComponent("\(containerID).ext4")
        if FileManager.default.fileExists(atPath: cloneURL.path) {
            try FileManager.default.removeItem(at: cloneURL)
        }
        try FileManager.default.copyItem(at: baseURL, to: cloneURL)
        return Mount.block(
            format: "ext4",
            source: cloneURL.path,
            destination: "/"
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
        let rootfs = try containerRootfs(for: service, containerID: containerID, in: state)

        let mounts = try containerMounts(for: service, in: state)
        let logCapture = RuntimeLogCapture()
        var process = try processConfiguration(for: service, in: state)
        var metadata = containerMetadata(for: service, process: process, state: state)
        let logsDirectory = state.runtimeDirectory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let stdoutLog = logsDirectory.appendingPathComponent("\(service.name).stdout.log")
        let stderrLog = logsDirectory.appendingPathComponent("\(service.name).stderr.log")
        process.stdout = try LinuxPodLogWriter(capture: logCapture, stream: .stdout, fileURL: stdoutLog)
        process.stderr = try LinuxPodLogWriter(capture: logCapture, stream: .stderr, fileURL: stderrLog)
        metadata["logStdout"] = "logs/\(service.name).stdout.log"
        metadata["logStderr"] = "logs/\(service.name).stderr.log"
        let resolvedProcess = process
        try await state.pod.addContainer(containerID, rootfs: rootfs) { config in
            config.process = resolvedProcess
            config.mounts += mounts
            config.hostname = service.name
        }
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
        if !state.podCreated {
            try await state.pod.create()
            state.podCreated = true
        }
        try await state.pod.startContainer(containerID)
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
        if !state.podCreated {
            try await state.pod.create()
            state.podCreated = true
        }
        try await state.pod.startContainer(containerID)
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
}

private struct ProjectRuntime: Sendable {
    let runtimeDirectory: URL
    let imageStore: ImageStore
    let pod: LinuxPod
    var podCreated = false
    var rootfsPathByImage: [String: URL] = [:]
    var defaultsByImage: [String: ImageRuntimeDefaults] = [:]
    var volumePaths: [String: URL] = [:]
    var containers: Set<String> = []
    var containerByService: [String: String] = [:]
    var completedJobs: Set<String> = []
    var logCaptureByService: [String: RuntimeLogCapture] = [:]
}

private struct ImageRuntimeDefaults: Sendable {
    let process: LinuxProcessConfiguration
    let declaredVolumes: [String]
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
