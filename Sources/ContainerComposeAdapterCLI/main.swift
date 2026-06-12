// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import ContainerComposeAdapter
import ContainerComposeAdapterLinuxPod
import Foundation

@main
struct ContainerComposeAdapterCommand {
    static func main() async {
        do {
            let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            Foundation.exit(64)
        }
    }

    private static func run(_ options: CLIOptions) async throws {
        if options.command == .doctor {
            print("Container Compose Adapter doctor")
            print("runtime: \(options.runtime.rawValue)")
            print("runtime mutation: requires explicit approval")
            if options.runtime == .linuxpod {
                let entitlementStatus = ContainerizationLinuxPodRuntimeExecutor.currentProcessHasVirtualizationEntitlement()
                    ? "present"
                    : "missing"
                print("virtualization entitlement: \(entitlementStatus)")
                if entitlementStatus == "missing" {
                    print("suggestion: run scripts/sign-debug-runtime.sh and execute the signed binary instead of swift run")
                }
            }
            return
        }

        guard let command = AdapterCommand(rawValue: options.command.rawValue) else {
            throw CLIError.usage("unsupported command: \(options.command.rawValue)")
        }
        let plan = try makePlan(options)
        let backend: any RuntimeBackend = options.runtime == .linuxpod
            ? LinuxPodBackend(runtimeExecutor: ContainerizationLinuxPodRuntimeExecutor())
            : NoopDryRunBackend()
        let runtimeOptions = RuntimeOptions(includeVolumes: options.includeVolumes)

        if options.dryRun {
            let result = try backend.renderDryRun(command: command, plan: plan, options: runtimeOptions)
            if let evidencePath = options.evidenceJSONL {
                try writeEvidence(result, path: evidencePath)
            }
            if options.format == .json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                print(result.renderText())
            }
            return
        }

        let executionDryRun = try options.evidenceJSONL.map { _ in
            try backend.renderDryRun(command: command, plan: plan, options: runtimeOptions)
        }
        let approval = RuntimeApproval(
            approved: options.approvalToken == LinuxPodBackend.runtimeApprovalToken,
            token: options.approvalToken
        )
        let result = try await backend.execute(
            command: command,
            plan: plan,
            options: runtimeOptions,
            approval: approval
        )
        if let evidencePath = options.evidenceJSONL, let executionDryRun {
            try writeEvidence(result, dryRun: executionDryRun, path: evidencePath)
        }
        if options.format == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            print(String(data: data, encoding: .utf8) ?? "")
        } else {
            print(result.renderText())
        }
    }

    private static func makePlan(_ options: CLIOptions) throws -> RuntimePlan {
        guard let composeFile = options.composeFile else {
            let sample = options.samplePlan ?? .publicSmoke
            return sample.makePlan(project: ProjectName(options.projectName))
        }
        let frontendResult = try ComposeFrontend().parseProject(
            fileURL: URL(fileURLWithPath: composeFile),
            projectName: options.projectName
        )
        return AppleNativePlanner().plan(frontendResult.project).runtimePlan
    }
}

private struct CLIOptions {
    var runtime: RuntimeKind = .noopDryRun
    var command: CLICommand = .doctor
    var dryRun = false
    var projectName = "linuxpod-smoke"
    var includeVolumes = false
    var format: OutputFormat = .text
    var approvalToken: String?
    var evidenceJSONL: String?
    var samplePlan: SamplePlanKind?
    var composeFile: String?

    static func parse(_ args: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--runtime":
                index += 1
                guard index < args.count, let runtime = RuntimeKind(rawValue: args[index]) else {
                    throw CLIError.usage("--runtime must be noop-dry-run or linuxpod")
                }
                options.runtime = runtime
            case "--dry-run":
                options.dryRun = true
            case "--project-name", "-p":
                index += 1
                guard index < args.count else {
                    throw CLIError.usage("\(arg) requires a value")
                }
                options.projectName = args[index]
            case "--format":
                index += 1
                guard index < args.count, let format = OutputFormat(rawValue: args[index]) else {
                    throw CLIError.usage("--format must be text or json")
                }
                options.format = format
            case "--volumes":
                options.includeVolumes = true
            case "--approval-token":
                index += 1
                guard index < args.count else {
                    throw CLIError.usage("--approval-token requires a value")
                }
                options.approvalToken = args[index]
            case "--evidence-jsonl":
                index += 1
                guard index < args.count else {
                    throw CLIError.usage("--evidence-jsonl requires a path")
                }
                options.evidenceJSONL = args[index]
            case "--sample":
                index += 1
                guard index < args.count, let sample = SamplePlanKind(rawValue: args[index]) else {
                    throw CLIError.usage("--sample must be public-smoke or backend-shaped")
                }
                options.samplePlan = sample
            case "--compose-file":
                index += 1
                guard index < args.count else {
                    throw CLIError.usage("--compose-file requires a path")
                }
                options.composeFile = args[index]
            case "--help", "-h":
                throw CLIError.usage(Self.usage())
            default:
                guard let command = CLICommand(rawValue: arg) else {
                    throw CLIError.usage("unknown argument: \(arg)\n\n\(Self.usage())")
                }
                options.command = command
            }
            index += 1
        }
        guard options.composeFile == nil || options.samplePlan == nil else {
            throw CLIError.usage("--compose-file and --sample are mutually exclusive")
        }
        return options
    }

    static func usage() -> String {
        """
        Usage: container-compose-adapter [--runtime noop-dry-run|linuxpod] [--dry-run] [-p name] [--sample public-smoke|backend-shaped] [--compose-file path] [--format text|json] [--evidence-jsonl path] <doctor|up|down|logs|status|run>
        """
    }
}

private func writeEvidence(_ result: DryRunResult, path: String) throws {
    let record = DryRunEvidenceRecord(timestamp: iso8601Now(), dryRun: result)
    try appendJSONLine(record, path: path)
}

private func writeEvidence(_ result: ExecutionResult, dryRun: DryRunResult, path: String) throws {
    let record = RuntimeExecutionEvidenceRecord(timestamp: iso8601Now(), dryRun: dryRun, execution: result)
    try appendJSONLine(record, path: path)
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

private enum OutputFormat: String {
    case text
    case json
}

private enum SamplePlanKind: String {
    case publicSmoke = "public-smoke"
    case backendShaped = "backend-shaped"

    func makePlan(project: ProjectName) -> RuntimePlan {
        switch self {
        case .publicSmoke:
            return SamplePlans.publicImageSmoke(project: project)
        case .backendShaped:
            return SamplePlans.publicBackendShaped(project: project)
        }
    }
}

private enum CLICommand: String {
    case doctor
    case up
    case down
    case logs
    case status
    case run
}

private enum CLIError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}
