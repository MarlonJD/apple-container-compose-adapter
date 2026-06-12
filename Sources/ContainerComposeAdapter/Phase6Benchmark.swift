// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum Phase6BenchmarkSchema {
    public static let version = "container-compose-adapter/linuxpod-phase6-benchmark/v1"
    public static let iterationRecordType = "linuxpod-phase6-benchmark-iteration"
    public static let summaryRecordType = "linuxpod-phase6-benchmark-summary"
}

public enum BenchmarkLifecycle: String, Codable, Equatable, Sendable {
    case cold
    case imageStoreSeededFreshRuntime = "image-store-seeded-fresh-runtime"
    case persistentWarmProjectRuntime = "persistent-warm-project-runtime"
    /// Legacy value kept so older Stage 4/6 evidence can still decode.
    case warm
}

public enum BenchmarkLifecycleMode: String, Codable, Equatable, CaseIterable, Sendable {
    case coldRuntime = "cold-runtime"
    case imageStoreSeededFreshRuntime = "image-store-seeded-fresh-runtime"
    case rootfsCacheHitRuntime = "rootfs-cache-hit-runtime"
    case initfsCacheHitRuntime = "initfs-cache-hit-runtime"
    case warmPreservedVolume = "warm-preserved-volume"
    case persistentPodHotplug = "persistent-pod-hotplug"
    case allWarmProjectRuntime = "all-warm-project-runtime"

    public var id: String {
        switch self {
        case .coldRuntime:
            return "A"
        case .imageStoreSeededFreshRuntime:
            return "B"
        case .rootfsCacheHitRuntime:
            return "C"
        case .initfsCacheHitRuntime:
            return "D"
        case .warmPreservedVolume:
            return "E"
        case .persistentPodHotplug:
            return "F"
        case .allWarmProjectRuntime:
            return "G"
        }
    }

    public var legacyLifecycle: BenchmarkLifecycle {
        switch self {
        case .coldRuntime:
            return .cold
        case .imageStoreSeededFreshRuntime:
            return .imageStoreSeededFreshRuntime
        case .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime,
             .warmPreservedVolume,
             .persistentPodHotplug,
             .allWarmProjectRuntime:
            return .persistentWarmProjectRuntime
        }
    }

    public var targetName: String {
        switch self {
        case .coldRuntime:
            return "LinuxPod cold runtime"
        case .imageStoreSeededFreshRuntime:
            return "LinuxPod image-store-seeded fresh runtime"
        case .rootfsCacheHitRuntime:
            return "LinuxPod rootfs-cache hit runtime"
        case .initfsCacheHitRuntime:
            return "LinuxPod initfs-cache hit runtime"
        case .warmPreservedVolume:
            return "LinuxPod warm preserved volume runtime"
        case .persistentPodHotplug:
            return "LinuxPod persistent pod hotplug runtime"
        case .allWarmProjectRuntime:
            return "LinuxPod all-warm project runtime"
        }
    }

    public static func compatibilityDefault(for lifecycle: BenchmarkLifecycle) -> BenchmarkLifecycleMode {
        switch lifecycle {
        case .cold:
            return .coldRuntime
        case .imageStoreSeededFreshRuntime:
            return .imageStoreSeededFreshRuntime
        case .persistentWarmProjectRuntime:
            return .allWarmProjectRuntime
        case .warm:
            return .allWarmProjectRuntime
        }
    }

    public static func classify(
        lifecycle: BenchmarkLifecycle,
        seedImageStoreCopied: Bool,
        rootfsCacheStatus: BenchmarkCacheStatus,
        initfsCacheStatus: BenchmarkCacheStatus,
        volumeExistedBeforeRun: Bool,
        podExistedBeforeRun: Bool
    ) -> BenchmarkLifecycleMode {
        let rootfsHit = rootfsCacheStatus.isHitLike
        let initfsHit = initfsCacheStatus.isHitLike

        if rootfsHit && initfsHit && volumeExistedBeforeRun && podExistedBeforeRun {
            return .allWarmProjectRuntime
        }
        if podExistedBeforeRun {
            return .persistentPodHotplug
        }
        if volumeExistedBeforeRun {
            return .warmPreservedVolume
        }
        if initfsHit {
            return .initfsCacheHitRuntime
        }
        if rootfsHit {
            return .rootfsCacheHitRuntime
        }
        if seedImageStoreCopied || lifecycle == .imageStoreSeededFreshRuntime {
            return .imageStoreSeededFreshRuntime
        }
        return .coldRuntime
    }
}

public enum BenchmarkCacheStatus: String, Codable, Equatable, Sendable {
    case hit
    case miss
    case unknown
    case blocked
    case unverifiedSeedRequested
    case verifiedHit
    case partialHit
    case invalid

    public var isHitLike: Bool {
        self == .hit || self == .verifiedHit
    }
}

public struct BenchmarkRunMetadata: Codable, Equatable, Sendable {
    public let runtime: RuntimeKind
    public let targetName: String
    public let coldOrWarm: String
    public let runtimeVersion: String
    public let containerizationVersion: String?
    public let appleContainerCLIVersion: String?
    public let macOSVersion: String
    public let hostArchitecture: String
    public let lifecycle: BenchmarkLifecycle
    public let lifecycleMode: String
    public let lifecycleModeID: String
    public let seedImageStoreRequested: Bool
    public let seedImageStoreCopied: Bool
    public let seedImageStoreValidated: Bool
    public let seedImageStorePath: String?
    public let projectRuntimeExistedBeforeRun: Bool
    public let projectRuntimeDirectoryExistedBeforeSeed: Bool
    public let projectRuntimeDirectoryExistedBeforeRun: Bool
    public let podExistedBeforeRun: Bool
    public let imageCacheStatus: BenchmarkCacheStatus
    public let rootfsCacheStatus: BenchmarkCacheStatus
    public let initfsCacheStatus: BenchmarkCacheStatus
    public let volumeExistedBeforeRun: Bool
    public let hostPortPublished: Bool?
    public let hostPortTTFBSeconds: Double?
    public let hostPortProbeStatus: String
    public let hostPortPublishingNotImplemented: Bool
    public let loadWindowSeconds: Double?
    public let loadWindowStatus: String
    public let completedRequests: Int?
    public let requestFailureCount: Int?

    private enum CodingKeys: String, CodingKey {
        case runtime
        case targetName = "target_name"
        case coldOrWarm = "cold_or_warm"
        case runtimeVersion
        case containerizationVersion
        case appleContainerCLIVersion
        case macOSVersion
        case hostArchitecture
        case lifecycle
        case lifecycleMode
        case lifecycleModeID
        case seedImageStoreRequested
        case seedImageStoreCopied
        case seedImageStoreValidated
        case seedImageStorePath
        case projectRuntimeExistedBeforeRun
        case projectRuntimeDirectoryExistedBeforeSeed
        case projectRuntimeDirectoryExistedBeforeRun
        case podExistedBeforeRun
        case imageCacheStatus
        case rootfsCacheStatus
        case initfsCacheStatus
        case volumeExistedBeforeRun
        case hostPortPublished
        case hostPortTTFBSeconds
        case hostPortProbeStatus
        case hostPortPublishingNotImplemented
        case loadWindowSeconds
        case loadWindowStatus
        case completedRequests
        case requestFailureCount
    }

    public init(
        runtime: RuntimeKind,
        targetName: String? = nil,
        runtimeVersion: String,
        containerizationVersion: String? = nil,
        appleContainerCLIVersion: String? = nil,
        macOSVersion: String,
        hostArchitecture: String,
        lifecycle: BenchmarkLifecycle,
        lifecycleMode: BenchmarkLifecycleMode? = nil,
        seedImageStoreRequested: Bool = false,
        seedImageStoreCopied: Bool = false,
        seedImageStoreValidated: Bool = false,
        seedImageStorePath: String? = nil,
        projectRuntimeExistedBeforeRun: Bool? = nil,
        projectRuntimeDirectoryExistedBeforeSeed: Bool = false,
        projectRuntimeDirectoryExistedBeforeRun: Bool? = nil,
        podExistedBeforeRun: Bool = false,
        imageCacheStatus: BenchmarkCacheStatus,
        rootfsCacheStatus: BenchmarkCacheStatus,
        initfsCacheStatus: BenchmarkCacheStatus,
        volumeExistedBeforeRun: Bool,
        hostPortPublished: Bool? = nil,
        hostPortTTFBSeconds: Double? = nil,
        hostPortProbeStatus: String = "notMeasured",
        hostPortPublishingNotImplemented: Bool = false,
        loadWindowSeconds: Double? = nil,
        loadWindowStatus: String = "notMeasured",
        completedRequests: Int? = nil,
        requestFailureCount: Int? = nil
    ) {
        self.runtime = runtime
        self.targetName = targetName ?? runtime.rawValue
        self.coldOrWarm = lifecycle.rawValue
        self.runtimeVersion = runtimeVersion
        self.containerizationVersion = containerizationVersion
        self.appleContainerCLIVersion = appleContainerCLIVersion
        self.macOSVersion = macOSVersion
        self.hostArchitecture = hostArchitecture
        self.lifecycle = lifecycle
        let resolvedMode = lifecycleMode ?? BenchmarkLifecycleMode.classify(
            lifecycle: lifecycle,
            seedImageStoreCopied: seedImageStoreCopied,
            rootfsCacheStatus: rootfsCacheStatus,
            initfsCacheStatus: initfsCacheStatus,
            volumeExistedBeforeRun: volumeExistedBeforeRun,
            podExistedBeforeRun: podExistedBeforeRun
        )
        self.lifecycleMode = resolvedMode.rawValue
        self.lifecycleModeID = resolvedMode.id
        self.seedImageStoreRequested = seedImageStoreRequested
        self.seedImageStoreCopied = seedImageStoreCopied
        self.seedImageStoreValidated = seedImageStoreValidated
        self.seedImageStorePath = seedImageStorePath
        let directoryBeforeRun = projectRuntimeDirectoryExistedBeforeRun
            ?? projectRuntimeExistedBeforeRun
            ?? false
        self.projectRuntimeExistedBeforeRun = projectRuntimeExistedBeforeRun ?? directoryBeforeRun
        self.projectRuntimeDirectoryExistedBeforeSeed = projectRuntimeDirectoryExistedBeforeSeed
        self.projectRuntimeDirectoryExistedBeforeRun = directoryBeforeRun
        self.podExistedBeforeRun = podExistedBeforeRun
        self.imageCacheStatus = imageCacheStatus
        self.rootfsCacheStatus = rootfsCacheStatus
        self.initfsCacheStatus = initfsCacheStatus
        self.volumeExistedBeforeRun = volumeExistedBeforeRun
        self.hostPortPublished = hostPortPublished
        self.hostPortTTFBSeconds = hostPortTTFBSeconds
        self.hostPortProbeStatus = hostPortProbeStatus
        self.hostPortPublishingNotImplemented = hostPortPublishingNotImplemented
        self.loadWindowSeconds = loadWindowSeconds
        self.loadWindowStatus = loadWindowStatus
        self.completedRequests = completedRequests
        self.requestFailureCount = requestFailureCount
    }
}

public enum Phase6BenchmarkIterationStatus: String, Codable, Equatable, Sendable {
    case measured
    case failed
}

public enum Phase6HostPhysicalMemoryStatus: String, Codable, Equatable, Sendable {
    case blocked
}

public struct Phase6BenchmarkDurations: Codable, Equatable, Sendable {
    public let up: Double?
    public let status: Double?
    public let logs: Double?
    public let cleanup: Double?
    public let rootfsPrep: Double?
    public let initfsPrep: Double?
    public let volumeCreateOrReuse: Double?
    public let podCreateOrReuse: Double?
    public let containerStart: Double?
    public let healthcheck: Double?

    public init(
        up: Double?,
        status: Double?,
        logs: Double?,
        cleanup: Double?,
        rootfsPrep: Double? = nil,
        initfsPrep: Double? = nil,
        volumeCreateOrReuse: Double? = nil,
        podCreateOrReuse: Double? = nil,
        containerStart: Double? = nil,
        healthcheck: Double? = nil
    ) {
        self.up = up
        self.status = status
        self.logs = logs
        self.cleanup = cleanup
        self.rootfsPrep = rootfsPrep
        self.initfsPrep = initfsPrep
        self.volumeCreateOrReuse = volumeCreateOrReuse
        self.podCreateOrReuse = podCreateOrReuse
        self.containerStart = containerStart
        self.healthcheck = healthcheck
    }
}

public struct Phase6BenchmarkIterationRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let runLabel: String
    public let iteration: Int
    public let environment: BenchmarkRunMetadata?
    public let status: Phase6BenchmarkIterationStatus
    public let durationsSeconds: Phase6BenchmarkDurations
    public let guest: HostFootprintGuestStats?
    public let hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus
    public let actionCount: Int
    public let cleanupStateDirectoryExistsAfterCleanup: Bool
    public let healthcheckAttempts: Int?
    public let dataFootprintBytes: UInt64?
    public let cleanupResult: String
    public let failure: String?

    public init(
        timestamp: String,
        project: String,
        runLabel: String,
        iteration: Int,
        environment: BenchmarkRunMetadata? = nil,
        status: Phase6BenchmarkIterationStatus,
        durationsSeconds: Phase6BenchmarkDurations,
        guest: HostFootprintGuestStats?,
        hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus,
        actionCount: Int,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        healthcheckAttempts: Int? = nil,
        dataFootprintBytes: UInt64? = nil,
        cleanupResult: String? = nil,
        failure: String?
    ) {
        self.schemaVersion = Phase6BenchmarkSchema.version
        self.recordType = Phase6BenchmarkSchema.iterationRecordType
        self.timestamp = timestamp
        self.project = project
        self.runLabel = runLabel
        self.iteration = iteration
        self.environment = environment
        self.status = status
        self.durationsSeconds = durationsSeconds
        self.guest = guest
        self.hostPhysicalMemoryStatus = hostPhysicalMemoryStatus
        self.actionCount = actionCount
        self.cleanupStateDirectoryExistsAfterCleanup = cleanupStateDirectoryExistsAfterCleanup
        self.healthcheckAttempts = healthcheckAttempts
        self.dataFootprintBytes = dataFootprintBytes
        self.cleanupResult = cleanupResult ?? (cleanupStateDirectoryExistsAfterCleanup ? "leftovers" : "clean")
        self.failure = failure
    }
}

public struct Phase6BenchmarkSummaryRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let projectPrefix: String
    public let runLabel: String
    public let environment: BenchmarkRunMetadata?
    public let requestedIterations: Int
    public let measuredIterations: Int
    public let failureCount: Int
    public let hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus
    public let guestCgroupMemoryCurrentP50Bytes: UInt64?
    public let guestCgroupMemoryLimitBytes: UInt64?
    public let processCountP50: UInt64?
    public let cpuUsageUsecP50: UInt64?
    public let blockReadP50Bytes: UInt64?
    public let blockWriteP50Bytes: UInt64?
    public let upDurationP50Seconds: Double?
    public let statusDurationP50Seconds: Double?
    public let logsDurationP50Seconds: Double?
    public let cleanupDurationP50Seconds: Double?
    public let rootfsPrepDurationP50Seconds: Double?
    public let initfsPrepDurationP50Seconds: Double?
    public let volumeCreateOrReuseDurationP50Seconds: Double?
    public let podCreateOrReuseDurationP50Seconds: Double?
    public let containerStartDurationP50Seconds: Double?
    public let healthcheckDurationP50Seconds: Double?
    public let healthcheckAttemptsP50: Int?
    public let lifecycleMode: String?
    public let lifecycleModeID: String?
    public let statusTimingMeaning: String
    public let logsTimingMeaning: String
    public let hostPortPublished: Bool?
    public let hostPortTTFBSeconds: Double?
    public let hostPortProbeStatus: String
    public let loadWindowSeconds: Double?
    public let loadWindowStatus: String
    public let completedRequests: Int?
    public let requestFailureCount: Int?
    public let processRSSP50Bytes: UInt64?
    public let dataFootprintP50Bytes: UInt64?
    public let cleanupResult: String?

    public init(
        timestamp: String,
        projectPrefix: String,
        runLabel: String,
        requestedIterations: Int,
        records: [Phase6BenchmarkIterationRecord]
    ) {
        let measured = records.filter { $0.status == .measured }
        self.schemaVersion = Phase6BenchmarkSchema.version
        self.recordType = Phase6BenchmarkSchema.summaryRecordType
        self.timestamp = timestamp
        self.projectPrefix = projectPrefix
        self.runLabel = runLabel
        self.environment = records.compactMap(\.environment).first
        self.requestedIterations = requestedIterations
        self.measuredIterations = measured.count
        self.failureCount = records.filter { $0.status == .failed }.count
        self.hostPhysicalMemoryStatus = .blocked
        self.guestCgroupMemoryCurrentP50Bytes = p50(measured.compactMap { $0.guest?.cgroupMemoryCurrentBytes })
        self.guestCgroupMemoryLimitBytes = p50(measured.compactMap { $0.guest?.cgroupMemoryLimitBytes })
        self.processCountP50 = p50(measured.compactMap { $0.guest?.processCount })
        self.cpuUsageUsecP50 = p50(measured.compactMap { $0.guest?.cpuUsageUsec })
        self.blockReadP50Bytes = p50(measured.compactMap { $0.guest?.blockReadBytes })
        self.blockWriteP50Bytes = p50(measured.compactMap { $0.guest?.blockWriteBytes })
        self.upDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.up))
        self.statusDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.status))
        self.logsDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.logs))
        self.cleanupDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.cleanup))
        self.rootfsPrepDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.rootfsPrep))
        self.initfsPrepDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.initfsPrep))
        self.volumeCreateOrReuseDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.volumeCreateOrReuse))
        self.podCreateOrReuseDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.podCreateOrReuse))
        self.containerStartDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.containerStart))
        self.healthcheckDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.healthcheck))
        self.healthcheckAttemptsP50 = p50(measured.compactMap(\.healthcheckAttempts))
        self.lifecycleMode = self.environment?.lifecycleMode
        self.lifecycleModeID = self.environment?.lifecycleModeID
        self.statusTimingMeaning = "control-plane-local-state"
        self.logsTimingMeaning = "control-plane-no-op"
        self.hostPortPublished = self.environment?.hostPortPublished
        self.hostPortTTFBSeconds = self.environment?.hostPortTTFBSeconds
        self.hostPortProbeStatus = self.environment?.hostPortProbeStatus ?? "notMeasured"
        self.loadWindowSeconds = self.environment?.loadWindowSeconds
        self.loadWindowStatus = self.environment?.loadWindowStatus ?? "notMeasured"
        self.completedRequests = self.environment?.completedRequests
        self.requestFailureCount = self.environment?.requestFailureCount
        self.processRSSP50Bytes = p50(measured.compactMap { $0.guest?.processRSSBytes })
        self.dataFootprintP50Bytes = p50(measured.compactMap(\.dataFootprintBytes))
        self.cleanupResult = measured.first?.cleanupResult
    }
}

public struct Stage8BenchmarkEvidenceValidator: Sendable {
    public init() {}

    public func validate(records: [Phase6BenchmarkIterationRecord]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        if records.isEmpty {
            diagnostics.append(blocking("stage8-evidence-empty", "Stage 8 benchmark evidence must include iteration records."))
        }
        for record in records {
            validate(record, diagnostics: &diagnostics)
        }
        return diagnostics
    }

    public func validate(evidenceURL: URL) throws -> [Diagnostic] {
        let records: [Phase6BenchmarkIterationRecord] = try readStage8IterationRecords(evidenceURL)
        return validate(records: records)
    }

    private func validate(
        _ record: Phase6BenchmarkIterationRecord,
        diagnostics: inout [Diagnostic]
    ) {
        guard let environment = record.environment else {
            diagnostics.append(blocking("stage8-environment-missing", "Stage 8 records must include runtime metadata."))
            return
        }

        if environment.lifecycleModeID.isEmpty || !Self.validLifecycleModeIDs.contains(environment.lifecycleModeID) {
            diagnostics.append(blocking("stage8-lifecycle-mode-id-missing", "Stage 8 records must include an A/B/C/D/E/F/G lifecycle mode id."))
        }
        guard let mode = BenchmarkLifecycleMode(rawValue: environment.lifecycleMode) else {
            diagnostics.append(blocking("stage8-lifecycle-mode-missing", "Stage 8 records must include a recognized lifecycle mode."))
            return
        }
        if environment.lifecycleModeID != mode.id {
            diagnostics.append(blocking("stage8-lifecycle-mode-id-mismatch", "Stage 8 lifecycle mode id must match the lifecycle mode."))
        }
        let classified = BenchmarkLifecycleMode.classify(
            lifecycle: environment.lifecycle,
            seedImageStoreCopied: environment.seedImageStoreCopied,
            rootfsCacheStatus: environment.rootfsCacheStatus,
            initfsCacheStatus: environment.initfsCacheStatus,
            volumeExistedBeforeRun: environment.volumeExistedBeforeRun,
            podExistedBeforeRun: environment.podExistedBeforeRun
        )
        if classified != mode {
            diagnostics.append(blocking("stage8-lifecycle-mode-cache-mismatch", "Stage 8 lifecycle mode does not match cache/reuse metadata."))
        }
        if environment.hostPortTTFBSeconds == nil && environment.hostPortProbeStatus != "notMeasured" {
            diagnostics.append(blocking("stage8-host-port-not-measured-missing", "Missing host-port TTFB must be marked notMeasured."))
        }
        if environment.loadWindowSeconds == nil
            && environment.completedRequests == nil
            && environment.requestFailureCount == nil
            && environment.loadWindowStatus != "notMeasured" {
            diagnostics.append(blocking("stage8-load-window-not-measured-missing", "Missing load-window metrics must be marked notMeasured."))
        }

        validateMetrics(record, diagnostics: &diagnostics)
    }

    private func validateMetrics(
        _ record: Phase6BenchmarkIterationRecord,
        diagnostics: inout [Diagnostic]
    ) {
        if record.durationsSeconds.up == nil {
            diagnostics.append(blocking("stage8-startup-duration-missing", "Stage 8 records must preserve startup/readiness duration."))
        }
        if record.durationsSeconds.rootfsPrep == nil {
            diagnostics.append(blocking("stage8-rootfs-prep-duration-missing", "Stage 8 records must preserve rootfs prep duration."))
        }
        if record.durationsSeconds.initfsPrep == nil {
            diagnostics.append(blocking("stage8-initfs-prep-duration-missing", "Stage 8 records must preserve initfs prep duration."))
        }
        if record.durationsSeconds.volumeCreateOrReuse == nil {
            diagnostics.append(blocking("stage8-volume-duration-missing", "Stage 8 records must preserve volume create/reuse duration."))
        }
        if record.durationsSeconds.podCreateOrReuse == nil {
            diagnostics.append(blocking("stage8-pod-duration-missing", "Stage 8 records must preserve pod create/reuse duration."))
        }
        if record.durationsSeconds.containerStart == nil {
            diagnostics.append(blocking("stage8-container-start-duration-missing", "Stage 8 records must preserve container start duration."))
        }
        if record.durationsSeconds.healthcheck == nil {
            diagnostics.append(blocking("stage8-healthcheck-duration-missing", "Stage 8 records must preserve healthcheck duration."))
        }
        if record.healthcheckAttempts == nil {
            diagnostics.append(blocking("stage8-healthcheck-attempts-missing", "Stage 8 records must preserve healthcheck attempts."))
        }
        if let guest = record.guest {
            if guest.processRSSBytes == nil {
                diagnostics.append(blocking("stage8-process-rss-missing", "Stage 8 records must preserve process RSS when measured."))
            }
        } else {
            diagnostics.append(blocking("stage8-guest-metrics-missing", "Stage 8 records must preserve cgroup and block I/O metrics."))
            diagnostics.append(blocking("stage8-process-rss-missing", "Stage 8 records must preserve process RSS when measured."))
        }
        if record.dataFootprintBytes == nil {
            diagnostics.append(blocking("stage8-data-footprint-missing", "Stage 8 records must preserve data footprint."))
        }
        if record.cleanupResult != "clean" || record.cleanupStateDirectoryExistsAfterCleanup {
            diagnostics.append(blocking("stage8-cleanup-leftovers", "Stage 8 cleanup proof must show no adapter-owned project runtime leftovers."))
        }
    }

    private static let validLifecycleModeIDs = Set(BenchmarkLifecycleMode.allCases.map(\.id))
}

private func blocking(_ code: String, _ message: String) -> Diagnostic {
    Diagnostic(severity: .blocking, code: code, message: message)
}

private func readStage8IterationRecords(_ url: URL) throws -> [Phase6BenchmarkIterationRecord] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    var records: [Phase6BenchmarkIterationRecord] = []
    for line in contents.split(separator: "\n") {
        let data = Data(line.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["recordType"] as? String == Phase6BenchmarkSchema.iterationRecordType else {
            continue
        }
        records.append(try decoder.decode(Phase6BenchmarkIterationRecord.self, from: data))
    }
    return records
}

private func p50<T: Comparable>(_ values: [T]) -> T? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}
