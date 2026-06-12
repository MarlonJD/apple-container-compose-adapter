// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum Phase6BenchmarkSchema {
    public static let version = "container-compose-adapter/linuxpod-phase6-benchmark/v1"
    public static let iterationRecordType = "linuxpod-phase6-benchmark-iteration"
    public static let summaryRecordType = "linuxpod-phase6-benchmark-summary"
}

public enum Phase6BenchmarkIterationStatus: String, Codable, Sendable {
    case measured
    case failed
}

public enum Phase6HostPhysicalMemoryStatus: String, Codable, Sendable {
    case blocked
}

public struct Phase6BenchmarkDurations: Codable, Equatable, Sendable {
    public let up: Double?
    public let status: Double?
    public let logs: Double?
    public let cleanup: Double?

    public init(up: Double?, status: Double?, logs: Double?, cleanup: Double?) {
        self.up = up
        self.status = status
        self.logs = logs
        self.cleanup = cleanup
    }
}

public struct Phase6BenchmarkIterationRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let runLabel: String
    public let iteration: Int
    public let status: Phase6BenchmarkIterationStatus
    public let durationsSeconds: Phase6BenchmarkDurations
    public let guest: HostFootprintGuestStats?
    public let hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus
    public let actionCount: Int
    public let cleanupStateDirectoryExistsAfterCleanup: Bool
    public let failure: String?

    public init(
        timestamp: String,
        project: String,
        runLabel: String,
        iteration: Int,
        status: Phase6BenchmarkIterationStatus,
        durationsSeconds: Phase6BenchmarkDurations,
        guest: HostFootprintGuestStats?,
        hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus,
        actionCount: Int,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        failure: String?
    ) {
        self.schemaVersion = Phase6BenchmarkSchema.version
        self.recordType = Phase6BenchmarkSchema.iterationRecordType
        self.timestamp = timestamp
        self.project = project
        self.runLabel = runLabel
        self.iteration = iteration
        self.status = status
        self.durationsSeconds = durationsSeconds
        self.guest = guest
        self.hostPhysicalMemoryStatus = hostPhysicalMemoryStatus
        self.actionCount = actionCount
        self.cleanupStateDirectoryExistsAfterCleanup = cleanupStateDirectoryExistsAfterCleanup
        self.failure = failure
    }
}

public struct Phase6BenchmarkSummaryRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let projectPrefix: String
    public let runLabel: String
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
    }
}

private func p50<T: Comparable>(_ values: [T]) -> T? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}
