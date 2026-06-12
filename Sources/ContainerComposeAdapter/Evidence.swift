// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct DryRunEvidenceRecord: Codable, Equatable, Sendable {
    public struct CacheEvent: Codable, Equatable, Sendable {
        public let image: String
        public let cache: String
        public let rootfs: String
    }

    public struct CleanupProof: Codable, Equatable, Sendable {
        public let runtimeMutation: String
        public let ownedPrefix: String
        public let globalCleanup: String
        public let volumeCleanup: String
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
                rootfs: action.metadata["rootfs"] ?? ""
            )
        }
        self.cleanupProof = CleanupProof(
            runtimeMutation: "not-run",
            ownedPrefix: LinuxPodStateStore.ownedPrefix,
            globalCleanup: "not-run",
            volumeCleanup: dryRun.actions.contains { $0.kind == .cleanupNamedVolume }
                ? "planned-only"
                : "not-requested"
        )
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
                rootfs: action.metadata["rootfs"] ?? ""
            )
        }
        self.cleanupProof = DryRunEvidenceRecord.CleanupProof(
            runtimeMutation: execution.status,
            ownedPrefix: LinuxPodStateStore.ownedPrefix,
            globalCleanup: "not-run",
            volumeCleanup: dryRun.actions.contains { $0.kind == .cleanupNamedVolume }
                ? execution.status
                : "not-requested"
        )
        self.dryRun = dryRun
        self.execution = execution
    }
}
