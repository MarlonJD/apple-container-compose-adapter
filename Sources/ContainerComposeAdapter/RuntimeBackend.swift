// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct RuntimeCapabilities: Codable, Equatable, Sendable {
    public let supportsDryRun: Bool
    public let supportsRuntimeMutation: Bool
    public let supportedCommands: [AdapterCommand]

    public init(
        supportsDryRun: Bool,
        supportsRuntimeMutation: Bool,
        supportedCommands: [AdapterCommand]
    ) {
        self.supportsDryRun = supportsDryRun
        self.supportsRuntimeMutation = supportsRuntimeMutation
        self.supportedCommands = supportedCommands
    }
}

public struct RuntimeApproval: Codable, Equatable, Sendable {
    public let approved: Bool
    public let token: String?

    public init(approved: Bool = false, token: String? = nil) {
        self.approved = approved
        self.token = token
    }
}

public struct DryRunResult: Codable, Equatable, Sendable {
    public let backend: RuntimeKind
    public let command: AdapterCommand
    public let project: String
    public let approvalRequired: Bool
    public let diagnostics: [Diagnostic]
    public let actions: [PlannedAction]

    public init(
        backend: RuntimeKind,
        command: AdapterCommand,
        project: String,
        approvalRequired: Bool,
        diagnostics: [Diagnostic],
        actions: [PlannedAction]
    ) {
        self.backend = backend
        self.command = command
        self.project = project
        self.approvalRequired = approvalRequired
        self.diagnostics = diagnostics
        self.actions = actions
    }

    public var mutatingActionCount: Int {
        actions.filter(\.mutatesRuntime).count
    }

    public func renderText() -> String {
        var lines: [String] = [
            "Container Compose Adapter dry run",
            "backend: \(backend.rawValue)",
            "command: \(command.rawValue)",
            "project: \(project)",
            "approval required: \(approvalRequired ? "yes" : "no")"
        ]
        if !diagnostics.isEmpty {
            lines.append("diagnostics:")
            for diagnostic in diagnostics {
                lines.append("- [\(diagnostic.severity.rawValue)] \(diagnostic.code): \(diagnostic.message)")
                if let suggestion = diagnostic.suggestion {
                    lines.append("  suggestion: \(suggestion)")
                }
            }
        }
        lines.append("actions:")
        for action in actions.sorted(by: { $0.order < $1.order }) {
            let mutation = action.mutatesRuntime ? "mutates" : "no-side-effect"
            if let resource = action.resourceName {
                lines.append("\(action.order). \(action.kind.rawValue) [\(mutation)] \(resource): \(action.description)")
            } else {
                lines.append("\(action.order). \(action.kind.rawValue) [\(mutation)]: \(action.description)")
            }
            for key in action.metadata.keys.sorted() {
                lines.append("   \(key)=\(action.metadata[key] ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public struct RuntimeActionResult: Codable, Equatable, Sendable {
    public let order: Int
    public let kind: PlannedActionKind
    public let resourceName: String?
    public let status: String
    public let metadata: [String: String]

    public init(
        order: Int,
        kind: PlannedActionKind,
        resourceName: String?,
        status: String,
        metadata: [String: String] = [:]
    ) {
        self.order = order
        self.kind = kind
        self.resourceName = resourceName
        self.status = status
        self.metadata = metadata
    }
}

public struct ExecutionResult: Codable, Equatable, Sendable {
    public let backend: RuntimeKind
    public let command: AdapterCommand
    public let status: String
    public let diagnostics: [Diagnostic]
    public let actionResults: [RuntimeActionResult]

    public init(
        backend: RuntimeKind,
        command: AdapterCommand,
        status: String,
        diagnostics: [Diagnostic] = [],
        actionResults: [RuntimeActionResult] = []
    ) {
        self.backend = backend
        self.command = command
        self.status = status
        self.diagnostics = diagnostics
        self.actionResults = actionResults
    }

    public func renderText() -> String {
        var lines: [String] = [
            "Container Compose Adapter execution",
            "backend: \(backend.rawValue)",
            "command: \(command.rawValue)",
            "status: \(status)"
        ]
        if !diagnostics.isEmpty {
            lines.append("diagnostics:")
            for diagnostic in diagnostics {
                lines.append("- [\(diagnostic.severity.rawValue)] \(diagnostic.code): \(diagnostic.message)")
                if let suggestion = diagnostic.suggestion {
                    lines.append("  suggestion: \(suggestion)")
                }
            }
        }
        if !actionResults.isEmpty {
            lines.append("actions:")
            for result in actionResults.sorted(by: { $0.order < $1.order }) {
                if let resource = result.resourceName {
                    lines.append("\(result.order). \(result.kind.rawValue) [\(result.status)] \(resource)")
                } else {
                    lines.append("\(result.order). \(result.kind.rawValue) [\(result.status)]")
                }
                for key in result.metadata.keys.sorted() {
                    lines.append("   \(key)=\(result.metadata[key] ?? "")")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum RuntimeBackendError: Error, Equatable, CustomStringConvertible, Sendable {
    case blockingDiagnostics([Diagnostic])
    case runtimeMutationRequiresApproval(String)
    case runtimeUnavailable(String)
    case unsupportedCommand(AdapterCommand)

    public var description: String {
        switch self {
        case .blockingDiagnostics(let diagnostics):
            let codes = diagnostics.map(\.code).joined(separator: ", ")
            return "blocking diagnostics prevent runtime execution: \(codes)"
        case .runtimeMutationRequiresApproval(let message):
            return message
        case .runtimeUnavailable(let message):
            return message
        case .unsupportedCommand(let command):
            return "unsupported command for backend: \(command.rawValue)"
        }
    }
}

public protocol RuntimeBackend: Sendable {
    var kind: RuntimeKind { get }
    var capabilities: RuntimeCapabilities { get }

    func renderDryRun(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions
    ) throws -> DryRunResult

    func execute(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions,
        approval: RuntimeApproval
    ) async throws -> ExecutionResult
}
