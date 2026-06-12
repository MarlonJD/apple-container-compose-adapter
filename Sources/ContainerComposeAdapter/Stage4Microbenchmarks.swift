// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum Stage4MicrobenchmarkSchema {
    public static let version = "container-compose-adapter/linuxpod-stage4-microbenchmark/v1"
    public static let planRecordType = "linuxpod-stage4-microbenchmark-plan"
    public static let operationRecordType = "linuxpod-stage4-microbenchmark-operation"
    public static let measurementRecordType = "linuxpod-stage4-microbenchmark-measurement"
}

public enum Stage4MicrobenchmarkKind: String, Codable, Equatable, Hashable, Sendable {
    case rootfsUnpack = "rootfs-unpack"
    case rootfsCopy = "rootfs-copy"
    case apfsClone = "apfs-clone"
    case namedVolumeFresh = "named-volume-fresh"
    case namedVolumeWarm = "named-volume-warm"
    case healthcheckExec = "healthcheck-exec"
}

public enum Stage4MicrobenchmarkCacheKeyKind: String, Codable, Equatable, Sendable {
    case imageReferencePendingDigest = "image-reference-pending-digest"
    case notApplicable = "not-applicable"
}

public enum Stage4HostPhysicalMemoryStatus: String, Codable, Equatable, Sendable {
    case blocked
}

public enum Stage4MicrobenchmarkMeasurementStatus: String, Codable, Equatable, Sendable {
    case measured
    case failed
}

public struct Stage4MicrobenchmarkRuntimeContext: Codable, Equatable, Sendable {
    public let containerizationVersion: String
    public let rootfsFormatVersion: String
    public let vminitImageReference: String
    public let vminitImageDigest: String
    public let kernelPath: String
    public let kernelVersion: String
    public let kernelArchitecture: String
    public let initfsCacheStatus: BenchmarkCacheStatus

    private enum CodingKeys: String, CodingKey {
        case containerizationVersion = "containerization_version"
        case rootfsFormatVersion = "rootfs_format_version"
        case vminitImageReference = "vminit_image_reference"
        case vminitImageDigest = "vminit_image_digest"
        case kernelPath = "kernel_path"
        case kernelVersion = "kernel_version"
        case kernelArchitecture = "kernel_architecture"
        case initfsCacheStatus = "initfs_cache_status"
    }

    public init(
        containerizationVersion: String,
        rootfsFormatVersion: String,
        vminitImageReference: String,
        vminitImageDigest: String,
        kernelPath: String,
        kernelVersion: String,
        kernelArchitecture: String,
        initfsCacheStatus: BenchmarkCacheStatus
    ) {
        self.containerizationVersion = containerizationVersion
        self.rootfsFormatVersion = rootfsFormatVersion
        self.vminitImageReference = vminitImageReference
        self.vminitImageDigest = vminitImageDigest
        self.kernelPath = kernelPath
        self.kernelVersion = kernelVersion
        self.kernelArchitecture = kernelArchitecture
        self.initfsCacheStatus = initfsCacheStatus
    }
}

public struct Stage4MicrobenchmarkCleanupProof: Codable, Equatable, Sendable {
    public let cleanupDurationSeconds: Double?
    public let runtimeCleanup: String
    public let volumeCleanup: String
    public let portCleanup: String
    public let logCleanup: String
    public let metricsCleanup: String
    public let cacheCleanup: String
    public let globalCleanup: String
    public let staleFileCount: Int
    public let staleProcessCount: Int
    public let stalePortCount: Int

    private enum CodingKeys: String, CodingKey {
        case cleanupDurationSeconds = "cleanup_duration_seconds"
        case runtimeCleanup = "runtime_cleanup"
        case volumeCleanup = "volume_cleanup"
        case portCleanup = "port_cleanup"
        case logCleanup = "log_cleanup"
        case metricsCleanup = "metrics_cleanup"
        case cacheCleanup = "cache_cleanup"
        case globalCleanup = "global_cleanup"
        case staleFileCount = "stale_file_count"
        case staleProcessCount = "stale_process_count"
        case stalePortCount = "stale_port_count"
    }

    public init(
        cleanupDurationSeconds: Double?,
        runtimeCleanup: String,
        volumeCleanup: String,
        portCleanup: String,
        logCleanup: String,
        metricsCleanup: String,
        cacheCleanup: String,
        globalCleanup: String,
        staleFileCount: Int,
        staleProcessCount: Int,
        stalePortCount: Int
    ) {
        self.cleanupDurationSeconds = cleanupDurationSeconds
        self.runtimeCleanup = runtimeCleanup
        self.volumeCleanup = volumeCleanup
        self.portCleanup = portCleanup
        self.logCleanup = logCleanup
        self.metricsCleanup = metricsCleanup
        self.cacheCleanup = cacheCleanup
        self.globalCleanup = globalCleanup
        self.staleFileCount = staleFileCount
        self.staleProcessCount = staleProcessCount
        self.stalePortCount = stalePortCount
    }
}

public struct Stage4MicrobenchmarkMetrics: Codable, Equatable, Sendable {
    public let durationSeconds: Double?
    public let bytesCopied: UInt64?
    public let blockReadBytes: UInt64?
    public let blockWriteBytes: UInt64?
    public let healthcheckAttempts: Int?
    public let timeoutSeconds: Double?
    public let cloneSuccess: Bool?
    public let fallbackReason: String?
    public let cleanupResult: String?

    private enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds"
        case bytesCopied = "bytes_copied"
        case blockReadBytes = "block_read_bytes"
        case blockWriteBytes = "block_write_bytes"
        case healthcheckAttempts = "healthcheck_attempts"
        case timeoutSeconds = "timeout_seconds"
        case cloneSuccess = "clone_success"
        case fallbackReason = "fallback_reason"
        case cleanupResult = "cleanup_result"
    }

    public init(
        durationSeconds: Double? = nil,
        bytesCopied: UInt64? = nil,
        blockReadBytes: UInt64? = nil,
        blockWriteBytes: UInt64? = nil,
        healthcheckAttempts: Int? = nil,
        timeoutSeconds: Double? = nil,
        cloneSuccess: Bool? = nil,
        fallbackReason: String? = nil,
        cleanupResult: String? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.bytesCopied = bytesCopied
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.healthcheckAttempts = healthcheckAttempts
        self.timeoutSeconds = timeoutSeconds
        self.cloneSuccess = cloneSuccess
        self.fallbackReason = fallbackReason
        self.cleanupResult = cleanupResult
    }
}

public struct Stage4MicrobenchmarkMeasurementRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let projectID: String
    public let runtimeResourceName: String
    public let probeID: String
    public let kind: Stage4MicrobenchmarkKind
    public let coldOrWarm: String
    public let imageReference: String
    public let volumeName: String
    public let serviceName: String
    public let environment: BenchmarkRunMetadata?
    public let runtimeContext: Stage4MicrobenchmarkRuntimeContext?
    public let cleanupProof: Stage4MicrobenchmarkCleanupProof?
    public let status: Stage4MicrobenchmarkMeasurementStatus
    public let metrics: Stage4MicrobenchmarkMetrics
    public let guest: HostFootprintGuestStats?
    public let hostPhysicalMemoryStatus: Stage4HostPhysicalMemoryStatus
    public let failure: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordType = "record_type"
        case timestamp
        case projectID = "project_id"
        case runtimeResourceName = "runtime_resource_name"
        case probeID = "probe_id"
        case kind
        case coldOrWarm = "cold_or_warm"
        case imageReference = "image_reference"
        case volumeName = "volume_name"
        case serviceName = "service_name"
        case environment
        case runtimeContext = "runtime_context"
        case cleanupProof = "cleanup_proof"
        case status
        case metrics
        case guest
        case hostPhysicalMemoryStatus = "host_physical_memory_status"
        case failure
    }

    public init(
        timestamp: String,
        projectID: String,
        runtimeResourceName: String,
        probe: Stage4MicrobenchmarkProbe,
        environment: BenchmarkRunMetadata?,
        runtimeContext: Stage4MicrobenchmarkRuntimeContext? = nil,
        cleanupProof: Stage4MicrobenchmarkCleanupProof? = nil,
        status: Stage4MicrobenchmarkMeasurementStatus,
        metrics: Stage4MicrobenchmarkMetrics,
        guest: HostFootprintGuestStats?,
        failure: String?
    ) {
        self.schemaVersion = Stage4MicrobenchmarkSchema.version
        self.recordType = Stage4MicrobenchmarkSchema.measurementRecordType
        self.timestamp = timestamp
        self.projectID = projectID
        self.runtimeResourceName = runtimeResourceName
        self.probeID = probe.probeID
        self.kind = probe.kind
        self.coldOrWarm = probe.coldOrWarm
        self.imageReference = probe.imageReference
        self.volumeName = probe.volumeName
        self.serviceName = probe.serviceName
        self.environment = environment
        self.runtimeContext = runtimeContext
        self.cleanupProof = cleanupProof
        self.status = status
        self.metrics = metrics
        self.guest = guest
        self.hostPhysicalMemoryStatus = .blocked
        self.failure = failure
    }
}

public struct Stage4MicrobenchmarkCleanupExpectation: Codable, Equatable, Sendable {
    public let runtimeCleanup: String
    public let volumeCleanup: String
    public let portCleanup: String
    public let logCleanup: String
    public let metricsCleanup: String
    public let cacheCleanup: String
    public let globalCleanup: String

    private enum CodingKeys: String, CodingKey {
        case runtimeCleanup = "runtime_cleanup"
        case volumeCleanup = "volume_cleanup"
        case portCleanup = "port_cleanup"
        case logCleanup = "log_cleanup"
        case metricsCleanup = "metrics_cleanup"
        case cacheCleanup = "cache_cleanup"
        case globalCleanup = "global_cleanup"
    }

    public init(
        runtimeCleanup: String = "not-run",
        volumeCleanup: String = "preserved-by-default",
        portCleanup: String = "not-run",
        logCleanup: String = "not-run",
        metricsCleanup: String = "not-run",
        cacheCleanup: String = "preserved",
        globalCleanup: String = "not-run"
    ) {
        self.runtimeCleanup = runtimeCleanup
        self.volumeCleanup = volumeCleanup
        self.portCleanup = portCleanup
        self.logCleanup = logCleanup
        self.metricsCleanup = metricsCleanup
        self.cacheCleanup = cacheCleanup
        self.globalCleanup = globalCleanup
    }
}

public struct Stage4MicrobenchmarkProbe: Codable, Equatable, Sendable {
    public let probeID: String
    public let kind: Stage4MicrobenchmarkKind
    public let coldOrWarm: String
    public let imageReference: String
    public let volumeName: String
    public let serviceName: String
    public let command: [String]
    public let targetPath: String
    public let cacheKeyKind: Stage4MicrobenchmarkCacheKeyKind
    public let runtimeMutation: String
    public let requiresRuntimeApprovalToMeasure: Bool
    public let expectedMetrics: [String]

    private enum CodingKeys: String, CodingKey {
        case probeID = "probe_id"
        case kind
        case coldOrWarm = "cold_or_warm"
        case imageReference = "image_reference"
        case volumeName = "volume_name"
        case serviceName = "service_name"
        case command
        case targetPath = "target_path"
        case cacheKeyKind = "cache_key_kind"
        case runtimeMutation = "runtime_mutation"
        case requiresRuntimeApprovalToMeasure = "requires_runtime_approval_to_measure"
        case expectedMetrics = "expected_metrics"
    }

    public init(
        probeID: String,
        kind: Stage4MicrobenchmarkKind,
        coldOrWarm: String,
        imageReference: String = "",
        volumeName: String = "",
        serviceName: String = "",
        command: [String] = [],
        targetPath: String,
        cacheKeyKind: Stage4MicrobenchmarkCacheKeyKind = .notApplicable,
        runtimeMutation: String = "not-run",
        requiresRuntimeApprovalToMeasure: Bool = true,
        expectedMetrics: [String]
    ) {
        self.probeID = probeID
        self.kind = kind
        self.coldOrWarm = coldOrWarm
        self.imageReference = imageReference
        self.volumeName = volumeName
        self.serviceName = serviceName
        self.command = command
        self.targetPath = targetPath
        self.cacheKeyKind = cacheKeyKind
        self.runtimeMutation = runtimeMutation
        self.requiresRuntimeApprovalToMeasure = requiresRuntimeApprovalToMeasure
        self.expectedMetrics = expectedMetrics
    }
}

public enum Stage4MicrobenchmarkMutationScope: String, Codable, Equatable, Sendable {
    case reusableCache = "reusable-cache"
    case projectRuntimeState = "project-runtime-state"
    case projectNamedVolume = "project-named-volume"
    case runtimeExec = "runtime-exec"
}

public struct Stage4MicrobenchmarkOperation: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let projectID: String
    public let runtimeResourceName: String
    public let probeID: String
    public let kind: Stage4MicrobenchmarkKind
    public let coldOrWarm: String
    public let imageReference: String
    public let volumeName: String
    public let serviceName: String
    public let command: [String]
    public let targetPath: String
    public let expectedMetrics: [String]
    public let mutationScope: Stage4MicrobenchmarkMutationScope
    public let runtimeMutation: String
    public let requiresRuntimeApproval: Bool
    public let mutatesGlobalState: Bool
    public let cleanupExpectation: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordType = "record_type"
        case timestamp
        case projectID = "project_id"
        case runtimeResourceName = "runtime_resource_name"
        case probeID = "probe_id"
        case kind
        case coldOrWarm = "cold_or_warm"
        case imageReference = "image_reference"
        case volumeName = "volume_name"
        case serviceName = "service_name"
        case command
        case targetPath = "target_path"
        case expectedMetrics = "expected_metrics"
        case mutationScope = "mutation_scope"
        case runtimeMutation = "runtime_mutation"
        case requiresRuntimeApproval = "requires_runtime_approval"
        case mutatesGlobalState = "mutates_global_state"
        case cleanupExpectation = "cleanup_expectation"
    }

    public init(
        probe: Stage4MicrobenchmarkProbe,
        plan: Stage4MicrobenchmarkPlanRecord,
        mutationScope: Stage4MicrobenchmarkMutationScope,
        cleanupExpectation: String,
        runtimeMutation: String = "planned-not-run",
        requiresRuntimeApproval: Bool = true,
        mutatesGlobalState: Bool = false
    ) {
        self.schemaVersion = Stage4MicrobenchmarkSchema.version
        self.recordType = Stage4MicrobenchmarkSchema.operationRecordType
        self.timestamp = plan.timestamp
        self.projectID = plan.projectID
        self.runtimeResourceName = plan.runtimeResourceName
        self.probeID = probe.probeID
        self.kind = probe.kind
        self.coldOrWarm = probe.coldOrWarm
        self.imageReference = probe.imageReference
        self.volumeName = probe.volumeName
        self.serviceName = probe.serviceName
        self.command = probe.command
        self.targetPath = probe.targetPath
        self.expectedMetrics = probe.expectedMetrics
        self.mutationScope = mutationScope
        self.runtimeMutation = runtimeMutation
        self.requiresRuntimeApproval = requiresRuntimeApproval
        self.mutatesGlobalState = mutatesGlobalState
        self.cleanupExpectation = cleanupExpectation
    }
}

public struct Stage4MicrobenchmarkOperationResult: Codable, Equatable, Sendable {
    public let timestamp: String
    public let environment: BenchmarkRunMetadata?
    public let runtimeContext: Stage4MicrobenchmarkRuntimeContext?
    public let cleanupProof: Stage4MicrobenchmarkCleanupProof?
    public let status: Stage4MicrobenchmarkMeasurementStatus
    public let metrics: Stage4MicrobenchmarkMetrics
    public let guest: HostFootprintGuestStats?
    public let failure: String?

    public init(
        timestamp: String,
        environment: BenchmarkRunMetadata?,
        runtimeContext: Stage4MicrobenchmarkRuntimeContext? = nil,
        cleanupProof: Stage4MicrobenchmarkCleanupProof? = nil,
        status: Stage4MicrobenchmarkMeasurementStatus,
        metrics: Stage4MicrobenchmarkMetrics,
        guest: HostFootprintGuestStats?,
        failure: String?
    ) {
        self.timestamp = timestamp
        self.environment = environment
        self.runtimeContext = runtimeContext
        self.cleanupProof = cleanupProof
        self.status = status
        self.metrics = metrics
        self.guest = guest
        self.failure = failure
    }
}

public struct Stage4MicrobenchmarkPlanRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let status: String
    public let projectID: String
    public let displayName: String
    public let runtimeResourceName: String
    public let hostPhysicalMemoryStatus: Stage4HostPhysicalMemoryStatus
    public let cleanupExpectation: Stage4MicrobenchmarkCleanupExpectation
    public let probes: [Stage4MicrobenchmarkProbe]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordType = "record_type"
        case timestamp
        case status
        case projectID = "project_id"
        case displayName = "display_name"
        case runtimeResourceName = "runtime_resource_name"
        case hostPhysicalMemoryStatus = "host_physical_memory_status"
        case cleanupExpectation = "cleanup_expectation"
        case probes
    }

    public init(
        timestamp: String,
        projectID: String,
        displayName: String,
        runtimeResourceName: String,
        probes: [Stage4MicrobenchmarkProbe],
        cleanupExpectation: Stage4MicrobenchmarkCleanupExpectation = Stage4MicrobenchmarkCleanupExpectation()
    ) {
        self.schemaVersion = Stage4MicrobenchmarkSchema.version
        self.recordType = Stage4MicrobenchmarkSchema.planRecordType
        self.timestamp = timestamp
        self.status = "planned-dry-run-no-runtime-mutation"
        self.projectID = projectID
        self.displayName = displayName
        self.runtimeResourceName = runtimeResourceName
        self.hostPhysicalMemoryStatus = .blocked
        self.cleanupExpectation = cleanupExpectation
        self.probes = probes
    }
}

public struct Stage4MicrobenchmarkOperationPlanner: Sendable {
    public init() {}

    public func planOperations(for record: Stage4MicrobenchmarkPlanRecord) -> [Stage4MicrobenchmarkOperation] {
        record.probes.map { planOperation(for: $0, plan: record) }
    }

    public func planOperation(
        for probe: Stage4MicrobenchmarkProbe,
        plan record: Stage4MicrobenchmarkPlanRecord
    ) -> Stage4MicrobenchmarkOperation {
        Stage4MicrobenchmarkOperation(
            probe: probe,
            plan: record,
            mutationScope: mutationScope(for: probe.kind),
            cleanupExpectation: cleanupExpectation(for: probe.kind)
        )
    }

    private func mutationScope(for kind: Stage4MicrobenchmarkKind) -> Stage4MicrobenchmarkMutationScope {
        switch kind {
        case .rootfsUnpack:
            return .reusableCache
        case .rootfsCopy, .apfsClone:
            return .projectRuntimeState
        case .namedVolumeFresh, .namedVolumeWarm:
            return .projectNamedVolume
        case .healthcheckExec:
            return .runtimeExec
        }
    }

    private func cleanupExpectation(for kind: Stage4MicrobenchmarkKind) -> String {
        switch kind {
        case .rootfsUnpack:
            return "preserve-reusable-cache"
        case .rootfsCopy:
            return "remove-project-runtime-copy"
        case .apfsClone:
            return "remove-project-runtime-clone"
        case .namedVolumeFresh, .namedVolumeWarm:
            return "preserve-named-volume-by-default"
        case .healthcheckExec:
            return "remove-metrics-only"
        }
    }
}

public struct Stage4MicrobenchmarkEvidenceValidator: Sendable {
    public init() {}

    public func validate(
        plan: Stage4MicrobenchmarkPlanRecord,
        operations: [Stage4MicrobenchmarkOperation] = [],
        measurements: [Stage4MicrobenchmarkMeasurementRecord] = []
    ) -> [Diagnostic] {
        var diagnostics = validatePlan(plan)
        if !operations.isEmpty {
            diagnostics += validateOperations(operations, plan: plan)
        }
        if !measurements.isEmpty {
            diagnostics += validateMeasurements(measurements, plan: plan)
        }
        return diagnostics
    }

    public func validate(
        planEvidenceURL: URL,
        operationEvidenceURL: URL? = nil,
        measurementEvidenceURL: URL? = nil
    ) throws -> [Diagnostic] {
        let plans: [Stage4MicrobenchmarkPlanRecord] = try readJSONL(planEvidenceURL)
        guard let plan = plans.first else {
            return [blocking("stage4-plan-evidence-empty", "Stage 4 plan evidence file is empty.")]
        }
        var diagnostics: [Diagnostic] = []
        if plans.count != 1 {
            diagnostics.append(
                blocking(
                    "stage4-plan-evidence-count",
                    "Stage 4 plan evidence file must contain exactly one plan record."
                )
            )
        }
        if let operationEvidenceURL {
            let operations: [Stage4MicrobenchmarkOperation] = try readJSONL(operationEvidenceURL)
            diagnostics += validate(plan: plan, operations: operations)
        } else {
            diagnostics += validate(plan: plan)
        }
        if let measurementEvidenceURL {
            let measurements: [Stage4MicrobenchmarkMeasurementRecord] = try readJSONL(measurementEvidenceURL)
            diagnostics += validateMeasurements(measurements, plan: plan)
        }
        return diagnostics
    }

    private func validatePlan(_ plan: Stage4MicrobenchmarkPlanRecord) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        if plan.schemaVersion != Stage4MicrobenchmarkSchema.version {
            diagnostics.append(blocking("stage4-plan-schema-mismatch", "Stage 4 plan schema version is invalid."))
        }
        if plan.recordType != Stage4MicrobenchmarkSchema.planRecordType {
            diagnostics.append(blocking("stage4-plan-record-type-mismatch", "Stage 4 plan record type is invalid."))
        }
        if plan.status != "planned-dry-run-no-runtime-mutation" {
            diagnostics.append(blocking("stage4-plan-status-mismatch", "Stage 4 plan must be no-runtime evidence."))
        }
        if plan.hostPhysicalMemoryStatus != .blocked {
            diagnostics.append(blocking("stage4-host-memory-not-blocked", "Stage 4 host physical memory must remain blocked."))
        }
        if plan.cleanupExpectation.globalCleanup != "not-run" {
            diagnostics.append(blocking("stage4-plan-global-cleanup", "Stage 4 plan must not include global cleanup."))
        }
        if plan.cleanupExpectation.cacheCleanup != "preserved" {
            diagnostics.append(blocking("stage4-plan-cache-cleanup", "Stage 4 plan must preserve reusable cache state."))
        }
        if plan.probes.isEmpty {
            diagnostics.append(blocking("stage4-plan-empty", "Stage 4 plan must contain at least one probe."))
        }
        let plannedKinds = Set(plan.probes.map(\.kind))
        if !Self.requiredProbeKinds.isSubset(of: plannedKinds) {
            diagnostics.append(
                blocking(
                    "stage4-plan-required-probes-missing",
                    "Stage 4 plan must include rootfs, volume, and healthcheck microbenchmark probes."
                )
            )
        }
        for probe in plan.probes {
            if probe.runtimeMutation != "not-run" {
                diagnostics.append(blocking("stage4-probe-runtime-mutation", "Stage 4 probes must not be marked as run."))
            }
            if !probe.requiresRuntimeApprovalToMeasure {
                diagnostics.append(blocking("stage4-probe-approval-missing", "Stage 4 probes must require runtime approval."))
            }
            if probe.expectedMetrics.isEmpty {
                diagnostics.append(blocking("stage4-probe-metrics-empty", "Stage 4 probes must name expected metrics."))
            }
            validateProbeShape(probe, diagnostics: &diagnostics)
        }
        return diagnostics
    }

    private static let requiredProbeKinds: Set<Stage4MicrobenchmarkKind> = [
        .rootfsUnpack,
        .rootfsCopy,
        .apfsClone,
        .namedVolumeFresh,
        .namedVolumeWarm,
        .healthcheckExec
    ]

    private func validateProbeShape(
        _ probe: Stage4MicrobenchmarkProbe,
        diagnostics: inout [Diagnostic]
    ) {
        switch probe.kind {
        case .rootfsUnpack, .rootfsCopy, .apfsClone:
            if probe.imageReference.isEmpty {
                diagnostics.append(blocking("stage4-rootfs-image-missing", "Stage 4 rootfs probes must name an image reference."))
            }
            if probe.cacheKeyKind != .imageReferencePendingDigest {
                diagnostics.append(
                    blocking(
                        "stage4-rootfs-cache-key-missing",
                        "Stage 4 rootfs probes must keep digest-key proof pending until runtime/image resolution."
                    )
                )
            }
            if !probe.targetPath.contains("/cache/rootfs-by-digest/") {
                diagnostics.append(blocking("stage4-rootfs-cache-path-missing", "Stage 4 rootfs probes must target reusable rootfs cache state."))
            }
        case .namedVolumeFresh, .namedVolumeWarm:
            if probe.volumeName.isEmpty {
                diagnostics.append(blocking("stage4-volume-name-missing", "Stage 4 named-volume probes must name a volume."))
            }
            if !probe.targetPath.contains("/volumes/") {
                diagnostics.append(blocking("stage4-volume-path-missing", "Stage 4 named-volume probes must target project volume state."))
            }
        case .healthcheckExec:
            if probe.serviceName.isEmpty {
                diagnostics.append(blocking("stage4-healthcheck-service-missing", "Stage 4 healthcheck probes must name a service."))
            }
            if probe.command.isEmpty {
                diagnostics.append(blocking("stage4-healthcheck-command-missing", "Stage 4 healthcheck probes must include the exec command."))
            }
            if !probe.targetPath.contains("/metrics") {
                diagnostics.append(blocking("stage4-healthcheck-metrics-path-missing", "Stage 4 healthcheck probes must target metrics state."))
            }
        }
    }

    private func validateOperations(
        _ operations: [Stage4MicrobenchmarkOperation],
        plan: Stage4MicrobenchmarkPlanRecord
    ) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let probesByID = Dictionary(uniqueKeysWithValues: plan.probes.map { ($0.probeID, $0) })
        if operations.count != plan.probes.count {
            diagnostics.append(
                blocking(
                    "stage4-operation-count-mismatch",
                    "Stage 4 operation evidence count must match planned probe count."
                )
            )
        }
        for operation in operations {
            guard let probe = probesByID[operation.probeID] else {
                diagnostics.append(
                    blocking(
                        "stage4-operation-unknown-probe",
                        "Stage 4 operation \(operation.probeID) does not match a planned probe."
                    )
                )
                continue
            }

            if operation.schemaVersion != Stage4MicrobenchmarkSchema.version {
                diagnostics.append(blocking("stage4-operation-schema-mismatch", "Stage 4 operation schema is invalid."))
            }
            if operation.recordType != Stage4MicrobenchmarkSchema.operationRecordType {
                diagnostics.append(blocking("stage4-operation-record-type-mismatch", "Stage 4 operation record type is invalid."))
            }
            if operation.projectID != plan.projectID || operation.runtimeResourceName != plan.runtimeResourceName {
                diagnostics.append(blocking("stage4-operation-project-mismatch", "Stage 4 operation project identity does not match the plan."))
            }
            if operation.kind != probe.kind {
                diagnostics.append(blocking("stage4-operation-kind-mismatch", "Stage 4 operation kind does not match its planned probe."))
            }
            if operation.coldOrWarm != probe.coldOrWarm
                || operation.imageReference != probe.imageReference
                || operation.volumeName != probe.volumeName
                || operation.serviceName != probe.serviceName
                || operation.command != probe.command
                || operation.targetPath != probe.targetPath
                || operation.expectedMetrics != probe.expectedMetrics {
                diagnostics.append(
                    blocking(
                        "stage4-operation-target-mismatch",
                        "Stage 4 operation target fields do not match the planned probe."
                    )
                )
            }
            if operation.runtimeMutation != "planned-not-run" {
                diagnostics.append(
                    blocking(
                        "stage4-operation-runtime-mutation-not-planned",
                        "Stage 4 operation evidence must remain planned-not-run."
                    )
                )
            }
            if !operation.requiresRuntimeApproval {
                diagnostics.append(
                    blocking(
                        "stage4-operation-approval-missing",
                        "Stage 4 operation evidence must require runtime approval."
                    )
                )
            }
            if operation.mutatesGlobalState {
                diagnostics.append(
                    blocking(
                        "stage4-operation-global-mutation",
                        "Stage 4 operation evidence must not mutate global state."
                    )
                )
            }
            if operation.mutationScope != expectedMutationScope(for: operation.kind) {
                diagnostics.append(
                    blocking(
                        "stage4-operation-scope-mismatch",
                        "Stage 4 operation mutation scope does not match the probe kind."
                    )
                )
            }
            if operation.cleanupExpectation != expectedCleanupExpectation(for: operation.kind) {
                diagnostics.append(
                    blocking(
                        "stage4-operation-cleanup-mismatch",
                        "Stage 4 operation cleanup expectation does not match the probe kind."
                    )
                )
            }
        }
        return diagnostics
    }

    private func validateMeasurements(
        _ measurements: [Stage4MicrobenchmarkMeasurementRecord],
        plan: Stage4MicrobenchmarkPlanRecord
    ) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let probesByID = Dictionary(uniqueKeysWithValues: plan.probes.map { ($0.probeID, $0) })
        if measurements.count != plan.probes.count {
            diagnostics.append(
                blocking(
                    "stage4-measurement-count-mismatch",
                    "Stage 4 measurement evidence count must match planned probe count."
                )
            )
        }
        var seenProbeIDs: Set<String> = []
        for measurement in measurements {
            guard let probe = probesByID[measurement.probeID] else {
                diagnostics.append(
                    blocking(
                        "stage4-measurement-unknown-probe",
                        "Stage 4 measurement \(measurement.probeID) does not match a planned probe."
                    )
                )
                continue
            }

            if !seenProbeIDs.insert(measurement.probeID).inserted {
                diagnostics.append(
                    blocking(
                        "stage4-measurement-duplicate-probe",
                        "Stage 4 measurement \(measurement.probeID) appears more than once."
                    )
                )
            }
            if measurement.schemaVersion != Stage4MicrobenchmarkSchema.version {
                diagnostics.append(blocking("stage4-measurement-schema-mismatch", "Stage 4 measurement schema is invalid."))
            }
            if measurement.recordType != Stage4MicrobenchmarkSchema.measurementRecordType {
                diagnostics.append(blocking("stage4-measurement-record-type-mismatch", "Stage 4 measurement record type is invalid."))
            }
            if measurement.projectID != plan.projectID || measurement.runtimeResourceName != plan.runtimeResourceName {
                diagnostics.append(blocking("stage4-measurement-project-mismatch", "Stage 4 measurement project identity does not match the plan."))
            }
            if measurement.kind != probe.kind || measurement.coldOrWarm != probe.coldOrWarm {
                diagnostics.append(blocking("stage4-measurement-probe-mismatch", "Stage 4 measurement kind or lifecycle does not match its planned probe."))
            }
            if measurement.imageReference != probe.imageReference
                || measurement.volumeName != probe.volumeName
                || measurement.serviceName != probe.serviceName {
                diagnostics.append(blocking("stage4-measurement-target-mismatch", "Stage 4 measurement target does not match its planned probe."))
            }
            if measurement.hostPhysicalMemoryStatus != .blocked {
                diagnostics.append(blocking("stage4-measurement-host-memory-not-blocked", "Stage 4 measurement host physical memory must remain blocked."))
            }
            validateMeasurementEnvironment(
                measurement.environment,
                probe: probe,
                runtimeResourceName: plan.runtimeResourceName,
                diagnostics: &diagnostics
            )
            validateMeasurementRuntimeContext(measurement.runtimeContext, diagnostics: &diagnostics)
            validateMeasurementRuntimeMetadataConsistency(
                environment: measurement.environment,
                runtimeContext: measurement.runtimeContext,
                diagnostics: &diagnostics
            )
            validateMeasurementCleanupProof(measurement.cleanupProof, diagnostics: &diagnostics)
            validateMeasurementMetrics(measurement.metrics, kind: measurement.kind, diagnostics: &diagnostics)
            if measurement.guest == nil {
                diagnostics.append(blocking("stage4-measurement-guest-missing", "Stage 4 measurement must include guest cgroup metrics."))
            }
            switch measurement.status {
            case .measured:
                if let failure = measurement.failure, !failure.isEmpty {
                    diagnostics.append(blocking("stage4-measurement-failure-present", "Measured Stage 4 records must not include a failure reason."))
                }
            case .failed:
                if measurement.failure?.isEmpty ?? true {
                    diagnostics.append(blocking("stage4-measurement-failure-missing", "Failed Stage 4 records must include a failure reason."))
                }
            }
        }
        return diagnostics
    }

    private func validateMeasurementEnvironment(
        _ environment: BenchmarkRunMetadata?,
        probe: Stage4MicrobenchmarkProbe,
        runtimeResourceName: String,
        diagnostics: inout [Diagnostic]
    ) {
        guard let environment else {
            diagnostics.append(blocking("stage4-measurement-environment-missing", "Stage 4 measurement must include runtime metadata."))
            return
        }
        if environment.runtime != .linuxpod {
            diagnostics.append(blocking("stage4-measurement-runtime-mismatch", "Stage 4 measurement runtime must be LinuxPod."))
        }
        if environment.targetName != runtimeResourceName {
            diagnostics.append(
                blocking(
                    "stage4-measurement-runtime-target-mismatch",
                    "Stage 4 measurement runtime metadata must match the planned adapter-owned LinuxPod name."
                )
            )
        }
        if environment.coldOrWarm != probe.coldOrWarm || environment.lifecycle.rawValue != probe.coldOrWarm {
            diagnostics.append(blocking("stage4-measurement-lifecycle-mismatch", "Stage 4 measurement lifecycle does not match the probe."))
        }
        if environment.runtimeVersion.isEmpty || environment.macOSVersion.isEmpty || environment.hostArchitecture.isEmpty {
            diagnostics.append(blocking("stage4-measurement-environment-incomplete", "Stage 4 measurement runtime metadata is incomplete."))
        }
        if !probe.imageReference.isEmpty
            && environment.imageCacheStatus != .hit
            && environment.imageCacheStatus != .miss {
            diagnostics.append(
                blocking(
                    "stage4-measurement-image-cache-state-missing",
                    "Stage 4 image-backed measurements must record image cache hit or miss."
                )
            )
        }
        switch probe.kind {
        case .rootfsUnpack:
            if environment.rootfsCacheStatus != .miss {
                diagnostics.append(
                    blocking(
                        "stage4-measurement-rootfs-cache-state-mismatch",
                        "Cold rootfs unpack measurements must record a rootfs cache miss."
                    )
                )
            }
        case .rootfsCopy, .apfsClone:
            if environment.rootfsCacheStatus != .hit {
                diagnostics.append(
                    blocking(
                        "stage4-measurement-rootfs-cache-state-mismatch",
                        "Warm rootfs copy and APFS clone measurements must record a rootfs cache hit."
                    )
                )
            }
        case .namedVolumeFresh:
            if environment.volumeExistedBeforeRun {
                diagnostics.append(
                    blocking(
                        "stage4-measurement-volume-lifecycle-mismatch",
                        "Fresh named-volume measurements must record that the volume did not exist before the run."
                    )
                )
            }
        case .namedVolumeWarm:
            if !environment.volumeExistedBeforeRun {
                diagnostics.append(
                    blocking(
                        "stage4-measurement-volume-lifecycle-mismatch",
                        "Warm named-volume measurements must record that the volume existed before the run."
                    )
                )
            }
        case .healthcheckExec:
            break
        }
    }

    private func validateMeasurementRuntimeMetadataConsistency(
        environment: BenchmarkRunMetadata?,
        runtimeContext: Stage4MicrobenchmarkRuntimeContext?,
        diagnostics: inout [Diagnostic]
    ) {
        guard let environment, let runtimeContext else {
            return
        }
        guard let environmentContainerizationVersion = environment.containerizationVersion,
              !environmentContainerizationVersion.isEmpty else {
            diagnostics.append(
                blocking(
                    "stage4-measurement-containerization-version-missing",
                    "Stage 4 measurement metadata must include the apple/containerization version."
                )
            )
            return
        }
        if environmentContainerizationVersion != runtimeContext.containerizationVersion {
            diagnostics.append(
                blocking(
                    "stage4-measurement-containerization-version-mismatch",
                    "Stage 4 measurement metadata and runtime context must agree on the apple/containerization version."
                )
            )
        }
        if environment.initfsCacheStatus != runtimeContext.initfsCacheStatus {
            diagnostics.append(
                blocking(
                    "stage4-measurement-initfs-cache-state-mismatch",
                    "Stage 4 measurement metadata and runtime context must agree on initfs cache state."
                )
            )
        }
    }

    private func validateMeasurementRuntimeContext(
        _ runtimeContext: Stage4MicrobenchmarkRuntimeContext?,
        diagnostics: inout [Diagnostic]
    ) {
        guard let runtimeContext else {
            diagnostics.append(
                blocking(
                    "stage4-measurement-runtime-context-missing",
                    "Stage 4 measurement must include containerization, initfs, vminit, kernel, and rootfs metadata."
                )
            )
            return
        }
        if runtimeContext.containerizationVersion.isEmpty
            || runtimeContext.rootfsFormatVersion.isEmpty
            || runtimeContext.vminitImageReference.isEmpty
            || runtimeContext.vminitImageDigest.isEmpty
            || runtimeContext.kernelPath.isEmpty
            || runtimeContext.kernelVersion.isEmpty
            || runtimeContext.kernelArchitecture.isEmpty {
            diagnostics.append(
                blocking(
                    "stage4-measurement-runtime-context-incomplete",
                    "Stage 4 measurement runtime context is incomplete."
                )
            )
        }
        if runtimeContext.kernelPath.contains("/Users/") {
            diagnostics.append(
                blocking(
                    "stage4-measurement-kernel-path-unsafe",
                    "Stage 4 measurement runtime context must not expose personal host paths."
                )
            )
        }
        if runtimeContext.initfsCacheStatus != .hit && runtimeContext.initfsCacheStatus != .miss {
            diagnostics.append(
                blocking(
                    "stage4-measurement-initfs-cache-status-missing",
                    "Stage 4 measurement must record initfs cache hit or miss."
                )
            )
        }
    }

    private func validateMeasurementCleanupProof(
        _ cleanupProof: Stage4MicrobenchmarkCleanupProof?,
        diagnostics: inout [Diagnostic]
    ) {
        guard let cleanupProof else {
            diagnostics.append(
                blocking(
                    "stage4-measurement-cleanup-proof-missing",
                    "Stage 4 measurement must include structured cleanup proof."
                )
            )
            return
        }
        if cleanupProof.cleanupDurationSeconds == nil {
            diagnostics.append(blocking("stage4-measurement-cleanup-duration-missing", "Stage 4 cleanup proof must include duration."))
        }
        if cleanupProof.globalCleanup != "not-run" {
            diagnostics.append(blocking("stage4-measurement-global-cleanup", "Stage 4 cleanup proof must not include global cleanup."))
        }
        if cleanupProof.cacheCleanup != "preserved" {
            diagnostics.append(blocking("stage4-measurement-cache-cleanup", "Stage 4 cleanup proof must preserve reusable cache state."))
        }
        if cleanupProof.staleFileCount != 0 || cleanupProof.staleProcessCount != 0 || cleanupProof.stalePortCount != 0 {
            diagnostics.append(blocking("stage4-measurement-stale-state", "Stage 4 cleanup proof must show zero stale files, processes, and ports."))
        }
        if cleanupProof.runtimeCleanup.isEmpty
            || cleanupProof.volumeCleanup.isEmpty
            || cleanupProof.portCleanup.isEmpty
            || cleanupProof.logCleanup.isEmpty
            || cleanupProof.metricsCleanup.isEmpty {
            diagnostics.append(blocking("stage4-measurement-cleanup-proof-incomplete", "Stage 4 cleanup proof is incomplete."))
        }
    }

    private func validateMeasurementMetrics(
        _ metrics: Stage4MicrobenchmarkMetrics,
        kind: Stage4MicrobenchmarkKind,
        diagnostics: inout [Diagnostic]
    ) {
        if metrics.durationSeconds == nil {
            diagnostics.append(blocking("stage4-measurement-duration-missing", "Stage 4 measurement must include timing."))
        }
        if metrics.blockReadBytes == nil && metrics.blockWriteBytes == nil {
            diagnostics.append(blocking("stage4-measurement-block-io-missing", "Stage 4 measurement must include block I/O."))
        }
        if metrics.cleanupResult?.isEmpty ?? true {
            diagnostics.append(blocking("stage4-measurement-cleanup-missing", "Stage 4 measurement must include cleanup result."))
        }
        switch kind {
        case .rootfsCopy:
            if metrics.bytesCopied == nil {
                diagnostics.append(blocking("stage4-measurement-bytes-copied-missing", "Rootfs copy measurements must include copied bytes."))
            }
        case .apfsClone:
            if metrics.cloneSuccess == nil {
                diagnostics.append(blocking("stage4-measurement-clone-result-missing", "APFS clone measurements must include clone result."))
            }
        case .healthcheckExec:
            if metrics.healthcheckAttempts == nil {
                diagnostics.append(blocking("stage4-measurement-healthcheck-attempts-missing", "Healthcheck measurements must include attempt count."))
            }
        case .rootfsUnpack, .namedVolumeFresh, .namedVolumeWarm:
            break
        }
    }

    private func expectedMutationScope(for kind: Stage4MicrobenchmarkKind) -> Stage4MicrobenchmarkMutationScope {
        switch kind {
        case .rootfsUnpack:
            return .reusableCache
        case .rootfsCopy, .apfsClone:
            return .projectRuntimeState
        case .namedVolumeFresh, .namedVolumeWarm:
            return .projectNamedVolume
        case .healthcheckExec:
            return .runtimeExec
        }
    }

    private func expectedCleanupExpectation(for kind: Stage4MicrobenchmarkKind) -> String {
        switch kind {
        case .rootfsUnpack:
            return "preserve-reusable-cache"
        case .rootfsCopy:
            return "remove-project-runtime-copy"
        case .apfsClone:
            return "remove-project-runtime-clone"
        case .namedVolumeFresh, .namedVolumeWarm:
            return "preserve-named-volume-by-default"
        case .healthcheckExec:
            return "remove-metrics-only"
        }
    }

    private func blocking(_ code: String, _ message: String) -> Diagnostic {
        Diagnostic(severity: .blocking, code: code, message: message)
    }

    private func readJSONL<T: Decodable>(_ url: URL) throws -> [T] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        let decoder = JSONDecoder()
        return try lines.map { line in
            try decoder.decode(T.self, from: Data(String(line).utf8))
        }
    }
}

public struct Stage4MicrobenchmarkPlanner: Sendable {
    public let store: ProjectRuntimeStore

    public init(store: ProjectRuntimeStore = ProjectRuntimeStore()) {
        self.store = store
    }

    public func plan(project: LocalDevProject, timestamp: String) -> Stage4MicrobenchmarkPlanRecord {
        let runtimePlan = AppleNativePlanner().plan(project).runtimePlan
        let session = ProjectSessionManager(store: store).planSession(for: project)
        let projectName = ProjectName(project.id)
        var probes: [Stage4MicrobenchmarkProbe] = []

        for image in Set(runtimePlan.services.map(\.image)).sorted() {
            let rootfsPath = store.rootfsCacheURL(imageReference: image).path
            probes.append(
                rootfsProbe(
                    kind: .rootfsUnpack,
                    image: image,
                    targetPath: rootfsPath,
                    lifecycle: .cold,
                    metrics: ["rootfs_prep_seconds", "block_read_bytes", "block_write_bytes", "cleanup_result"]
                )
            )
            probes.append(
                rootfsProbe(
                    kind: .rootfsCopy,
                    image: image,
                    targetPath: rootfsPath,
                    lifecycle: .warm,
                    metrics: ["rootfs_copy_seconds", "bytes_copied", "block_read_bytes", "block_write_bytes"]
                )
            )
            probes.append(
                rootfsProbe(
                    kind: .apfsClone,
                    image: image,
                    targetPath: rootfsPath,
                    lifecycle: .warm,
                    metrics: ["apfs_clone_seconds", "clone_success", "fallback_reason", "block_write_bytes"]
                )
            )
        }

        for volume in runtimePlan.volumes.sorted(by: { $0.name < $1.name }) {
            let volumePath = store.volumeDirectory(for: projectName, volumeName: volume.name).path
            probes.append(
                volumeProbe(kind: .namedVolumeFresh, volumeName: volume.name, targetPath: volumePath, lifecycle: .cold)
            )
            probes.append(
                volumeProbe(kind: .namedVolumeWarm, volumeName: volume.name, targetPath: volumePath, lifecycle: .warm)
            )
        }

        for service in runtimePlan.services.sorted(by: { $0.name < $1.name }) {
            for readiness in service.readiness where readiness.kind == .serviceHealthy {
                probes.append(
                    Stage4MicrobenchmarkProbe(
                        probeID: "healthcheck-exec-\(ProjectName(service.name).sanitized)",
                        kind: .healthcheckExec,
                        coldOrWarm: BenchmarkLifecycle.warm.rawValue,
                        serviceName: service.name,
                        command: readiness.command,
                        targetPath: session.paths.runtimeStateDirectories["metrics"] ?? "",
                        expectedMetrics: [
                            "healthcheck_exec_seconds",
                            "healthcheck_attempts",
                            "timeout_seconds",
                            "guest_cgroup_memory_current_bytes",
                            "block_read_bytes"
                        ]
                    )
                )
            }
        }

        return Stage4MicrobenchmarkPlanRecord(
            timestamp: timestamp,
            projectID: project.id,
            displayName: project.name,
            runtimeResourceName: session.runtimeResourceName,
            probes: probes
        )
    }

    private func rootfsProbe(
        kind: Stage4MicrobenchmarkKind,
        image: String,
        targetPath: String,
        lifecycle: BenchmarkLifecycle,
        metrics: [String]
    ) -> Stage4MicrobenchmarkProbe {
        Stage4MicrobenchmarkProbe(
            probeID: "\(kind.rawValue)-\(cacheKey(for: image))",
            kind: kind,
            coldOrWarm: lifecycle.rawValue,
            imageReference: image,
            targetPath: targetPath,
            cacheKeyKind: .imageReferencePendingDigest,
            expectedMetrics: metrics
        )
    }

    private func volumeProbe(
        kind: Stage4MicrobenchmarkKind,
        volumeName: String,
        targetPath: String,
        lifecycle: BenchmarkLifecycle
    ) -> Stage4MicrobenchmarkProbe {
        Stage4MicrobenchmarkProbe(
            probeID: "\(kind.rawValue)-\(ProjectName(volumeName).sanitized)",
            kind: kind,
            coldOrWarm: lifecycle.rawValue,
            volumeName: volumeName,
            targetPath: targetPath,
            expectedMetrics: [
                "volume_setup_seconds",
                "volume_existed_before_run",
                "block_read_bytes",
                "block_write_bytes",
                "cleanup_result"
            ]
        )
    }

    private func cacheKey(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        var result = ""
        var previousWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "default" : trimmed
    }
}

public struct Stage4MicrobenchmarkJSONLWriter: Sendable {
    public init() {}

    public func append(_ record: Stage4MicrobenchmarkPlanRecord, to url: URL) throws {
        try appendEncoded(record, to: url)
    }

    public func append(_ record: Stage4MicrobenchmarkOperation, to url: URL) throws {
        try appendEncoded(record, to: url)
    }

    public func append(_ record: Stage4MicrobenchmarkMeasurementRecord, to url: URL) throws {
        try appendEncoded(record, to: url)
    }

    private func appendEncoded(_ record: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(record)
        data.append(0x0A)

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }
}

public protocol Stage4MicrobenchmarkRunning: Sendable {
    func measure(
        probe: Stage4MicrobenchmarkProbe,
        plan: Stage4MicrobenchmarkPlanRecord,
        sequence: Int
    ) async throws -> Stage4MicrobenchmarkMeasurementRecord
}

public protocol Stage4MicrobenchmarkOperationExecuting: Sendable {
    func measure(
        operation: Stage4MicrobenchmarkOperation,
        plan: Stage4MicrobenchmarkPlanRecord,
        sequence: Int
    ) async throws -> Stage4MicrobenchmarkOperationResult
}

public struct UnavailableStage4MicrobenchmarkRunner: Stage4MicrobenchmarkRunning {
    public init() {}

    public func measure(
        probe _: Stage4MicrobenchmarkProbe,
        plan _: Stage4MicrobenchmarkPlanRecord,
        sequence _: Int
    ) async throws -> Stage4MicrobenchmarkMeasurementRecord {
        throw RuntimeBackendError.runtimeUnavailable(
            "Stage 4 microbenchmark measurement executor is approval-gated but not implemented in this no-runtime slice."
        )
    }
}

public struct UnavailableStage4MicrobenchmarkOperationExecutor: Stage4MicrobenchmarkOperationExecuting {
    public init() {}

    public func measure(
        operation: Stage4MicrobenchmarkOperation,
        plan _: Stage4MicrobenchmarkPlanRecord,
        sequence _: Int
    ) async throws -> Stage4MicrobenchmarkOperationResult {
        throw RuntimeBackendError.runtimeUnavailable(
            "No concrete Stage 4 microbenchmark operation executor is configured for \(operation.kind.rawValue)."
        )
    }
}

public struct LinuxPodStage4MicrobenchmarkRunner: Stage4MicrobenchmarkRunning {
    public let operationPlanner: Stage4MicrobenchmarkOperationPlanner
    public let operationExecutor: any Stage4MicrobenchmarkOperationExecuting

    public init(
        operationPlanner: Stage4MicrobenchmarkOperationPlanner = Stage4MicrobenchmarkOperationPlanner(),
        operationExecutor: any Stage4MicrobenchmarkOperationExecuting = UnavailableStage4MicrobenchmarkOperationExecutor()
    ) {
        self.operationPlanner = operationPlanner
        self.operationExecutor = operationExecutor
    }

    public func measure(
        probe: Stage4MicrobenchmarkProbe,
        plan: Stage4MicrobenchmarkPlanRecord,
        sequence: Int
    ) async throws -> Stage4MicrobenchmarkMeasurementRecord {
        let operation = operationPlanner.planOperation(for: probe, plan: plan)
        let result = try await operationExecutor.measure(operation: operation, plan: plan, sequence: sequence)
        return Stage4MicrobenchmarkMeasurementRecord(
            timestamp: result.timestamp,
            projectID: plan.projectID,
            runtimeResourceName: plan.runtimeResourceName,
            probe: probe,
            environment: result.environment,
            runtimeContext: result.runtimeContext,
            cleanupProof: result.cleanupProof,
            status: result.status,
            metrics: result.metrics,
            guest: result.guest,
            failure: result.failure
        )
    }
}

public struct Stage4MicrobenchmarkExecutor: Sendable {
    public let runner: any Stage4MicrobenchmarkRunning

    public init(runner: any Stage4MicrobenchmarkRunning = UnavailableStage4MicrobenchmarkRunner()) {
        self.runner = runner
    }

    public func measure(
        plan: Stage4MicrobenchmarkPlanRecord,
        approval: RuntimeApproval = RuntimeApproval()
    ) async throws -> [Stage4MicrobenchmarkMeasurementRecord] {
        guard approval.approved, approval.token == LinuxPodBackend.runtimeApprovalToken else {
            throw RuntimeBackendError.runtimeMutationRequiresApproval(
                "Stage 4 microbenchmark measurement requires explicit current-task approval and token \(LinuxPodBackend.runtimeApprovalToken)."
            )
        }

        var records: [Stage4MicrobenchmarkMeasurementRecord] = []
        for (index, probe) in plan.probes.enumerated() {
            let record = try await runner.measure(probe: probe, plan: plan, sequence: index + 1)
            records.append(record)
        }
        return records
    }
}

public struct Stage4MicrobenchmarkPlanHarness: Sendable {
    public let store: ProjectRuntimeStore
    public let frontend: ComposeFrontend
    public let writer: Stage4MicrobenchmarkJSONLWriter

    public init(
        store: ProjectRuntimeStore = ProjectRuntimeStore(),
        frontend: ComposeFrontend = ComposeFrontend(),
        writer: Stage4MicrobenchmarkJSONLWriter = Stage4MicrobenchmarkJSONLWriter()
    ) {
        self.store = store
        self.frontend = frontend
        self.writer = writer
    }

    @discardableResult
    public func emitPlan(
        composeFile: URL,
        projectName: String,
        timestamp: String,
        evidenceURL: URL
    ) throws -> Stage4MicrobenchmarkPlanRecord {
        let project = try frontend.parseProject(fileURL: composeFile, projectName: projectName).project
        let record = Stage4MicrobenchmarkPlanner(store: store).plan(project: project, timestamp: timestamp)
        try writer.append(record, to: evidenceURL)
        return record
    }

    @discardableResult
    public func emitOperationPlan(
        composeFile: URL,
        projectName: String,
        timestamp: String,
        evidenceURL: URL
    ) throws -> [Stage4MicrobenchmarkOperation] {
        let project = try frontend.parseProject(fileURL: composeFile, projectName: projectName).project
        let record = Stage4MicrobenchmarkPlanner(store: store).plan(project: project, timestamp: timestamp)
        let operations = Stage4MicrobenchmarkOperationPlanner().planOperations(for: record)
        for operation in operations {
            try writer.append(operation, to: evidenceURL)
        }
        return operations
    }
}

public struct Stage4MicrobenchmarkPlanCommandResult: Equatable, Sendable {
    public let plan: Stage4MicrobenchmarkPlanRecord
    public let operations: [Stage4MicrobenchmarkOperation]
    public let validationDiagnostics: [Diagnostic]

    public init(
        plan: Stage4MicrobenchmarkPlanRecord,
        operations: [Stage4MicrobenchmarkOperation],
        validationDiagnostics: [Diagnostic]
    ) {
        self.plan = plan
        self.operations = operations
        self.validationDiagnostics = validationDiagnostics
    }
}

public struct Stage4MicrobenchmarkPlanCommandRunner: Sendable {
    public init() {}

    public func run(
        options: Stage4MicrobenchmarkPlanCommandOptions
    ) throws -> Stage4MicrobenchmarkPlanCommandResult {
        let timestamp = options.timestamp ?? Self.iso8601Now()
        let harness = Stage4MicrobenchmarkPlanHarness(
            store: ProjectRuntimeStore(baseDirectory: options.storeRoot.fileURL)
        )
        let plan = try harness.emitPlan(
            composeFile: options.composeFile.fileURL,
            projectName: options.projectName,
            timestamp: timestamp,
            evidenceURL: options.evidenceJSONL.fileURL
        )
        let operations: [Stage4MicrobenchmarkOperation]
        if let operationEvidence = options.operationEvidenceJSONL {
            operations = try harness.emitOperationPlan(
                composeFile: options.composeFile.fileURL,
                projectName: options.projectName,
                timestamp: timestamp,
                evidenceURL: operationEvidence.fileURL
            )
        } else {
            operations = []
        }

        var diagnostics: [Diagnostic] = []
        if options.validateEvidence {
            diagnostics = try Stage4MicrobenchmarkEvidenceValidator().validate(
                planEvidenceURL: options.evidenceJSONL.fileURL,
                operationEvidenceURL: options.operationEvidenceJSONL?.fileURL,
                measurementEvidenceURL: options.measurementEvidenceJSONL?.fileURL
            )
            guard diagnostics.isEmpty else {
                throw Stage4MicrobenchmarkPlanCommandError.evidenceValidationFailed(diagnostics)
            }
        }

        return Stage4MicrobenchmarkPlanCommandResult(
            plan: plan,
            operations: operations,
            validationDiagnostics: diagnostics
        )
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

public struct Stage4MicrobenchmarkPlanCommandOptions: Equatable, Sendable {
    public struct Path: Equatable, Sendable {
        public let path: String

        public init(_ path: String) {
            self.path = path
        }

        public var fileURL: URL {
            URL(fileURLWithPath: path)
        }
    }

    public let composeFile: Path
    public let projectName: String
    public let timestamp: String?
    public let evidenceJSONL: Path
    public let operationEvidenceJSONL: Path?
    public let measurementEvidenceJSONL: Path?
    public let validateEvidence: Bool
    public let storeRoot: Path

    public init(
        composeFile: Path,
        projectName: String,
        timestamp: String?,
        evidenceJSONL: Path,
        operationEvidenceJSONL: Path? = nil,
        measurementEvidenceJSONL: Path? = nil,
        validateEvidence: Bool = false,
        storeRoot: Path
    ) {
        self.composeFile = composeFile
        self.projectName = projectName
        self.timestamp = timestamp
        self.evidenceJSONL = evidenceJSONL
        self.operationEvidenceJSONL = operationEvidenceJSONL
        self.measurementEvidenceJSONL = measurementEvidenceJSONL
        self.validateEvidence = validateEvidence
        self.storeRoot = storeRoot
    }

    public static func parse(_ args: [String]) throws -> Stage4MicrobenchmarkPlanCommandOptions {
        var composeFile: String?
        var projectName: String?
        var timestamp: String?
        var evidenceJSONL: String?
        var operationEvidenceJSONL: String?
        var measurementEvidenceJSONL: String?
        var validateEvidence = false
        var storeRoot = "/tmp/container-compose-stage4-plan"

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--compose-file":
                composeFile = try value(after: arg, args: args, index: &index)
            case "--project-name":
                projectName = try value(after: arg, args: args, index: &index)
            case "--timestamp":
                timestamp = try value(after: arg, args: args, index: &index)
            case "--evidence-jsonl":
                evidenceJSONL = try value(after: arg, args: args, index: &index)
            case "--operation-evidence-jsonl":
                operationEvidenceJSONL = try value(after: arg, args: args, index: &index)
            case "--measurement-evidence-jsonl":
                measurementEvidenceJSONL = try value(after: arg, args: args, index: &index)
            case "--validate-evidence":
                validateEvidence = true
            case "--store-root":
                storeRoot = try value(after: arg, args: args, index: &index)
            case "--approval-token":
                throw Stage4MicrobenchmarkPlanCommandError.runtimeApprovalNotAccepted
            case "-h", "--help":
                throw Stage4MicrobenchmarkPlanCommandError.helpRequested
            default:
                throw Stage4MicrobenchmarkPlanCommandError.unknownArgument(arg)
            }
            index += 1
        }

        guard let composeFile, !composeFile.isEmpty else {
            throw Stage4MicrobenchmarkPlanCommandError.missingRequiredArgument("--compose-file")
        }
        guard let projectName, !projectName.isEmpty else {
            throw Stage4MicrobenchmarkPlanCommandError.missingRequiredArgument("--project-name")
        }
        guard let evidenceJSONL, !evidenceJSONL.isEmpty else {
            throw Stage4MicrobenchmarkPlanCommandError.missingRequiredArgument("--evidence-jsonl")
        }
        if measurementEvidenceJSONL != nil && !validateEvidence {
            throw Stage4MicrobenchmarkPlanCommandError.measurementEvidenceRequiresValidation
        }

        return Stage4MicrobenchmarkPlanCommandOptions(
            composeFile: Path(composeFile),
            projectName: projectName,
            timestamp: timestamp,
            evidenceJSONL: Path(evidenceJSONL),
            operationEvidenceJSONL: operationEvidenceJSONL.map(Path.init),
            measurementEvidenceJSONL: measurementEvidenceJSONL.map(Path.init),
            validateEvidence: validateEvidence,
            storeRoot: Path(storeRoot)
        )
    }

    private static func value(after flag: String, args: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < args.count else {
            throw Stage4MicrobenchmarkPlanCommandError.missingValue(flag)
        }
        let value = args[valueIndex]
        guard !value.hasPrefix("--") else {
            throw Stage4MicrobenchmarkPlanCommandError.missingValue(flag)
        }
        index = valueIndex
        return value
    }
}

public enum Stage4MicrobenchmarkPlanCommandError: Error, Equatable, CustomStringConvertible {
    case missingRequiredArgument(String)
    case missingValue(String)
    case unknownArgument(String)
    case runtimeApprovalNotAccepted
    case measurementEvidenceRequiresValidation
    case evidenceValidationFailed([Diagnostic])
    case helpRequested

    public var description: String {
        switch self {
        case .missingRequiredArgument(let flag):
            return "Missing required argument \(flag)."
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .unknownArgument(let arg):
            return "Unknown argument \(arg)."
        case .runtimeApprovalNotAccepted:
            return "Stage 4 plan emission is no-runtime only and does not accept runtime approval tokens."
        case .measurementEvidenceRequiresValidation:
            return "Stage 4 measurement evidence paths are validation-only and require --validate-evidence."
        case .evidenceValidationFailed(let diagnostics):
            let codes = diagnostics.map(\.code).joined(separator: ", ")
            return "Stage 4 evidence validation failed: \(codes)."
        case .helpRequested:
            return Stage4MicrobenchmarkPlanCommandHelp.text
        }
    }
}

public enum Stage4MicrobenchmarkPlanCommandHelp {
    public static let text = """
    Usage: container-compose-stage4-microbenchmarks \\
      --compose-file <path> \\
      --project-name <name> \\
      --evidence-jsonl <path> \\
      [--operation-evidence-jsonl <path>] \\
      [--measurement-evidence-jsonl <path>] \\
      [--validate-evidence] \\
      [--timestamp <iso8601>] \\
      [--store-root <path>]

    Emits Stage 4 microbenchmark plan JSONL without runtime mutation.
    Optionally emits approval-gated measurement operation JSONL without running it.
    Optionally validates emitted no-runtime plan, operation evidence, and an existing
    measurement evidence file before exiting.
    """
}
