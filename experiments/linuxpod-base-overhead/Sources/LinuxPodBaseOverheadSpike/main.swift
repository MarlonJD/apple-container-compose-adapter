// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Containerization
import Foundation
import Security

private let schemaVersion = "linuxpod-base-overhead/v1"
private let runtimeBackend = "containerization-linuxpod"
private let containerizationVersion = "0.26.5"
private let runtimeApprovalToken = "I_APPROVE_LINUXPOD_RUNTIME_MUTATION"
private let ownedPrefix = "cca-linuxpod-spike-"
private let postgresPassword = "postgres"

enum SpikeError: Error, CustomStringConvertible {
    case usage(String)
    case runtimeBlocked(String)

    var description: String {
        switch self {
        case .usage(let message), .runtimeBlocked(let message):
            return message
        }
    }
}

enum Mode: String, CaseIterable, Codable {
    case idlePod = "idle-pod"
    case postgresOnly = "postgres-only"
    case postgresAPI = "postgres-api"
}

struct Options {
    var mode: Mode?
    var iterations = 1
    var dryRun = false
    var output: String?
    var approvalToken: String?
    var imageReferences = ImageReferences.defaults
}

struct ImageReferences: Codable {
    let initfs: String
    let alpine: String
    let postgres: String

    static let defaults = ImageReferences(
        initfs: "ghcr.io/apple/containerization/vminit:\(containerizationVersion)",
        alpine: "docker.io/library/alpine:3.20",
        postgres: "docker.io/library/postgres:16-alpine"
    )
}

struct SourceSnapshot: Codable {
    let package: String
    let version: String
    let inspectedSourcePath: String
    let inspectedFiles: [String]
    let compileProbeSymbols: [String]
    let imageReferences: ImageReferences
}

struct PlannedAction: Codable {
    let order: Int
    let name: String
    let mutatesRuntime: Bool
    let details: String
}

struct MeasurementFields: Codable {
    let setupSeconds: Double?
    let createSeconds: Double?
    let readinessSeconds: Double?
    let loadSeconds: Double?
    let stopSeconds: Double?
    let deleteSeconds: Double?
    let processRSSBytes: UInt64?
    let processHighWaterRSSBytes: UInt64?
    let processCount: UInt64?
    let cgroupMemoryCurrentBytes: UInt64?
    let cgroupMemoryPeakBytes: UInt64?
    let cgroupMemoryLimitBytes: UInt64?
    let hostRuntimeRSSBytes: UInt64?
    let dbDataFootprintBytes: UInt64?
    let blockReadBytes: UInt64?
    let blockWriteBytes: UInt64?
    let cpuPercent: Double?
    let cpuUsageUsec: UInt64?
    let loadCompletedWork: UInt64?
    let loadErrors: UInt64?

    static let empty = MeasurementFields(
        setupSeconds: nil,
        createSeconds: nil,
        readinessSeconds: nil,
        loadSeconds: nil,
        stopSeconds: nil,
        deleteSeconds: nil,
        processRSSBytes: nil,
        processHighWaterRSSBytes: nil,
        processCount: nil,
        cgroupMemoryCurrentBytes: nil,
        cgroupMemoryPeakBytes: nil,
        cgroupMemoryLimitBytes: nil,
        hostRuntimeRSSBytes: nil,
        dbDataFootprintBytes: nil,
        blockReadBytes: nil,
        blockWriteBytes: nil,
        cpuPercent: nil,
        cpuUsageUsec: nil,
        loadCompletedWork: nil,
        loadErrors: nil
    )

    enum CodingKeys: String, CodingKey {
        case setupSeconds
        case createSeconds
        case readinessSeconds
        case loadSeconds
        case stopSeconds
        case deleteSeconds
        case processRSSBytes
        case processHighWaterRSSBytes
        case processCount
        case cgroupMemoryCurrentBytes
        case cgroupMemoryPeakBytes
        case cgroupMemoryLimitBytes
        case hostRuntimeRSSBytes
        case dbDataFootprintBytes
        case blockReadBytes
        case blockWriteBytes
        case cpuPercent
        case cpuUsageUsec
        case loadCompletedWork
        case loadErrors
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setupSeconds, forKey: .setupSeconds)
        try container.encode(createSeconds, forKey: .createSeconds)
        try container.encode(readinessSeconds, forKey: .readinessSeconds)
        try container.encode(loadSeconds, forKey: .loadSeconds)
        try container.encode(stopSeconds, forKey: .stopSeconds)
        try container.encode(deleteSeconds, forKey: .deleteSeconds)
        try container.encode(processRSSBytes, forKey: .processRSSBytes)
        try container.encode(processHighWaterRSSBytes, forKey: .processHighWaterRSSBytes)
        try container.encode(processCount, forKey: .processCount)
        try container.encode(cgroupMemoryCurrentBytes, forKey: .cgroupMemoryCurrentBytes)
        try container.encode(cgroupMemoryPeakBytes, forKey: .cgroupMemoryPeakBytes)
        try container.encode(cgroupMemoryLimitBytes, forKey: .cgroupMemoryLimitBytes)
        try container.encode(hostRuntimeRSSBytes, forKey: .hostRuntimeRSSBytes)
        try container.encode(dbDataFootprintBytes, forKey: .dbDataFootprintBytes)
        try container.encode(blockReadBytes, forKey: .blockReadBytes)
        try container.encode(blockWriteBytes, forKey: .blockWriteBytes)
        try container.encode(cpuPercent, forKey: .cpuPercent)
        try container.encode(cpuUsageUsec, forKey: .cpuUsageUsec)
        try container.encode(loadCompletedWork, forKey: .loadCompletedWork)
        try container.encode(loadErrors, forKey: .loadErrors)
    }
}

struct CleanupPlan: Codable {
    let ownedPrefix: String
    let stopPod: Bool
    let deleteRootfsFiles: Bool
    let releaseNetwork: Bool
    let verifyNoOwnedState: Bool
    let result: String?
    let forbiddenActions: [String]
}

struct EvidenceRecord: Codable {
    let schemaVersion: String
    let timestamp: String
    let recordType: String
    let scenario: Mode
    let runtimeBackend: String
    let source: SourceSnapshot
    let iteration: Int
    let iterationsPlanned: Int
    let status: String
    let statusReason: String
    let approvalGate: String
    let plannedActions: [PlannedAction]
    let metrics: MeasurementFields
    let cleanup: CleanupPlan
    let redaction: [String]
}

struct ExecResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let seconds: Double
}

final class BufferWriter: Writer, @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.append(data)
    }

    func close() throws {}

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: storage, encoding: .utf8) ?? ""
    }
}

@main
struct LinuxPodBaseOverheadSpike {
    static func main() async {
        do {
            let options = try parseOptions(Array(CommandLine.arguments[1...]))
            try await run(options: options)
        } catch {
            FileHandle.standardError.write(Data("\(redactMessage(String(describing: error)))\n".utf8))
            Foundation.exit(64)
        }
    }

    private static func run(options: Options) async throws {
        guard let mode = options.mode else {
            throw SpikeError.usage(Self.usage())
        }
        guard options.iterations > 0 else {
            throw SpikeError.usage("--iterations must be greater than 0")
        }

        if options.dryRun {
            let records = (1...options.iterations).map { iteration in
                makeRecord(
                    mode: mode,
                    iteration: iteration,
                    iterations: options.iterations,
                    recordType: "scenario-plan",
                    status: "planned-dry-run",
                    statusReason: "No runtime resources created, started, stopped, deleted, pulled, unpacked, or networked.",
                    metrics: .empty,
                    cleanupResult: "not-run",
                    imageReferences: options.imageReferences
                )
            }
            printPlan(mode: mode, iterations: options.iterations, records: records)
            try write(records: records, outputPath: options.output)
            return
        }

        guard options.approvalToken == runtimeApprovalToken else {
            let event = makeRecord(
                mode: mode,
                iteration: 1,
                iterations: options.iterations,
                recordType: "scenario-blocked",
                status: "blocked-runtime",
                statusReason: "Runtime mutation requires --approval-token \(runtimeApprovalToken).",
                metrics: .empty,
                cleanupResult: "not-run",
                imageReferences: options.imageReferences
            )
            try write(records: [event], outputPath: options.output)
            throw SpikeError.runtimeBlocked("runtime execution blocked; approval token missing or incorrect")
        }

        var records: [EvidenceRecord] = []
        for iteration in 1...options.iterations {
            let record = await runRuntime(
                mode: mode,
                iteration: iteration,
                iterations: options.iterations,
                imageReferences: options.imageReferences
            )
            records.append(record)
            printMeasurement(record)
        }
        try write(records: records, outputPath: options.output)
    }

    private static func parseOptions(_ args: [String]) throws -> Options {
        var options = Options()
        var index = 0

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--mode":
                index += 1
                guard index < args.count, let mode = Mode(rawValue: args[index]) else {
                    throw SpikeError.usage("--mode must be one of: \(Mode.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                options.mode = mode
            case "--iterations":
                index += 1
                guard index < args.count, let iterations = Int(args[index]) else {
                    throw SpikeError.usage("--iterations requires an integer value")
                }
                options.iterations = iterations
            case "--dry-run":
                options.dryRun = true
            case "--output":
                index += 1
                guard index < args.count else {
                    throw SpikeError.usage("--output requires a path")
                }
                options.output = args[index]
            case "--approval-token":
                index += 1
                guard index < args.count else {
                    throw SpikeError.usage("--approval-token requires a value")
                }
                options.approvalToken = args[index]
            case "--init-reference":
                index += 1
                guard index < args.count else {
                    throw SpikeError.usage("--init-reference requires a value")
                }
                options.imageReferences = ImageReferences(
                    initfs: args[index],
                    alpine: options.imageReferences.alpine,
                    postgres: options.imageReferences.postgres
                )
            case "--alpine-reference":
                index += 1
                guard index < args.count else {
                    throw SpikeError.usage("--alpine-reference requires a value")
                }
                options.imageReferences = ImageReferences(
                    initfs: options.imageReferences.initfs,
                    alpine: args[index],
                    postgres: options.imageReferences.postgres
                )
            case "--postgres-reference":
                index += 1
                guard index < args.count else {
                    throw SpikeError.usage("--postgres-reference requires a value")
                }
                options.imageReferences = ImageReferences(
                    initfs: options.imageReferences.initfs,
                    alpine: options.imageReferences.alpine,
                    postgres: args[index]
                )
            case "--help", "-h":
                throw SpikeError.usage(Self.usage())
            default:
                throw SpikeError.usage("unknown argument: \(arg)\n\n\(Self.usage())")
            }
            index += 1
        }

        return options
    }

    private static func runRuntime(
        mode: Mode,
        iteration: Int,
        iterations: Int,
        imageReferences: ImageReferences
    ) async -> EvidenceRecord {
        let runID = makeRunID(mode: mode, iteration: iteration)
        let runDirectory = runtimeRoot().appendingPathComponent(runID)
        var pod: LinuxPod?
        var podCreated = false
        var setupSeconds: Double?
        var createSeconds: Double?
        var readinessSeconds: Double?
        var loadSeconds: Double?
        var stopSeconds: Double?
        var deleteSeconds: Double?
        var loadCompletedWork: UInt64 = 0
        var loadErrors: UInt64 = 0

        func cleanup() async -> String {
            let started = Date()
            var messages: [String] = []
            if let pod, podCreated {
                do {
                    try await pod.stop()
                    messages.append("pod-stopped")
                } catch {
                    messages.append("pod-stop-failed:\(redactMessage(String(describing: error)))")
                }
            }
            do {
                if FileManager.default.fileExists(atPath: runDirectory.path) {
                    try FileManager.default.removeItem(at: runDirectory)
                }
                deleteSeconds = Date().timeIntervalSince(started)
                messages.append("owned-state-deleted")
            } catch {
                deleteSeconds = Date().timeIntervalSince(started)
                messages.append("owned-state-delete-failed:\(redactMessage(String(describing: error)))")
            }
            return messages.joined(separator: ",")
        }

        do {
            let setupStart = Date()
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            try ensureVirtualizationEntitlement()
            let kernel = try findKernel()
            let imageStore = try ImageStore(path: runDirectory.appendingPathComponent("image-store"))
            let initImage = try await imageStore.getInitImage(reference: imageReferences.initfs)
            let initfs = try await initImage.initBlock(at: runDirectory.appendingPathComponent("initfs.ext4"), for: .linuxArm)
            var kernelConfig = Kernel(path: kernel, platform: .linuxArm)
            kernelConfig.commandLine.addDebug()
            let vmm = VZVirtualMachineManager(kernel: kernelConfig, initialFilesystem: initfs)

            let alpine = try await unpackImage(
                reference: imageReferences.alpine,
                imageStore: imageStore,
                destination: runDirectory.appendingPathComponent("alpine.ext4"),
                rootfsSize: 512 * 1024 * 1024
            )

            let postgresRootfs: Mount?
            let apiRootfs: Mount?
            switch mode {
            case .idlePod:
                postgresRootfs = nil
                apiRootfs = nil
            case .postgresOnly:
                postgresRootfs = try await unpackImage(
                    reference: imageReferences.postgres,
                    imageStore: imageStore,
                    destination: runDirectory.appendingPathComponent("postgres.ext4"),
                    rootfsSize: 4 * 1024 * 1024 * 1024
                )
                apiRootfs = nil
            case .postgresAPI:
                postgresRootfs = try await unpackImage(
                    reference: imageReferences.postgres,
                    imageStore: imageStore,
                    destination: runDirectory.appendingPathComponent("postgres.ext4"),
                    rootfsSize: 4 * 1024 * 1024 * 1024
                )
                apiRootfs = try await unpackImage(
                    reference: imageReferences.postgres,
                    imageStore: imageStore,
                    destination: runDirectory.appendingPathComponent("api-client.ext4"),
                    rootfsSize: 2 * 1024 * 1024 * 1024
                )
            }
            setupSeconds = Date().timeIntervalSince(setupStart)

            let createdPod = try LinuxPod(runID, vmm: vmm) { config in
                config.cpus = 4
                config.memoryInBytes = 1024 * 1024 * 1024
                config.bootLog = .file(path: runDirectory.appendingPathComponent("boot.log"), append: false)
                config.hostname = runID
            }
            pod = createdPod

            switch mode {
            case .idlePod:
                try await createdPod.addContainer("idle", rootfs: alpine) { config in
                    config.process.arguments = ["/bin/sleep", "infinity"]
                }
            case .postgresOnly:
                guard let postgresRootfs else { throw SpikeError.runtimeBlocked("missing postgres rootfs") }
                try await addPostgresContainer(to: createdPod, rootfs: postgresRootfs)
            case .postgresAPI:
                guard let postgresRootfs, let apiRootfs else { throw SpikeError.runtimeBlocked("missing postgres or api rootfs") }
                try await addPostgresContainer(to: createdPod, rootfs: postgresRootfs)
                try await createdPod.addContainer("api", rootfs: apiRootfs) { config in
                    config.process.arguments = ["/bin/sleep", "infinity"]
                    config.process.environmentVariables += [
                        "PGPASSWORD=\(postgresPassword)"
                    ]
                }
            }

            let createStart = Date()
            try await createdPod.create()
            podCreated = true
            switch mode {
            case .idlePod:
                try await createdPod.startContainer("idle")
            case .postgresOnly:
                try await createdPod.startContainer("db")
            case .postgresAPI:
                try await createdPod.startContainer("db")
                try await createdPod.startContainer("api")
            }
            createSeconds = Date().timeIntervalSince(createStart)

            switch mode {
            case .idlePod:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            case .postgresOnly:
                readinessSeconds = try await waitForPostgres(createdPod, containerID: "db")
                let loadStart = Date()
                try await runSQLProbe(createdPod, containerID: "db")
                loadCompletedWork = 1
                loadSeconds = Date().timeIntervalSince(loadStart)
            case .postgresAPI:
                readinessSeconds = try await waitForPostgres(createdPod, containerID: "db")
                let loadStart = Date()
                try await runSQLProbe(createdPod, containerID: "api")
                loadCompletedWork = 1
                loadSeconds = Date().timeIntervalSince(loadStart)
            }

            let metrics = try await collectMetrics(
                pod: createdPod,
                mode: mode,
                setupSeconds: setupSeconds,
                createSeconds: createSeconds,
                readinessSeconds: readinessSeconds,
                loadSeconds: loadSeconds,
                stopSeconds: nil,
                deleteSeconds: nil,
                loadCompletedWork: loadCompletedWork,
                loadErrors: loadErrors
            )

            let stopStart = Date()
            let cleanupResult = await cleanup()
            stopSeconds = Date().timeIntervalSince(stopStart)
            let finalMetrics = MeasurementFields(
                setupSeconds: metrics.setupSeconds,
                createSeconds: metrics.createSeconds,
                readinessSeconds: metrics.readinessSeconds,
                loadSeconds: metrics.loadSeconds,
                stopSeconds: stopSeconds,
                deleteSeconds: deleteSeconds,
                processRSSBytes: metrics.processRSSBytes,
                processHighWaterRSSBytes: metrics.processHighWaterRSSBytes,
                processCount: metrics.processCount,
                cgroupMemoryCurrentBytes: metrics.cgroupMemoryCurrentBytes,
                cgroupMemoryPeakBytes: metrics.cgroupMemoryPeakBytes,
                cgroupMemoryLimitBytes: metrics.cgroupMemoryLimitBytes,
                hostRuntimeRSSBytes: metrics.hostRuntimeRSSBytes,
                dbDataFootprintBytes: metrics.dbDataFootprintBytes,
                blockReadBytes: metrics.blockReadBytes,
                blockWriteBytes: metrics.blockWriteBytes,
                cpuPercent: metrics.cpuPercent,
                cpuUsageUsec: metrics.cpuUsageUsec,
                loadCompletedWork: metrics.loadCompletedWork,
                loadErrors: metrics.loadErrors
            )
            let cleanupSucceeded = cleanupResult.contains("owned-state-deleted") && !cleanupResult.contains("failed")
            return makeRecord(
                mode: mode,
                iteration: iteration,
                iterations: iterations,
                recordType: "scenario-measurement",
                status: cleanupSucceeded ? "measured-with-limitations" : "failed-cleanup",
                statusReason: cleanupSucceeded
                    ? "Runtime smoke completed; hostRuntimeRSSBytes is runner process RSS while the VM is alive and includes Swift/ImageStore overhead."
                    : "Runtime smoke completed but cleanup verification failed: \(cleanupResult)",
                metrics: finalMetrics,
                cleanupResult: cleanupResult,
                imageReferences: imageReferences
            )
        } catch {
            loadErrors += 1
            let cleanupResult = await cleanup()
            let cleanupSucceeded = cleanupResult.contains("owned-state-deleted") && !cleanupResult.contains("failed")
            return makeRecord(
                mode: mode,
                iteration: iteration,
                iterations: iterations,
                recordType: "scenario-measurement",
                status: cleanupSucceeded ? "blocked-runtime" : "failed-cleanup",
                statusReason: "Runtime smoke failed: \(redactMessage(String(describing: error))). Cleanup: \(cleanupResult)",
                metrics: MeasurementFields(
                    setupSeconds: setupSeconds,
                    createSeconds: createSeconds,
                    readinessSeconds: readinessSeconds,
                    loadSeconds: loadSeconds,
                    stopSeconds: stopSeconds,
                    deleteSeconds: deleteSeconds,
                    processRSSBytes: nil,
                    processHighWaterRSSBytes: nil,
                    processCount: nil,
                    cgroupMemoryCurrentBytes: nil,
                    cgroupMemoryPeakBytes: nil,
                    cgroupMemoryLimitBytes: nil,
                    hostRuntimeRSSBytes: nil,
                    dbDataFootprintBytes: nil,
                    blockReadBytes: nil,
                    blockWriteBytes: nil,
                    cpuPercent: nil,
                    cpuUsageUsec: nil,
                    loadCompletedWork: loadCompletedWork,
                    loadErrors: loadErrors
                ),
                cleanupResult: cleanupResult,
                imageReferences: imageReferences
            )
        }
    }

    private static func addPostgresContainer(to pod: LinuxPod, rootfs: Mount) async throws {
        try await pod.addContainer("db", rootfs: rootfs) { config in
            config.process.arguments = ["/usr/local/bin/docker-entrypoint.sh", "postgres"]
            config.process.environmentVariables += [
                "POSTGRES_PASSWORD=\(postgresPassword)",
                "PGDATA=/var/lib/postgresql/data",
                "POSTGRES_INITDB_ARGS=--encoding=UTF8"
            ]
            config.process.workingDirectory = "/"
        }
    }

    private static func unpackImage(
        reference: String,
        imageStore: ImageStore,
        destination: URL,
        rootfsSize: UInt64
    ) async throws -> Mount {
        let image = try await imageStore.get(reference: reference, pull: true)
        let unpacker = EXT4Unpacker(blockSizeInBytes: rootfsSize)
        return try await unpacker.unpack(image, for: SystemPlatform.linuxArm.ociPlatform(), at: destination)
    }

    private static func waitForPostgres(_ pod: LinuxPod, containerID: String) async throws -> Double {
        let started = Date()
        var lastError = ""
        for attempt in 1...45 {
            let result = try await exec(
                pod,
                containerID: containerID,
                processID: "pg-ready-\(attempt)",
                arguments: ["pg_isready", "-h", "127.0.0.1", "-U", "postgres"],
                environment: ["PGPASSWORD=\(postgresPassword)"]
            )
            if result.exitCode == 0 {
                return Date().timeIntervalSince(started)
            }
            lastError = result.stderr + result.stdout
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw SpikeError.runtimeBlocked("Postgres readiness timed out: \(redactMessage(lastError))")
    }

    private static func runSQLProbe(_ pod: LinuxPod, containerID: String) async throws {
        let result = try await exec(
            pod,
            containerID: containerID,
            processID: "sql-probe",
            arguments: [
                "psql",
                "-h", "127.0.0.1",
                "-U", "postgres",
                "-d", "postgres",
                "-tAc", "select 1"
            ],
            environment: ["PGPASSWORD=\(postgresPassword)"]
        )
        guard result.exitCode == 0 else {
            throw SpikeError.runtimeBlocked("SQL probe failed: \(redactMessage(result.stderr + result.stdout))")
        }
    }

    private static func collectMetrics(
        pod: LinuxPod,
        mode: Mode,
        setupSeconds: Double?,
        createSeconds: Double?,
        readinessSeconds: Double?,
        loadSeconds: Double?,
        stopSeconds: Double?,
        deleteSeconds: Double?,
        loadCompletedWork: UInt64,
        loadErrors: UInt64
    ) async throws -> MeasurementFields {
        if mode == .postgresAPI {
            return try await collectExecBackedMetrics(
                pod: pod,
                mode: mode,
                setupSeconds: setupSeconds,
                createSeconds: createSeconds,
                readinessSeconds: readinessSeconds,
                loadSeconds: loadSeconds,
                stopSeconds: stopSeconds,
                deleteSeconds: deleteSeconds,
                loadCompletedWork: loadCompletedWork,
                loadErrors: loadErrors
            )
        }

        let stats = try await pod.statistics(categories: .all)
        let memoryCurrent = sumUInt64(stats.compactMap { $0.memory?.usageBytes })
        let memoryLimit = sumUInt64(stats.compactMap { $0.memory?.limitBytes })
        let processCount = sumUInt64(stats.compactMap { $0.process?.current })
        let blockRead = sumUInt64(stats.flatMap { $0.blockIO?.devices ?? [] }.map(\.readBytes))
        let blockWrite = sumUInt64(stats.flatMap { $0.blockIO?.devices ?? [] }.map(\.writeBytes))
        let cpuUsage = sumUInt64(stats.compactMap { $0.cpu?.usageUsec })

        var rssBytes: UInt64 = 0
        var hwmBytes: UInt64 = 0
        var rssSeen = false
        for containerID in await pod.listContainers() {
            if let proc = try? await processMemory(pod, containerID: containerID) {
                rssBytes += proc.rss
                hwmBytes += proc.hwm
                rssSeen = true
            }
        }

        let dbFootprint: UInt64?
        if mode == .postgresOnly || mode == .postgresAPI {
            dbFootprint = try? await dbDataFootprint(pod)
        } else {
            dbFootprint = nil
        }
        let hostRSS = currentHostProcessRSSBytes()

        return MeasurementFields(
            setupSeconds: setupSeconds,
            createSeconds: createSeconds,
            readinessSeconds: readinessSeconds,
            loadSeconds: loadSeconds,
            stopSeconds: stopSeconds,
            deleteSeconds: deleteSeconds,
            processRSSBytes: rssSeen ? rssBytes : nil,
            processHighWaterRSSBytes: rssSeen ? hwmBytes : nil,
            processCount: processCount,
            cgroupMemoryCurrentBytes: memoryCurrent > 0 ? memoryCurrent : nil,
            cgroupMemoryPeakBytes: nil,
            cgroupMemoryLimitBytes: memoryLimit > 0 ? memoryLimit : nil,
            hostRuntimeRSSBytes: hostRSS,
            dbDataFootprintBytes: dbFootprint,
            blockReadBytes: blockRead,
            blockWriteBytes: blockWrite,
            cpuPercent: nil,
            cpuUsageUsec: cpuUsage,
            loadCompletedWork: loadCompletedWork,
            loadErrors: loadErrors
        )
    }

    private static func collectExecBackedMetrics(
        pod: LinuxPod,
        mode: Mode,
        setupSeconds: Double?,
        createSeconds: Double?,
        readinessSeconds: Double?,
        loadSeconds: Double?,
        stopSeconds: Double?,
        deleteSeconds: Double?,
        loadCompletedWork: UInt64,
        loadErrors: UInt64
    ) async throws -> MeasurementFields {
        var rssBytes: UInt64 = 0
        var hwmBytes: UInt64 = 0
        var rssSeen = false
        var memoryCurrentValues: [UInt64] = []
        var memoryPeakValues: [UInt64] = []
        var memoryLimitValues: [UInt64] = []
        var processValues: [UInt64] = []
        var blockReadValues: [UInt64] = []
        var blockWriteValues: [UInt64] = []
        var cpuValues: [UInt64] = []

        for containerID in containerIDs(for: mode) {
            if let proc = try? await processMemory(pod, containerID: containerID) {
                rssBytes += proc.rss
                hwmBytes += proc.hwm
                rssSeen = true
            }
            guard let cgroup = try? await containerCgroupSnapshot(pod, containerID: containerID) else {
                continue
            }
            if let value = cgroup.memoryCurrent {
                memoryCurrentValues.append(value)
            }
            if let value = cgroup.memoryPeak {
                memoryPeakValues.append(value)
            }
            if let value = cgroup.memoryLimit {
                memoryLimitValues.append(value)
            }
            if let value = cgroup.processCount {
                processValues.append(value)
            }
            if let value = cgroup.blockRead {
                blockReadValues.append(value)
            }
            if let value = cgroup.blockWrite {
                blockWriteValues.append(value)
            }
            if let value = cgroup.cpuUsage {
                cpuValues.append(value)
            }
        }

        let dbFootprint: UInt64?
        if mode == .postgresOnly || mode == .postgresAPI {
            dbFootprint = try? await dbDataFootprint(pod)
        } else {
            dbFootprint = nil
        }
        let hostRSS = currentHostProcessRSSBytes()

        return MeasurementFields(
            setupSeconds: setupSeconds,
            createSeconds: createSeconds,
            readinessSeconds: readinessSeconds,
            loadSeconds: loadSeconds,
            stopSeconds: stopSeconds,
            deleteSeconds: deleteSeconds,
            processRSSBytes: rssSeen ? rssBytes : nil,
            processHighWaterRSSBytes: rssSeen ? hwmBytes : nil,
            processCount: processValues.isEmpty ? nil : sumUInt64(processValues),
            cgroupMemoryCurrentBytes: memoryCurrentValues.isEmpty ? nil : sumUInt64(memoryCurrentValues),
            cgroupMemoryPeakBytes: memoryPeakValues.isEmpty ? nil : sumUInt64(memoryPeakValues),
            cgroupMemoryLimitBytes: memoryLimitValues.isEmpty ? nil : sumUInt64(memoryLimitValues),
            hostRuntimeRSSBytes: hostRSS,
            dbDataFootprintBytes: dbFootprint,
            blockReadBytes: blockReadValues.isEmpty ? nil : sumUInt64(blockReadValues),
            blockWriteBytes: blockWriteValues.isEmpty ? nil : sumUInt64(blockWriteValues),
            cpuPercent: nil,
            cpuUsageUsec: cpuValues.isEmpty ? nil : sumUInt64(cpuValues),
            loadCompletedWork: loadCompletedWork,
            loadErrors: loadErrors
        )
    }

    private struct CgroupSnapshot {
        var memoryCurrent: UInt64?
        var memoryPeak: UInt64?
        var memoryLimit: UInt64?
        var processCount: UInt64?
        var blockRead: UInt64?
        var blockWrite: UInt64?
        var cpuUsage: UInt64?
    }

    private static func containerIDs(for mode: Mode) -> [String] {
        switch mode {
        case .idlePod:
            return ["idle"]
        case .postgresOnly:
            return ["db"]
        case .postgresAPI:
            return ["db", "api"]
        }
    }

    private static func containerCgroupSnapshot(_ pod: LinuxPod, containerID: String) async throws -> CgroupSnapshot {
        let script = """
        memory_current=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || true)
        memory_peak=$(cat /sys/fs/cgroup/memory.peak 2>/dev/null || true)
        memory_max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)
        pids_current=$(cat /sys/fs/cgroup/pids.current 2>/dev/null || true)
        cpu_usage=$(awk '/usage_usec/ {print $2}' /sys/fs/cgroup/cpu.stat 2>/dev/null || true)
        io_values=$(awk '{for (i = 2; i <= NF; i++) {split($i, item, "="); if (item[1] == "rbytes") r += item[2]; if (item[1] == "wbytes") w += item[2]}} END {printf "%s %s", r + 0, w + 0}' /sys/fs/cgroup/io.stat 2>/dev/null || true)
        set -- $io_values
        printf 'memory.current=%s\\n' "$memory_current"
        printf 'memory.peak=%s\\n' "$memory_peak"
        printf 'memory.max=%s\\n' "$memory_max"
        printf 'pids.current=%s\\n' "$pids_current"
        printf 'cpu.usage_usec=%s\\n' "$cpu_usage"
        printf 'io.rbytes=%s\\n' "${1:-}"
        printf 'io.wbytes=%s\\n' "${2:-}"
        """
        let result = try await exec(
            pod,
            containerID: containerID,
            processID: "cgroup-metrics-\(containerID)",
            arguments: ["sh", "-c", script]
        )
        guard result.exitCode == 0 else {
            throw SpikeError.runtimeBlocked("cgroup metrics probe failed for \(containerID): \(result.stderr)")
        }
        let values = parseKeyValueNumbers(result.stdout)
        return CgroupSnapshot(
            memoryCurrent: values["memory.current"],
            memoryPeak: values["memory.peak"],
            memoryLimit: values["memory.max"],
            processCount: values["pids.current"],
            blockRead: values["io.rbytes"],
            blockWrite: values["io.wbytes"],
            cpuUsage: values["cpu.usage_usec"]
        )
    }

    private static func parseKeyValueNumbers(_ text: String) -> [String: UInt64] {
        var values: [String: UInt64] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard value != "max", let parsed = UInt64(value) else { continue }
            values[parts[0]] = parsed
        }
        return values
    }

    private static func processMemory(_ pod: LinuxPod, containerID: String) async throws -> (rss: UInt64, hwm: UInt64) {
        let result = try await exec(
            pod,
            containerID: containerID,
            processID: "proc-mem-\(containerID)",
            arguments: ["sh", "-c", "awk '/VmRSS|VmHWM/ {print $1 \" \" $2}' /proc/1/status"]
        )
        guard result.exitCode == 0 else {
            throw SpikeError.runtimeBlocked("process memory probe failed for \(containerID): \(result.stderr)")
        }
        var rss: UInt64 = 0
        var hwm: UInt64 = 0
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let value = UInt64(parts[1]) else { continue }
            if parts[0].hasPrefix("VmRSS") {
                rss = value * 1024
            } else if parts[0].hasPrefix("VmHWM") {
                hwm = value * 1024
            }
        }
        return (rss, hwm)
    }

    private static func sumUInt64(_ values: [UInt64]) -> UInt64 {
        var total: UInt64 = 0
        for value in values {
            let result = total.addingReportingOverflow(value)
            if result.overflow {
                return UInt64.max
            }
            total = result.partialValue
        }
        return total
    }

    private static func currentHostProcessRSSBytes() -> UInt64? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "-o", "rss=",
            "-p", "\(ProcessInfo.processInfo.processIdentifier)"
        ]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let rssKiB = UInt64(text) else {
            return nil
        }
        return rssKiB * 1024
    }

    private static func dbDataFootprint(_ pod: LinuxPod) async throws -> UInt64 {
        let result = try await exec(
            pod,
            containerID: "db",
            processID: "db-footprint",
            arguments: ["du", "-sk", "/var/lib/postgresql/data"]
        )
        guard result.exitCode == 0 else {
            throw SpikeError.runtimeBlocked("DB footprint probe failed: \(result.stderr)")
        }
        let first = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first
        guard let first, let kib = UInt64(first) else {
            throw SpikeError.runtimeBlocked("DB footprint parse failed: \(result.stdout)")
        }
        return kib * 1024
    }

    private static func exec(
        _ pod: LinuxPod,
        containerID: String,
        processID: String,
        arguments: [String],
        environment: [String] = []
    ) async throws -> ExecResult {
        let stdout = BufferWriter()
        let stderr = BufferWriter()
        let started = Date()
        let process = try await pod.execInContainer(containerID, processID: processID) { config in
            config.arguments = arguments
            config.environmentVariables += environment
            config.stdout = stdout
            config.stderr = stderr
        }
        try await process.start()
        let status = try await process.wait(timeoutInSeconds: 30)
        try await process.delete()
        return ExecResult(
            exitCode: status.exitCode,
            stdout: stdout.stringValue,
            stderr: stderr.stringValue,
            seconds: Date().timeIntervalSince(started)
        )
    }

    private static func findKernel() throws -> URL {
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
            throw SpikeError.runtimeBlocked("No vmlinux kernel found under \(kernelsDirectory.path)")
        }
        return latest
    }

    private static func ensureVirtualizationEntitlement() throws {
        guard let task = SecTaskCreateFromSelf(nil) else {
            throw SpikeError.runtimeBlocked("Unable to inspect process entitlements before LinuxPod VM creation")
        }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.virtualization" as CFString,
            nil
        )
        guard let entitlement, CFGetTypeID(entitlement) == CFBooleanGetTypeID(), CFBooleanGetValue((entitlement as! CFBoolean)) else {
            throw SpikeError.runtimeBlocked("Process lacks com.apple.security.virtualization entitlement required by Virtualization.framework")
        }
    }

    private static func makeRecord(
        mode: Mode,
        iteration: Int,
        iterations: Int,
        recordType: String,
        status: String,
        statusReason: String,
        metrics: MeasurementFields,
        cleanupResult: String?,
        imageReferences: ImageReferences
    ) -> EvidenceRecord {
        EvidenceRecord(
            schemaVersion: schemaVersion,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            recordType: recordType,
            scenario: mode,
            runtimeBackend: runtimeBackend,
            source: sourceSnapshot(imageReferences: imageReferences),
            iteration: iteration,
            iterationsPlanned: iterations,
            status: status,
            statusReason: statusReason,
            approvalGate: "Runtime mutation approved by owner for \(ownedPrefix)* smoke resources only; no private workloads, registry login, prune, global cleanup, or host-destructive changes.",
            plannedActions: plannedActions(for: mode),
            metrics: metrics,
            cleanup: CleanupPlan(
                ownedPrefix: ownedPrefix,
                stopPod: true,
                deleteRootfsFiles: true,
                releaseNetwork: true,
                verifyNoOwnedState: true,
                result: cleanupResult,
                forbiddenActions: [
                    "container system stop",
                    "container system reset",
                    "container image prune",
                    "docker system prune",
                    "registry login",
                    "global cleanup outside \(ownedPrefix)*"
                ]
            ),
            redaction: [
                redact(key: "POSTGRES_PASSWORD", value: postgresPassword),
                redact(key: "PGPASSWORD", value: postgresPassword),
                redact(key: "DATABASE_URL", value: "postgres://postgres:\(postgresPassword)@127.0.0.1/postgres")
            ]
        )
    }

    private static func sourceSnapshot(imageReferences: ImageReferences) -> SourceSnapshot {
        SourceSnapshot(
            package: "apple/containerization",
            version: containerizationVersion,
            inspectedSourcePath: "/private/tmp/apple-container-source-check/containerization-main",
            inspectedFiles: [
                "Sources/Containerization/LinuxPod.swift",
                "Sources/Integration/PodTests.swift",
                "examples/ctr-example/Package.swift",
                "examples/ctr-example/Sources/ctr-example/main.swift"
            ],
            compileProbeSymbols: [
                String(describing: LinuxPod.self),
                String(describing: ContainerStatistics.self),
                "StatCategory.all.rawValue=\(StatCategory.all.rawValue)"
            ],
            imageReferences: imageReferences
        )
    }

    private static func plannedActions(for mode: Mode) -> [PlannedAction] {
        var actions: [PlannedAction] = [
            PlannedAction(order: 1, name: "prepare-state-directory", mutatesRuntime: true, details: "Create an experiment-owned working directory under docs/evidence/linuxpod-base-overhead/runtime/ with prefix \(ownedPrefix)."),
            PlannedAction(order: 2, name: "resolve-kernel-and-initfs", mutatesRuntime: true, details: "Resolve a local vmlinux kernel and ghcr.io/apple/containerization/vminit:\(containerizationVersion) initfs without registry login."),
            PlannedAction(order: 3, name: "create-linuxpod", mutatesRuntime: true, details: "Create one LinuxPod VM with 4 CPUs and 1GiB memory for comparison against Apple container CLI cgroup/runtime memory."),
        ]

        switch mode {
        case .idlePod:
            actions.append(contentsOf: [
                PlannedAction(order: 4, name: "add-idle-container", mutatesRuntime: true, details: "Add one Alpine rootfs container running sleep infinity."),
                PlannedAction(order: 5, name: "collect-idle-stats", mutatesRuntime: false, details: "Collect pod.statistics memory/cpu/block I/O plus /proc/1 RSS.")
            ])
        case .postgresOnly:
            actions.append(contentsOf: [
                PlannedAction(order: 4, name: "add-postgres-container", mutatesRuntime: true, details: "Add one postgres:16-alpine rootfs container with redacted POSTGRES_PASSWORD and isolated PGDATA."),
                PlannedAction(order: 5, name: "wait-postgres-readiness", mutatesRuntime: false, details: "Exec pg_isready inside the Postgres container until ready or timeout."),
                PlannedAction(order: 6, name: "collect-postgres-stats", mutatesRuntime: false, details: "Collect process RSS, cgroup current/limit, DB footprint, block I/O, CPU usage, readiness, and cleanup timings.")
            ])
        case .postgresAPI:
            actions.append(contentsOf: [
                PlannedAction(order: 4, name: "add-postgres-container", mutatesRuntime: true, details: "Add one postgres:16-alpine rootfs container with redacted POSTGRES_PASSWORD and isolated PGDATA."),
                PlannedAction(order: 5, name: "add-api-container", mutatesRuntime: true, details: "Add one postgres:16-alpine client fixture container in the same LinuxPod shared VM/network namespace."),
                PlannedAction(order: 6, name: "verify-api-to-db", mutatesRuntime: false, details: "Probe API-client-to-Postgres connectivity inside the pod over 127.0.0.1."),
                PlannedAction(order: 7, name: "collect-combined-stats", mutatesRuntime: false, details: "Collect total pod/container memory, marginal client cost, CPU usage, block I/O, readiness, load, failure count, and cleanup timings.")
            ])
        }

        actions.append(PlannedAction(order: actions.count + 1, name: "cleanup-owned-state", mutatesRuntime: true, details: "Stop LinuxPod, delete experiment-owned rootfs/state, and verify no \(ownedPrefix)* state remains."))
        return actions
    }

    private static func printPlan(mode: Mode, iterations: Int, records: [EvidenceRecord]) {
        print("LinuxPod base overhead dry run")
        print("mode: \(mode.rawValue)")
        print("iterations: \(iterations)")
        print("runtime backend: \(runtimeBackend)")
        print("containerization dependency: \(containerizationVersion)")
        print("initfs reference: \(records[0].source.imageReferences.initfs)")
        print("alpine reference: \(records[0].source.imageReferences.alpine)")
        print("postgres reference: \(records[0].source.imageReferences.postgres)")
        print("planned actions:")
        for action in records[0].plannedActions {
            let marker = action.mutatesRuntime ? "runtime-gated" : "observe"
            print("  \(action.order). [\(marker)] \(action.name) - \(action.details)")
        }
        print("status: planned-dry-run")
    }

    private static func printMeasurement(_ record: EvidenceRecord) {
        print("LinuxPod runtime smoke")
        print("mode: \(record.scenario.rawValue)")
        print("iteration: \(record.iteration)/\(record.iterationsPlanned)")
        print("status: \(record.status)")
        print("reason: \(record.statusReason)")
        print("cleanup: \(record.cleanup.result ?? "unknown")")
        if let memory = record.metrics.cgroupMemoryCurrentBytes {
            print("cgroup memory current bytes: \(memory)")
        }
        if let rss = record.metrics.processRSSBytes {
            print("process RSS bytes: \(rss)")
        }
        if let hostRSS = record.metrics.hostRuntimeRSSBytes {
            print("host runner RSS bytes: \(hostRSS)")
        }
    }

    private static func write(records: [EvidenceRecord], outputPath: String?) throws {
        guard let outputPath else { return }

        let url = URL(fileURLWithPath: outputPath)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try records.reduce(into: Data()) { partial, record in
            partial.append(try encoder.encode(record))
            partial.append(Data("\n".utf8))
        }

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    private static func runtimeRoot() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root: URL
        if cwd.path.hasSuffix("experiments/linuxpod-base-overhead") {
            root = cwd.deletingLastPathComponent().deletingLastPathComponent()
        } else {
            root = cwd
        }
        return root.appendingPathComponent("docs/evidence/linuxpod-base-overhead/runtime")
    }

    private static func makeRunID(mode: Mode, iteration: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "Z", with: "")
        let compactMode = mode.rawValue.replacingOccurrences(of: "-", with: "")
        return "\(ownedPrefix)\(compactMode)-\(stamp)-\(iteration)"
    }

    private static func redact(key: String, value: String) -> String {
        let secretMarkers = ["PASSWORD", "TOKEN", "SECRET", "KEY", "CREDENTIAL", "PRIVATE", "AUTH", "SESSION", "DATABASE_URL"]
        if secretMarkers.contains(where: { key.uppercased().contains($0) }) {
            return "\(key)=<redacted>"
        }
        return "\(key)=\(value)"
    }

    private static func redactMessage(_ message: String) -> String {
        message
            .replacingOccurrences(of: postgresPassword, with: "<redacted>")
            .replacingOccurrences(of: "postgres://postgres:<redacted>@127.0.0.1/postgres", with: "postgres://postgres:<redacted>@127.0.0.1/postgres")
    }

    private static func usage() -> String {
        """
        Usage:
          swift run linuxpod-base-overhead --mode <idle-pod|postgres-only|postgres-api> --iterations <n> --dry-run [--output path]
          swift run linuxpod-base-overhead --mode <idle-pod|postgres-only|postgres-api> --iterations <n> --approval-token \(runtimeApprovalToken) [--output path]
            [--init-reference ref] [--alpine-reference ref] [--postgres-reference ref]

        Dry-run mode prints planned LinuxPod actions and writes JSONL evidence without creating pods, rootfs files, networks, volumes, images, or runtime state.
        Runtime mode creates only \(ownedPrefix)* resources under docs/evidence/linuxpod-base-overhead/runtime and deletes them after each iteration.
        """
    }
}
