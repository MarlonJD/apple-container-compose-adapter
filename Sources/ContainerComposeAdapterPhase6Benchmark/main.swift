// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import ContainerComposeAdapterLinuxPod
import Foundation

@main
struct Phase6BenchmarkHarness {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(64)
        }
    }

    private static func run(_ options: Options) async throws {
        guard options.approvalToken == LinuxPodBackend.runtimeApprovalToken else {
            throw HarnessError.usage(
                "Phase 6 LinuxPod benchmark requires --approval-token \(LinuxPodBackend.runtimeApprovalToken)"
            )
        }
        let approval = RuntimeApproval(approved: true, token: options.approvalToken)
        let executor = ContainerizationLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        var records: [Phase6BenchmarkIterationRecord] = []

        for iteration in 1...options.iterations {
            let projectName = "\(options.projectPrefix)-\(options.runLabel)-\(String(format: "%03d", iteration))"
            let plan = SamplePlans.publicBackendShaped(project: ProjectName(projectName))
            let projectResource = backend.stateStore.projectName(for: plan.project)
            let projectDirectory = backend.stateStore.projectDirectory(for: plan.project)
            let environment = benchmarkEnvironment(
                options: options,
                plan: plan,
                backend: backend,
                projectDirectory: projectDirectory
            )

            FileHandle.standardError.write(Data("phase6-benchmark: \(options.runLabel) iteration \(iteration)/\(options.iterations) up\n".utf8))
            let record = await runIteration(
                iteration: iteration,
                runLabel: options.runLabel,
                environment: environment,
                plan: plan,
                projectResource: projectResource,
                projectDirectory: projectDirectory,
                backend: backend,
                executor: executor,
                approval: approval
            )
            try appendJSONLine(record, path: options.evidencePath)
            records.append(record)
        }

        let summary = Phase6BenchmarkSummaryRecord(
            timestamp: iso8601Now(),
            projectPrefix: options.projectPrefix,
            runLabel: options.runLabel,
            requestedIterations: options.iterations,
            records: records
        )
        try appendJSONLine(summary, path: options.evidencePath)
        print("phase6-benchmark: completed \(options.iterations) iteration(s); evidence at \(options.evidencePath ?? "")")
    }

    private static func runIteration(
        iteration: Int,
        runLabel: String,
        environment: BenchmarkRunMetadata,
        plan: RuntimePlan,
        projectResource: String,
        projectDirectory: URL,
        backend: LinuxPodBackend,
        executor: ContainerizationLinuxPodRuntimeExecutor,
        approval: RuntimeApproval
    ) async -> Phase6BenchmarkIterationRecord {
        var upDuration: Double?
        var statusDuration: Double?
        var logsDuration: Double?
        var cleanupDuration: Double?
        var guest: HostFootprintGuestStats?
        var actionCount = 0

        do {
            let upStarted = Date()
            let up = try await backend.execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(),
                approval: approval
            )
            upDuration = elapsedSeconds(since: upStarted)
            actionCount += up.actionResults.count

            guest = try await executor.guestStatistics(project: projectResource)

            let statusStarted = Date()
            let status = try await backend.execute(
                command: .status,
                plan: plan,
                options: RuntimeOptions(),
                approval: RuntimeApproval()
            )
            statusDuration = elapsedSeconds(since: statusStarted)
            actionCount += status.actionResults.count

            let logsStarted = Date()
            let logs = try await backend.execute(
                command: .logs,
                plan: plan,
                options: RuntimeOptions(),
                approval: RuntimeApproval()
            )
            logsDuration = elapsedSeconds(since: logsStarted)
            actionCount += logs.actionResults.count

            let cleanupStarted = Date()
            let cleanup = try await backend.execute(
                command: .down,
                plan: plan,
                options: RuntimeOptions(includeVolumes: true),
                approval: approval
            )
            cleanupDuration = elapsedSeconds(since: cleanupStarted)
            actionCount += cleanup.actionResults.count

            return Phase6BenchmarkIterationRecord(
                timestamp: iso8601Now(),
                project: projectResource,
                runLabel: runLabel,
                iteration: iteration,
                environment: environment,
                status: .measured,
                durationsSeconds: Phase6BenchmarkDurations(
                    up: upDuration,
                    status: statusDuration,
                    logs: logsDuration,
                    cleanup: cleanupDuration
                ),
                guest: guest,
                hostPhysicalMemoryStatus: .blocked,
                actionCount: actionCount,
                cleanupStateDirectoryExistsAfterCleanup: FileManager.default.fileExists(atPath: projectDirectory.path),
                failure: nil
            )
        } catch {
            let cleanupStarted = Date()
            if let cleanup = try? await backend.execute(
                command: .down,
                plan: plan,
                options: RuntimeOptions(includeVolumes: true),
                approval: approval
            ) {
                actionCount += cleanup.actionResults.count
            }
            cleanupDuration = elapsedSeconds(since: cleanupStarted)
            return Phase6BenchmarkIterationRecord(
                timestamp: iso8601Now(),
                project: projectResource,
                runLabel: runLabel,
                iteration: iteration,
                environment: environment,
                status: .failed,
                durationsSeconds: Phase6BenchmarkDurations(
                    up: upDuration,
                    status: statusDuration,
                    logs: logsDuration,
                    cleanup: cleanupDuration
                ),
                guest: guest,
                hostPhysicalMemoryStatus: .blocked,
                actionCount: actionCount,
                cleanupStateDirectoryExistsAfterCleanup: FileManager.default.fileExists(atPath: projectDirectory.path),
                failure: "\(error)"
            )
        }
    }
}

private struct Options {
    var iterations = 1
    var projectPrefix = "phase6-backend"
    var runLabel = "phase6-smoke"
    var lifecycle: BenchmarkLifecycle = .warm
    var evidencePath: String?
    var approvalToken: String?

    static func parse(_ args: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--iterations":
                index += 1
                guard index < args.count, let iterations = Int(args[index]), iterations > 0 else {
                    throw HarnessError.usage("--iterations requires a positive integer")
                }
                options.iterations = iterations
            case "--project-prefix":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw HarnessError.usage("--project-prefix requires a value")
                }
                options.projectPrefix = args[index]
            case "--run-label":
                index += 1
                guard index < args.count, !args[index].isEmpty else {
                    throw HarnessError.usage("--run-label requires a value")
                }
                options.runLabel = args[index]
            case "--lifecycle":
                index += 1
                guard index < args.count, let lifecycle = BenchmarkLifecycle(rawValue: args[index]) else {
                    throw HarnessError.usage("--lifecycle must be cold or warm")
                }
                options.lifecycle = lifecycle
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
            case "--help", "-h":
                throw HarnessError.usage(Self.usage())
            default:
                throw HarnessError.usage("unknown argument: \(arg)\n\n\(Self.usage())")
            }
            index += 1
        }
        guard options.evidencePath != nil else {
            throw HarnessError.usage("--evidence-jsonl is required")
        }
        return options
    }

    static func usage() -> String {
        """
        Usage: container-compose-phase6-benchmark --evidence-jsonl path --approval-token token [--iterations n] [--project-prefix name] [--run-label label] [--lifecycle cold|warm]
        """
    }
}

private enum HarnessError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

private func appendJSONLine<T: Encodable>(_ record: T, path: String?) throws {
    guard let path else {
        throw HarnessError.usage("--evidence-jsonl is required")
    }
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

private func elapsedSeconds(since start: Date) -> Double {
    Date().timeIntervalSince(start)
}

private func benchmarkEnvironment(
    options: Options,
    plan: RuntimePlan,
    backend: LinuxPodBackend,
    projectDirectory: URL
) -> BenchmarkRunMetadata {
    let imageStatuses = plan.services.map { service in
        cacheStatus(path: backend.stateStore.rootfsPath(project: plan.project, image: service.image).path)
    }
    let rootfsStatus = combinedCacheStatus(imageStatuses)
    let volumeStatuses = plan.volumes.map { volume in
        FileManager.default.fileExists(atPath: backend.stateStore.volumePath(project: plan.project, volume: volume).path)
    }
    let runtimeDirectory = backend.stateStore.runtimeDirectory(for: plan.project)
    return BenchmarkRunMetadata(
        runtime: .linuxpod,
        targetName: options.lifecycle == .warm ? "future LinuxPod warm" : "current LinuxPod cold",
        runtimeVersion: "apple/containerization LinuxPod",
        containerizationVersion: ContainerizationLinuxPodRuntimeExecutor.containerizationVersion,
        appleContainerCLIVersion: nil,
        macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        hostArchitecture: hostArchitecture(),
        lifecycle: options.lifecycle,
        projectRuntimeExistedBeforeRun: FileManager.default.fileExists(atPath: runtimeDirectory.path),
        imageCacheStatus: .unknown,
        rootfsCacheStatus: rootfsStatus,
        initfsCacheStatus: cacheStatus(path: runtimeDirectory.appendingPathComponent("initfs.ext4").path),
        volumeExistedBeforeRun: volumeStatuses.contains(true)
    )
}

private func cacheStatus(path: String) -> BenchmarkCacheStatus {
    FileManager.default.fileExists(atPath: path) ? .hit : .miss
}

private func combinedCacheStatus(_ statuses: [BenchmarkCacheStatus]) -> BenchmarkCacheStatus {
    guard !statuses.isEmpty else {
        return .unknown
    }
    return statuses.allSatisfy { $0 == .hit } ? .hit : .miss
}

private func hostArchitecture() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}
