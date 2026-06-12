// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum Stage5BackendSmokeSchema {
    public static let version = "container-compose-adapter/linuxpod-stage5-backend-smoke/v1"
    public static let dryRunRecordType = "linuxpod-stage5-backend-smoke-dry-run"
}

public struct Stage5BackendSmokeEvidenceRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let status: String
    public let runtimeEvidenceStatus: String
    public let projectID: String
    public let runtimeResourceName: String
    public let sourceFiles: [String]
    public let coveredCapabilities: [String]
    public let dryRuns: [DryRunEvidenceRecord]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordType = "record_type"
        case timestamp
        case status
        case runtimeEvidenceStatus = "runtime_evidence_status"
        case projectID = "project_id"
        case runtimeResourceName = "runtime_resource_name"
        case sourceFiles = "source_files"
        case coveredCapabilities = "covered_capabilities"
        case dryRuns = "dry_runs"
    }

    public init(
        timestamp: String,
        projectID: String,
        runtimeResourceName: String,
        sourceFiles: [String],
        coveredCapabilities: [String],
        dryRuns: [DryRunEvidenceRecord]
    ) {
        self.schemaVersion = Stage5BackendSmokeSchema.version
        self.recordType = Stage5BackendSmokeSchema.dryRunRecordType
        self.timestamp = timestamp
        self.status = "planned-dry-run-no-runtime-mutation"
        self.runtimeEvidenceStatus = "not-run-runtime-approval-unavailable"
        self.projectID = projectID
        self.runtimeResourceName = runtimeResourceName
        self.sourceFiles = sourceFiles
        self.coveredCapabilities = coveredCapabilities
        self.dryRuns = dryRuns
    }
}

public struct Stage5BackendSmokeHarness: Sendable {
    public static let coveredCapabilities = [
        "postgres-service",
        "db-data-named-volume",
        "migrate-job",
        "seed-job",
        "api-service",
        "service-readiness-healthchecks",
        "logs-surface",
        "status-surface",
        "run-surface",
        "deterministic-host-port",
        "service-dns-managed-hosts",
        "cleanup-proof"
    ]

    public let stateStore: LinuxPodStateStore
    public let frontend: ComposeFrontend

    public init(
        stateStore: LinuxPodStateStore = LinuxPodStateStore(),
        frontend: ComposeFrontend = ComposeFrontend()
    ) {
        self.stateStore = stateStore
        self.frontend = frontend
    }

    public func buildDryRunEvidence(
        composeFile: URL,
        projectName: String,
        timestamp: String
    ) throws -> Stage5BackendSmokeEvidenceRecord {
        let frontendResult = try frontend.parseProject(fileURL: composeFile, projectName: projectName)
        let plannerResult = AppleNativePlanner().plan(frontendResult.project)
        let plan = plannerResult.runtimePlan
        let backend = LinuxPodBackend(stateStore: stateStore)
        let commands: [(AdapterCommand, RuntimeOptions)] = [
            (.up, RuntimeOptions()),
            (.logs, RuntimeOptions()),
            (.status, RuntimeOptions()),
            (.run, RuntimeOptions()),
            (.down, RuntimeOptions(includeVolumes: true))
        ]
        let dryRuns = try commands.map { command, options in
            let dryRun = try backend.renderDryRun(command: command, plan: plan, options: options)
            return DryRunEvidenceRecord(timestamp: timestamp, dryRun: dryRun)
        }
        return Stage5BackendSmokeEvidenceRecord(
            timestamp: timestamp,
            projectID: frontendResult.project.id,
            runtimeResourceName: stateStore.projectName(for: plan.project),
            sourceFiles: frontendResult.project.sourceFiles,
            coveredCapabilities: Self.coveredCapabilities,
            dryRuns: dryRuns
        )
    }
}

public struct Stage5BackendSmokeEvidenceValidator: Sendable {
    public init() {}

    public func validate(_ record: Stage5BackendSmokeEvidenceRecord) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        require(
            record.schemaVersion == Stage5BackendSmokeSchema.version,
            field: "schema_version",
            diagnostics: &diagnostics
        )
        require(
            record.recordType == Stage5BackendSmokeSchema.dryRunRecordType,
            field: "record_type",
            diagnostics: &diagnostics
        )
        require(
            record.status == "planned-dry-run-no-runtime-mutation",
            field: "status",
            diagnostics: &diagnostics
        )
        require(
            record.runtimeEvidenceStatus == "not-run-runtime-approval-unavailable",
            field: "runtime_evidence_status",
            diagnostics: &diagnostics
        )
        require(!record.sourceFiles.isEmpty, field: "source_files", diagnostics: &diagnostics)
        require(
            record.coveredCapabilities == Stage5BackendSmokeHarness.coveredCapabilities,
            field: "covered_capabilities",
            diagnostics: &diagnostics
        )
        require(
            record.dryRuns.map(\.command) == [.up, .logs, .status, .run, .down],
            field: "dry_runs.commands",
            diagnostics: &diagnostics
        )

        guard diagnostics.isEmpty else {
            return diagnostics
        }

        let dryRuns = Dictionary(uniqueKeysWithValues: record.dryRuns.map { ($0.command, $0) })
        if let up = dryRuns[.up] {
            validateUp(up, runtimeResourceName: record.runtimeResourceName, diagnostics: &diagnostics)
        }
        if let logs = dryRuns[.logs] {
            validateLogs(logs, diagnostics: &diagnostics)
        }
        if let status = dryRuns[.status] {
            validateStatus(status, diagnostics: &diagnostics)
        }
        if let run = dryRuns[.run] {
            validateRun(run, runtimeResourceName: record.runtimeResourceName, diagnostics: &diagnostics)
        }
        if let down = dryRuns[.down] {
            validateDown(down, diagnostics: &diagnostics)
        }
        return diagnostics
    }

    public func validate(evidenceURL: URL) throws -> [Diagnostic] {
        let content = try String(contentsOf: evidenceURL, encoding: .utf8)
        let lines = content.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else {
            return [invalid("evidence_jsonl", "Write at least one Stage 5 backend smoke record.")]
        }
        let decoder = JSONDecoder()
        return try lines.enumerated().flatMap { index, line in
            let record = try decoder.decode(Stage5BackendSmokeEvidenceRecord.self, from: Data(line.utf8))
            var diagnostics = validate(record)
            if lines.count != 1 {
                diagnostics.append(invalid("evidence_jsonl[\(index)]", "Write exactly one Stage 5 dry-run evidence record."))
            }
            return diagnostics
        }
    }

    private func validateUp(
        _ evidence: DryRunEvidenceRecord,
        runtimeResourceName: String,
        diagnostics: inout [Diagnostic]
    ) {
        let dryRun = evidence.dryRun
        require(evidence.approvalRequired, field: "up.approval_required", diagnostics: &diagnostics)
        require(
            dryRun.project == runtimeResourceName,
            field: "up.project",
            diagnostics: &diagnostics
        )
        require(
            dryRun.actions.first { $0.kind == .createProjectRuntime }?.metadata["hosts"] == "127.0.0.1 db migrate seed api",
            field: "up.managed_hosts",
            diagnostics: &diagnostics
        )
        require(
            dryRun.actions.contains { $0.kind == .createNamedVolume && $0.resourceName == "db-data" },
            field: "up.db_data_named_volume",
            diagnostics: &diagnostics
        )
        require(
            dryRun.actions.contains {
                $0.kind == .addContainer
                    && $0.resourceName == "\(runtimeResourceName)-db"
                    && $0.metadata["image"] == "docker.io/library/postgres:16-alpine"
                    && $0.metadata["ports"] == "15432:5432/tcp"
            },
            field: "up.postgres",
            diagnostics: &diagnostics
        )
        require(
            dryRun.actions.contains {
                $0.kind == .addContainer
                    && $0.resourceName == "\(runtimeResourceName)-api"
                    && $0.metadata["ports"] == "18081:8080/tcp"
            },
            field: "up.api",
            diagnostics: &diagnostics
        )
        for service in ["db", "migrate", "seed", "api"] {
            require(
                dryRun.actions.contains { $0.kind == .waitForReadiness && $0.resourceName == service },
                field: "up.readiness.\(service)",
                diagnostics: &diagnostics
            )
        }
        require(!dryRun.renderText().contains("dev_password"), field: "up.redaction", diagnostics: &diagnostics)
    }

    private func validateLogs(_ evidence: DryRunEvidenceRecord, diagnostics: inout [Diagnostic]) {
        require(!evidence.approvalRequired, field: "logs.approval_required", diagnostics: &diagnostics)
        require(
            evidence.dryRun.actions.filter { $0.kind == .collectLogs }.count == 4,
            field: "logs.collect_logs",
            diagnostics: &diagnostics
        )
    }

    private func validateStatus(_ evidence: DryRunEvidenceRecord, diagnostics: inout [Diagnostic]) {
        require(!evidence.approvalRequired, field: "status.approval_required", diagnostics: &diagnostics)
        require(
            evidence.dryRun.actions.first?.metadata["services"] == "db,migrate,seed,api",
            field: "status.services",
            diagnostics: &diagnostics
        )
    }

    private func validateRun(
        _ evidence: DryRunEvidenceRecord,
        runtimeResourceName: String,
        diagnostics: inout [Diagnostic]
    ) {
        require(evidence.approvalRequired, field: "run.approval_required", diagnostics: &diagnostics)
        require(
            evidence.dryRun.actions.contains { $0.kind == .runJob && $0.resourceName == "\(runtimeResourceName)-migrate" },
            field: "run.migrate",
            diagnostics: &diagnostics
        )
        require(
            evidence.dryRun.actions.contains { $0.kind == .runJob && $0.resourceName == "\(runtimeResourceName)-seed" },
            field: "run.seed",
            diagnostics: &diagnostics
        )
        require(
            !evidence.dryRun.actions.contains { $0.resourceName == "\(runtimeResourceName)-api" },
            field: "run.api_excluded",
            diagnostics: &diagnostics
        )
    }

    private func validateDown(_ evidence: DryRunEvidenceRecord, diagnostics: inout [Diagnostic]) {
        require(evidence.approvalRequired, field: "down.approval_required", diagnostics: &diagnostics)
        require(
            evidence.dryRun.actions.contains { $0.kind == .stopProjectRuntime },
            field: "down.stop_runtime",
            diagnostics: &diagnostics
        )
        require(
            evidence.dryRun.actions.contains { $0.kind == .deleteProjectRuntime },
            field: "down.delete_runtime",
            diagnostics: &diagnostics
        )
        require(
            evidence.dryRun.actions.contains { $0.kind == .cleanupNamedVolume && $0.resourceName == "db-data" },
            field: "down.cleanup_db_data",
            diagnostics: &diagnostics
        )
        require(evidence.cleanupProof.runtimeMutation == "not-run", field: "down.cleanup.runtime_mutation", diagnostics: &diagnostics)
        require(evidence.cleanupProof.runtimeCleanup == "planned-only", field: "down.cleanup.runtime", diagnostics: &diagnostics)
        require(evidence.cleanupProof.volumeCleanup == "planned-only", field: "down.cleanup.volume", diagnostics: &diagnostics)
        require(evidence.cleanupProof.portCleanup == "planned-release", field: "down.cleanup.port", diagnostics: &diagnostics)
    }

    private func require(_ condition: Bool, field: String, diagnostics: inout [Diagnostic]) {
        guard !condition else {
            return
        }
        diagnostics.append(invalid(field, "Regenerate Stage 5 dry-run evidence from the backend-shaped fixture."))
    }

    private func invalid(_ field: String, _ suggestion: String) -> Diagnostic {
        Diagnostic(
            severity: .blocking,
            code: "invalid-stage5-backend-smoke-evidence",
            message: "Stage 5 backend smoke evidence is missing or invalid at \(field).",
            suggestion: suggestion
        )
    }
}

public struct Stage5BackendSmokeJSONLWriter: Sendable {
    public init() {}

    public func write(_ record: Stage5BackendSmokeEvidenceRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(record)
        data.append(0x0A)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

public struct Stage5BackendSmokeCommandResult: Equatable, Sendable {
    public let record: Stage5BackendSmokeEvidenceRecord
    public let validationDiagnostics: [Diagnostic]

    public init(record: Stage5BackendSmokeEvidenceRecord, validationDiagnostics: [Diagnostic]) {
        self.record = record
        self.validationDiagnostics = validationDiagnostics
    }
}

public struct Stage5BackendSmokeCommandRunner: Sendable {
    public init() {}

    public func run(options: Stage5BackendSmokeCommandOptions) throws -> Stage5BackendSmokeCommandResult {
        let timestamp = options.timestamp ?? Self.iso8601Now()
        let stateStore = LinuxPodStateStore(root: options.storeRoot.fileURL)
        let record = try Stage5BackendSmokeHarness(stateStore: stateStore).buildDryRunEvidence(
            composeFile: options.composeFile.fileURL,
            projectName: options.projectName,
            timestamp: timestamp
        )
        try Stage5BackendSmokeJSONLWriter().write(record, to: options.evidenceJSONL.fileURL)

        var diagnostics: [Diagnostic] = []
        if options.validateEvidence {
            diagnostics = try Stage5BackendSmokeEvidenceValidator().validate(evidenceURL: options.evidenceJSONL.fileURL)
            guard diagnostics.isEmpty else {
                throw Stage5BackendSmokeCommandError.evidenceValidationFailed(diagnostics)
            }
        }
        return Stage5BackendSmokeCommandResult(record: record, validationDiagnostics: diagnostics)
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

public struct Stage5BackendSmokeCommandOptions: Equatable, Sendable {
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
    public let validateEvidence: Bool
    public let storeRoot: Path

    public init(
        composeFile: Path,
        projectName: String,
        timestamp: String?,
        evidenceJSONL: Path,
        validateEvidence: Bool = false,
        storeRoot: Path
    ) {
        self.composeFile = composeFile
        self.projectName = projectName
        self.timestamp = timestamp
        self.evidenceJSONL = evidenceJSONL
        self.validateEvidence = validateEvidence
        self.storeRoot = storeRoot
    }

    public static func parse(_ args: [String]) throws -> Stage5BackendSmokeCommandOptions {
        var composeFile: String?
        var projectName: String?
        var timestamp: String?
        var evidenceJSONL: String?
        var validateEvidence = false
        var storeRoot = "/tmp/container-compose-stage5-backend-smoke"

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
            case "--validate-evidence":
                validateEvidence = true
            case "--store-root":
                storeRoot = try value(after: arg, args: args, index: &index)
            case "--approval-token":
                throw Stage5BackendSmokeCommandError.runtimeApprovalNotAccepted
            case "-h", "--help":
                throw Stage5BackendSmokeCommandError.helpRequested
            default:
                throw Stage5BackendSmokeCommandError.unknownArgument(arg)
            }
            index += 1
        }

        guard let composeFile, !composeFile.isEmpty else {
            throw Stage5BackendSmokeCommandError.missingRequiredArgument("--compose-file")
        }
        guard let projectName, !projectName.isEmpty else {
            throw Stage5BackendSmokeCommandError.missingRequiredArgument("--project-name")
        }
        guard let evidenceJSONL, !evidenceJSONL.isEmpty else {
            throw Stage5BackendSmokeCommandError.missingRequiredArgument("--evidence-jsonl")
        }
        return Stage5BackendSmokeCommandOptions(
            composeFile: Path(composeFile),
            projectName: projectName,
            timestamp: timestamp,
            evidenceJSONL: Path(evidenceJSONL),
            validateEvidence: validateEvidence,
            storeRoot: Path(storeRoot)
        )
    }

    private static func value(after flag: String, args: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < args.count else {
            throw Stage5BackendSmokeCommandError.missingValue(flag)
        }
        let value = args[valueIndex]
        guard !value.hasPrefix("--") else {
            throw Stage5BackendSmokeCommandError.missingValue(flag)
        }
        index = valueIndex
        return value
    }
}

public enum Stage5BackendSmokeCommandError: Error, Equatable, CustomStringConvertible {
    case missingRequiredArgument(String)
    case missingValue(String)
    case unknownArgument(String)
    case runtimeApprovalNotAccepted
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
            return "Stage 5 backend smoke evidence is no-runtime only and does not accept runtime approval tokens."
        case .evidenceValidationFailed(let diagnostics):
            let codes = diagnostics.map(\.code).joined(separator: ", ")
            return "Stage 5 backend smoke evidence validation failed: \(codes)."
        case .helpRequested:
            return Stage5BackendSmokeCommandHelp.text
        }
    }
}

public enum Stage5BackendSmokeCommandHelp {
    public static let text = """
    Usage: container-compose-stage5-backend-smoke \\
      --compose-file <path> \\
      --project-name <name> \\
      --evidence-jsonl <path> \\
      [--validate-evidence] \\
      [--timestamp <iso8601>] \\
      [--store-root <path>]

    Emits Stage 5 backend-shaped product smoke dry-run JSONL without runtime mutation.
    Runtime approval tokens are rejected by this no-runtime evidence command.
    """
}
