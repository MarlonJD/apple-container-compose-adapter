// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum HostFootprintSchema {
    public static let version = "container-compose-adapter/host-footprint/v1"
    public static let sampleRecordType = "linuxpod-host-footprint-sample"
    public static let decisionRecordType = "linuxpod-host-footprint-source-decision"
    public static let cleanupRecordType = "linuxpod-host-footprint-cleanup"
}

public struct HostFootprintGuestStats: Codable, Equatable, Sendable {
    public let cgroupMemoryCurrentBytes: UInt64
    public let cgroupMemoryLimitBytes: UInt64
    public let processCount: UInt64
    public let cpuUsageUsec: UInt64
    public let blockReadBytes: UInt64
    public let blockWriteBytes: UInt64

    public init(
        cgroupMemoryCurrentBytes: UInt64,
        cgroupMemoryLimitBytes: UInt64,
        processCount: UInt64,
        cpuUsageUsec: UInt64,
        blockReadBytes: UInt64,
        blockWriteBytes: UInt64
    ) {
        self.cgroupMemoryCurrentBytes = cgroupMemoryCurrentBytes
        self.cgroupMemoryLimitBytes = cgroupMemoryLimitBytes
        self.processCount = processCount
        self.cpuUsageUsec = cpuUsageUsec
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
    }
}

public struct HostFootprintSourceSample: Codable, Equatable, Sendable {
    public let source: String
    public let attribution: String
    public let bytes: UInt64?
    public let status: String
    public let note: String?

    public init(source: String, attribution: String, bytes: UInt64?, status: String, note: String? = nil) {
        self.source = source
        self.attribution = attribution
        self.bytes = bytes
        self.status = status
        self.note = note
    }
}

public struct HostFootprintSampleRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let scenario: String
    public let sampleIndex: Int
    public let guest: HostFootprintGuestStats?
    public let hostSources: [HostFootprintSourceSample]

    public init(
        timestamp: String,
        project: String,
        scenario: String,
        sampleIndex: Int,
        guest: HostFootprintGuestStats?,
        hostSources: [HostFootprintSourceSample]
    ) {
        self.schemaVersion = HostFootprintSchema.version
        self.recordType = HostFootprintSchema.sampleRecordType
        self.timestamp = timestamp
        self.project = project
        self.scenario = scenario
        self.sampleIndex = sampleIndex
        self.guest = guest
        self.hostSources = hostSources
    }
}

public enum HostFootprintVerdict: String, Codable, Sendable {
    case accepted
    case rejectedNotScaling = "rejected-not-scaling"
    case blocked
}

public enum HostFootprintCriteria {
    /// The guest must grow by at least this much during the scale test before
    /// a host source can be accepted or rejected on scaling behavior.
    public static let minimumGuestDeltaBytes: Int64 = 64 * 1024 * 1024

    public static func evaluate(
        guestDeltaBytes: Int64,
        hostDeltaBytes: Int64?,
        systemWide: Bool
    ) -> (verdict: HostFootprintVerdict, reason: String) {
        if systemWide {
            return (.blocked, "system-wide source cannot attribute memory to the adapter process")
        }
        guard let hostDeltaBytes else {
            return (.blocked, "source could not be sampled in this environment")
        }
        guard guestDeltaBytes >= minimumGuestDeltaBytes else {
            return (
                .blocked,
                "guest cgroup delta \(guestDeltaBytes) bytes is below the \(minimumGuestDeltaBytes)-byte scale-test threshold, so scaling cannot be judged"
            )
        }
        if hostDeltaBytes < guestDeltaBytes / 2 {
            return (
                .rejectedNotScaling,
                "host delta \(hostDeltaBytes) bytes is less than half of the guest delta \(guestDeltaBytes) bytes"
            )
        }
        return (
            .accepted,
            "host delta \(hostDeltaBytes) bytes tracks the guest delta \(guestDeltaBytes) bytes"
        )
    }
}

public struct HostFootprintSourceDecisionRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let source: String
    public let guestDeltaBytes: Int64
    public let hostDeltaBytes: Int64?
    public let verdict: HostFootprintVerdict
    public let reason: String

    public init(
        timestamp: String,
        project: String,
        source: String,
        guestDeltaBytes: Int64,
        hostDeltaBytes: Int64?,
        verdict: HostFootprintVerdict,
        reason: String
    ) {
        self.schemaVersion = HostFootprintSchema.version
        self.recordType = HostFootprintSchema.decisionRecordType
        self.timestamp = timestamp
        self.project = project
        self.source = source
        self.guestDeltaBytes = guestDeltaBytes
        self.hostDeltaBytes = hostDeltaBytes
        self.verdict = verdict
        self.reason = reason
    }
}

public struct HostFootprintCleanupRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let ownedPrefix: String
    public let stateDirectoryExistsAfterCleanup: Bool
    public let volumeCleanup: String
    public let note: String?

    public init(
        timestamp: String,
        project: String,
        ownedPrefix: String,
        stateDirectoryExistsAfterCleanup: Bool,
        volumeCleanup: String,
        note: String? = nil
    ) {
        self.schemaVersion = HostFootprintSchema.version
        self.recordType = HostFootprintSchema.cleanupRecordType
        self.timestamp = timestamp
        self.project = project
        self.ownedPrefix = ownedPrefix
        self.stateDirectoryExistsAfterCleanup = stateDirectoryExistsAfterCleanup
        self.volumeCleanup = volumeCleanup
        self.note = note
    }
}
