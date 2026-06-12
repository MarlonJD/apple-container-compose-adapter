// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct DryRunEvidenceRecord: Codable, Equatable, Sendable {
    public struct CacheEvent: Codable, Equatable, Sendable {
        public let image: String
        public let cache: String
        public let rootfs: String
        public let rootfsCache: String
    }

    public struct CleanupProof: Codable, Equatable, Sendable {
        public let runtimeMutation: String
        public let ownedPrefix: String
        public let globalCleanup: String
        public let runtimeCleanup: String
        public let volumeCleanup: String
        public let portCleanup: String
        public let logCleanup: String
        public let metricsCleanup: String
        public let cacheCleanup: String

        public init(
            runtimeMutation: String,
            ownedPrefix: String,
            globalCleanup: String,
            runtimeCleanup: String,
            volumeCleanup: String,
            portCleanup: String,
            logCleanup: String,
            metricsCleanup: String,
            cacheCleanup: String
        ) {
            self.runtimeMutation = runtimeMutation
            self.ownedPrefix = ownedPrefix
            self.globalCleanup = globalCleanup
            self.runtimeCleanup = runtimeCleanup
            self.volumeCleanup = volumeCleanup
            self.portCleanup = portCleanup
            self.logCleanup = logCleanup
            self.metricsCleanup = metricsCleanup
            self.cacheCleanup = cacheCleanup
        }

        public func renderText() -> String {
            [
                "cleanup proof:",
                "runtime mutation: \(runtimeMutation)",
                "owned prefix: \(ownedPrefix)",
                "global cleanup: \(globalCleanup)",
                "runtime cleanup: \(runtimeCleanup)",
                "volume cleanup: \(volumeCleanup)",
                "port cleanup: \(portCleanup)",
                "log cleanup: \(logCleanup)",
                "metrics cleanup: \(metricsCleanup)",
                "cache cleanup: \(cacheCleanup)"
            ].joined(separator: "\n")
        }
    }

    public let schemaVersion: String
    public let timestamp: String
    public let recordType: String
    public let status: String
    public let backend: RuntimeKind
    public let command: AdapterCommand
    public let project: String
    public let approvalRequired: Bool
    public let mutatingActionCount: Int
    public let cacheEvents: [CacheEvent]
    public let cleanupProof: CleanupProof
    public let dryRun: DryRunResult

    public init(timestamp: String, dryRun: DryRunResult) {
        self.schemaVersion = "container-compose-adapter/linuxpod-dry-run/v1"
        self.timestamp = timestamp
        self.recordType = "linuxpod-dry-run-smoke"
        self.status = "planned-dry-run-no-runtime-mutation"
        self.backend = dryRun.backend
        self.command = dryRun.command
        self.project = dryRun.project
        self.approvalRequired = dryRun.approvalRequired
        self.mutatingActionCount = dryRun.mutatingActionCount
        self.cacheEvents = dryRun.actions.compactMap { action in
            guard action.kind == .prepareImageRootfs else {
                return nil
            }
            return CacheEvent(
                image: action.resourceName ?? "",
                cache: action.metadata["cache"] ?? "unknown",
                rootfs: action.metadata["rootfs"] ?? "",
                rootfsCache: action.metadata["rootfsCache"] ?? ""
            )
        }
        self.cleanupProof = CleanupProof.planned(dryRun: dryRun)
        self.dryRun = dryRun
    }
}

public struct RuntimeExecutionEvidenceRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let timestamp: String
    public let recordType: String
    public let status: String
    public let backend: RuntimeKind
    public let command: AdapterCommand
    public let project: String
    public let mutatingActionCount: Int
    public let cacheEvents: [DryRunEvidenceRecord.CacheEvent]
    public let cleanupProof: DryRunEvidenceRecord.CleanupProof
    public let dryRun: DryRunResult
    public let execution: ExecutionResult

    public init(timestamp: String, dryRun: DryRunResult, execution: ExecutionResult) {
        self.schemaVersion = "container-compose-adapter/linuxpod-runtime-execution/v1"
        self.timestamp = timestamp
        self.recordType = "linuxpod-runtime-smoke"
        self.status = execution.status
        self.backend = execution.backend
        self.command = execution.command
        self.project = dryRun.project
        self.mutatingActionCount = dryRun.mutatingActionCount
        self.cacheEvents = dryRun.actions.compactMap { action in
            guard action.kind == .prepareImageRootfs else {
                return nil
            }
            return DryRunEvidenceRecord.CacheEvent(
                image: action.resourceName ?? "",
                cache: action.metadata["cache"] ?? "unknown",
                rootfs: action.metadata["rootfs"] ?? "",
                rootfsCache: action.metadata["rootfsCache"] ?? ""
            )
        }
        self.cleanupProof = DryRunEvidenceRecord.CleanupProof.executed(
            dryRun: dryRun,
            status: execution.status
        )
        self.dryRun = dryRun
        self.execution = execution
    }
}

private extension DryRunEvidenceRecord.CleanupProof {
    static func planned(dryRun: DryRunResult) -> DryRunEvidenceRecord.CleanupProof {
        cleanupProof(
            dryRun: dryRun,
            runtimeMutation: "not-run",
            runtimeCleanupStatus: "planned-only",
            volumeCleanupStatus: "planned-only",
            portCleanupStatus: "planned-release",
            stateCleanupStatus: "planned-runtime-state-cleanup"
        )
    }

    static func executed(dryRun: DryRunResult, status: String) -> DryRunEvidenceRecord.CleanupProof {
        cleanupProof(
            dryRun: dryRun,
            runtimeMutation: status,
            runtimeCleanupStatus: status,
            volumeCleanupStatus: status,
            portCleanupStatus: status,
            stateCleanupStatus: status
        )
    }

    private static func cleanupProof(
        dryRun: DryRunResult,
        runtimeMutation: String,
        runtimeCleanupStatus: String,
        volumeCleanupStatus: String,
        portCleanupStatus: String,
        stateCleanupStatus: String
    ) -> DryRunEvidenceRecord.CleanupProof {
        let hasRuntimeCleanup = dryRun.actions.contains { action in
            action.kind == .stopProjectRuntime || action.kind == .deleteProjectRuntime
        }
        let hasVolumeCleanup = dryRun.actions.contains { $0.kind == .cleanupNamedVolume }
        return DryRunEvidenceRecord.CleanupProof(
            runtimeMutation: runtimeMutation,
            ownedPrefix: LinuxPodStateStore.ownedPrefix,
            globalCleanup: "not-run",
            runtimeCleanup: hasRuntimeCleanup ? runtimeCleanupStatus : "not-requested",
            volumeCleanup: hasVolumeCleanup
                ? volumeCleanupStatus
                : (hasRuntimeCleanup ? "preserved-by-default" : "not-requested"),
            portCleanup: hasRuntimeCleanup ? portCleanupStatus : "not-requested",
            logCleanup: hasRuntimeCleanup ? stateCleanupStatus : "not-requested",
            metricsCleanup: hasRuntimeCleanup ? stateCleanupStatus : "not-requested",
            cacheCleanup: "preserved"
        )
    }
}
