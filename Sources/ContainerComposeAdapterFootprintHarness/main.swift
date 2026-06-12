// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import ContainerComposeAdapterLinuxPod
import Darwin
import Foundation

@main
struct FootprintHarness {
    static func main() async {
        do {
            let options = try HarnessOptions.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(64)
        }
    }

    private static func run(_ options: HarnessOptions) async throws {
        let executor = ContainerizationLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        let fullPlan = SamplePlans.publicBackendShaped(project: ProjectName(options.projectName))
        let plan = scenarioPlan(options.scenario, fullPlan: fullPlan)
        let projectResource = backend.stateStore.projectName(for: plan.project)
        let approval = RuntimeApproval(
            approved: options.approvalToken == LinuxPodBackend.runtimeApprovalToken,
            token: options.approvalToken
        )

        FileHandle.standardError.write(Data("footprint-harness: scenario \(options.scenario.rawValue) up\n".utf8))
        _ = try await backend.execute(command: .up, plan: plan, options: RuntimeOptions(), approval: approval)

        do {
            if options.scenario == .idlePod {
                try await executor.ensurePodCreated(project: projectResource)
            }
            try await sampleScenario(
                options: options,
                executor: executor,
                projectResource: projectResource
            )
        } catch {
            // Best-effort cleanup before rethrowing so a failed measurement
            // never leaves adapter-owned runtime state behind.
            _ = try? await backend.execute(
                command: .down,
                plan: plan,
                options: RuntimeOptions(includeVolumes: true),
                approval: approval
            )
            throw error
        }

        FileHandle.standardError.write(Data("footprint-harness: down --volumes cleanup\n".utf8))
        _ = try await backend.execute(
            command: .down,
            plan: plan,
            options: RuntimeOptions(includeVolumes: true),
            approval: approval
        )

        let stateRoot = URL(fileURLWithPath: ".container-compose-adapter", isDirectory: true)
        let cleanupRecord = HostFootprintCleanupRecord(
            timestamp: iso8601Now(),
            project: projectResource,
            ownedPrefix: "cca-linuxpod-",
            stateDirectoryExistsAfterCleanup: FileManager.default.fileExists(atPath: stateRoot.path),
            volumeCleanup: "executed",
            note: "down --volumes executed in-process after sampling; process check performed externally"
        )
        try appendJSONLine(cleanupRecord, path: options.evidencePath)
        print("footprint-harness: scenario \(options.scenario.rawValue) completed; evidence at \(options.evidencePath)")
    }

    private static func sampleScenario(
        options: HarnessOptions,
        executor: ContainerizationLinuxPodRuntimeExecutor,
        projectResource: String
    ) async throws {
        if options.scenario == .scaleTest {
            let before = try await takeSamples(
                label: "scale-test-before",
                options: options,
                executor: executor,
                projectResource: projectResource
            )
            FileHandle.standardError.write(Data("footprint-harness: running bulk load (\(options.loadRows) rows)\n".utf8))
            let loadSQL = """
            CREATE TABLE IF NOT EXISTS footprint_load (id bigint, payload text); \
            INSERT INTO footprint_load SELECT g, repeat(md5(g::text), 8) FROM generate_series(1, \(options.loadRows)) g; \
            SELECT count(*) FROM footprint_load;
            """
            let exitCode = try await executor.execInService(
                project: projectResource,
                service: "db",
                processID: "footprint-load-1",
                arguments: ["psql", "-U", "app", "-d", "app", "-v", "ON_ERROR_STOP=1", "-c", loadSQL]
            )
            guard exitCode == 0 else {
                throw HarnessError.runtime("bulk load psql exited with status \(exitCode)")
            }
            let after = try await takeSamples(
                label: "scale-test-after",
                options: options,
                executor: executor,
                projectResource: projectResource
            )
            try writeDecisions(
                before: before,
                after: after,
                options: options,
                projectResource: projectResource
            )
        } else {
            _ = try await takeSamples(
                label: options.scenario.rawValue,
                options: options,
                executor: executor,
                projectResource: projectResource
            )
        }
    }

    private static func takeSamples(
        label: String,
        options: HarnessOptions,
        executor: ContainerizationLinuxPodRuntimeExecutor,
        projectResource: String
    ) async throws -> [HostFootprintSampleRecord] {
        var records: [HostFootprintSampleRecord] = []
        for index in 1...options.samples {
            let guest = try await executor.guestStatistics(project: projectResource)
            let record = HostFootprintSampleRecord(
                timestamp: iso8601Now(),
                project: projectResource,
                scenario: label,
                sampleIndex: index,
                guest: guest,
                hostSources: sampleHostSources()
            )
            try appendJSONLine(record, path: options.evidencePath)
            records.append(record)
            if index < options.samples {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        return records
    }

    private static func writeDecisions(
        before: [HostFootprintSampleRecord],
        after: [HostFootprintSampleRecord],
        options: HarnessOptions,
        projectResource: String
    ) throws {
        let guestBefore = meanGuestMemory(before)
        let guestAfter = meanGuestMemory(after)
        let guestDelta = Int64(guestAfter) - Int64(guestBefore)
        for source in HostSource.allCases {
            let beforeBytes = meanHostBytes(before, source: source)
            let afterBytes = meanHostBytes(after, source: source)
            let hostDelta: Int64?
            if let beforeBytes, let afterBytes {
                hostDelta = Int64(afterBytes) - Int64(beforeBytes)
            } else {
                hostDelta = nil
            }
            let evaluation = HostFootprintCriteria.evaluate(
                guestDeltaBytes: guestDelta,
                hostDeltaBytes: hostDelta,
                systemWide: source.attribution == "system-wide"
            )
            let record = HostFootprintSourceDecisionRecord(
                timestamp: iso8601Now(),
                project: projectResource,
                source: source.rawValue,
                guestDeltaBytes: guestDelta,
                hostDeltaBytes: hostDelta,
                verdict: evaluation.verdict,
                reason: evaluation.reason
            )
            try appendJSONLine(record, path: options.evidencePath)
        }
    }

    private static func meanGuestMemory(_ records: [HostFootprintSampleRecord]) -> UInt64 {
        let values = records.compactMap { $0.guest?.cgroupMemoryCurrentBytes }
        guard !values.isEmpty else {
            return 0
        }
        return values.reduce(0, +) / UInt64(values.count)
    }

    private static func meanHostBytes(_ records: [HostFootprintSampleRecord], source: HostSource) -> UInt64? {
        let values = records.flatMap { record in
            record.hostSources.filter { $0.source == source.rawValue && $0.status == "sampled" }
                .compactMap(\.bytes)
        }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / UInt64(values.count)
    }

    private static func scenarioPlan(_ scenario: Scenario, fullPlan: RuntimePlan) -> RuntimePlan {
        switch scenario {
        case .idlePod:
            return RuntimePlan(project: fullPlan.project, services: [], volumes: [])
        case .dbOnly, .scaleTest:
            let db = fullPlan.services.filter { $0.name == "db" }
            return RuntimePlan(project: fullPlan.project, services: db, volumes: fullPlan.volumes)
        case .fullStack:
            return fullPlan
        }
    }
}

// MARK: - Host source sampling

private enum HostSource: String, CaseIterable {
    case taskInfoPhysFootprint = "task-info-phys-footprint"
    case footprintTool = "footprint-tool"
    case vmmapSummary = "vmmap-summary"
    case psRSSTree = "ps-rss-tree"
    case vmStatDelta = "vm-stat-delta"

    var attribution: String {
        switch self {
        case .taskInfoPhysFootprint, .footprintTool, .vmmapSummary:
            return "adapter-process"
        case .psRSSTree:
            return "process-tree"
        case .vmStatDelta:
            return "system-wide"
        }
    }
}

private func sampleHostSources() -> [HostFootprintSourceSample] {
    let pid = ProcessInfo.processInfo.processIdentifier
    return [
        taskInfoSample(),
        footprintToolSample(pid: pid),
        vmmapSample(pid: pid),
        psSample(pid: pid),
        vmStatSample()
    ]
}

private func taskInfoSample() -> HostFootprintSourceSample {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else {
        return HostFootprintSourceSample(
            source: HostSource.taskInfoPhysFootprint.rawValue,
            attribution: HostSource.taskInfoPhysFootprint.attribution,
            bytes: nil,
            status: "error",
            note: "task_info failed with kr=\(kr)"
        )
    }
    return HostFootprintSourceSample(
        source: HostSource.taskInfoPhysFootprint.rawValue,
        attribution: HostSource.taskInfoPhysFootprint.attribution,
        bytes: info.phys_footprint,
        status: "sampled",
        note: "resident_size=\(info.resident_size)"
    )
}

private func footprintToolSample(pid: Int32) -> HostFootprintSourceSample {
    let result = runTool("/usr/bin/footprint", ["\(pid)"])
    guard result.exitCode == 0,
          let match = firstMatch(result.stdout, pattern: #"Footprint:\s+([0-9.]+)\s+(KB|MB|GB)"#),
          let value = Double(match[0]) else {
        return HostFootprintSourceSample(
            source: HostSource.footprintTool.rawValue,
            attribution: HostSource.footprintTool.attribution,
            bytes: nil,
            status: "error",
            note: "footprint tool failed: \(result.stderr.prefix(120))"
        )
    }
    let multiplier: Double = match[1] == "KB" ? 1024 : match[1] == "MB" ? 1024 * 1024 : 1024 * 1024 * 1024
    return HostFootprintSourceSample(
        source: HostSource.footprintTool.rawValue,
        attribution: HostSource.footprintTool.attribution,
        bytes: UInt64(value * multiplier),
        status: "sampled"
    )
}

private func vmmapSample(pid: Int32) -> HostFootprintSourceSample {
    let result = runTool("/usr/bin/vmmap", ["-summary", "\(pid)"])
    guard result.exitCode == 0,
          let match = firstMatch(result.stdout, pattern: #"Physical footprint:\s+([0-9.]+)([KMG])"#),
          let value = Double(match[0]) else {
        return HostFootprintSourceSample(
            source: HostSource.vmmapSummary.rawValue,
            attribution: HostSource.vmmapSummary.attribution,
            bytes: nil,
            status: "error",
            note: "vmmap failed: \(result.stderr.prefix(120))"
        )
    }
    let multiplier: Double = match[1] == "K" ? 1024 : match[1] == "M" ? 1024 * 1024 : 1024 * 1024 * 1024
    return HostFootprintSourceSample(
        source: HostSource.vmmapSummary.rawValue,
        attribution: HostSource.vmmapSummary.attribution,
        bytes: UInt64(value * multiplier),
        status: "sampled"
    )
}

private func psSample(pid: Int32) -> HostFootprintSourceSample {
    let result = runTool("/bin/ps", ["-o", "rss=", "-p", "\(pid)"])
    let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.exitCode == 0, let kib = UInt64(text) else {
        return HostFootprintSourceSample(
            source: HostSource.psRSSTree.rawValue,
            attribution: HostSource.psRSSTree.attribution,
            bytes: nil,
            status: "error",
            note: "ps failed: \(result.stderr.prefix(120))"
        )
    }
    return HostFootprintSourceSample(
        source: HostSource.psRSSTree.rawValue,
        attribution: HostSource.psRSSTree.attribution,
        bytes: kib * 1024,
        status: "sampled"
    )
}

private func vmStatSample() -> HostFootprintSourceSample {
    let result = runTool("/usr/bin/vm_stat", [])
    guard result.exitCode == 0,
          let pageSizeMatch = firstMatch(result.stdout, pattern: #"page size of (\d+) bytes"#),
          let pageSize = UInt64(pageSizeMatch[0]),
          let freeMatch = firstMatch(result.stdout, pattern: #"Pages free:\s+(\d+)"#),
          let freePages = UInt64(freeMatch[0]) else {
        return HostFootprintSourceSample(
            source: HostSource.vmStatDelta.rawValue,
            attribution: HostSource.vmStatDelta.attribution,
            bytes: nil,
            status: "error",
            note: "vm_stat failed: \(result.stderr.prefix(120))"
        )
    }
    return HostFootprintSourceSample(
        source: HostSource.vmStatDelta.rawValue,
        attribution: HostSource.vmStatDelta.attribution,
        bytes: freePages * pageSize,
        status: "sampled",
        note: "bytes is free memory; only deltas are meaningful and attribution is system-wide"
    )
}

private struct ToolResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func runTool(_ path: String, _ arguments: [String]) -> ToolResult {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ToolResult(exitCode: -1, stdout: "", stderr: "\(error)")
    }
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    return ToolResult(
        exitCode: process.terminationStatus,
        stdout: String(decoding: outData, as: UTF8.self),
        stderr: String(decoding: errData, as: UTF8.self)
    )
}

private func firstMatch(_ text: String, pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
        return nil
    }
    return (1..<match.numberOfRanges).compactMap { groupIndex in
        guard let groupRange = Range(match.range(at: groupIndex), in: text) else {
            return nil
        }
        return String(text[groupRange])
    }
}

// MARK: - Options and IO

private enum Scenario: String {
    case idlePod = "idle-pod"
    case dbOnly = "db-only"
    case fullStack = "full-stack"
    case scaleTest = "scale-test"
}

private struct HarnessOptions {
    var scenario: Scenario = .idlePod
    var projectName = "phase5-footprint"
    var samples = 3
    var loadRows = 600000
    var evidencePath = ""
    var approvalToken: String?

    static func parse(_ args: [String]) throws -> HarnessOptions {
        var options = HarnessOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--scenario":
                index += 1
                guard index < args.count, let scenario = Scenario(rawValue: args[index]) else {
                    throw HarnessError.usage("--scenario must be idle-pod, db-only, full-stack, or scale-test")
                }
                options.scenario = scenario
            case "--project-name":
                index += 1
                guard index < args.count else {
                    throw HarnessError.usage("--project-name requires a value")
                }
                options.projectName = args[index]
            case "--samples":
                index += 1
                guard index < args.count, let samples = Int(args[index]), samples > 0 else {
                    throw HarnessError.usage("--samples requires a positive integer")
                }
                options.samples = samples
            case "--load-rows":
                index += 1
                guard index < args.count, let rows = Int(args[index]), rows > 0 else {
                    throw HarnessError.usage("--load-rows requires a positive integer")
                }
                options.loadRows = rows
            case "--evidence-jsonl":
                index += 1
                guard index < args.count else {
                    throw HarnessError.usage("--evidence-jsonl requires a path")
                }
                options.evidencePath = args[index]
            case "--approval-token":
                index += 1
                guard index < args.count else {
                    throw HarnessError.usage("--approval-token requires a value")
                }
                options.approvalToken = args[index]
            default:
                throw HarnessError.usage("unknown argument: \(arg)")
            }
            index += 1
        }
        guard !options.evidencePath.isEmpty else {
            throw HarnessError.usage("--evidence-jsonl is required")
        }
        return options
    }
}

private enum HarnessError: Error, CustomStringConvertible {
    case usage(String)
    case runtime(String)

    var description: String {
        switch self {
        case .usage(let message):
            return "usage: \(message)"
        case .runtime(let message):
            return message
        }
    }
}

private func appendJSONLine<T: Encodable>(_ record: T, path: String) throws {
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
