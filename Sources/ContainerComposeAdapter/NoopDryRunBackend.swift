// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct NoopDryRunBackend: RuntimeBackend {
    public let kind: RuntimeKind = .noopDryRun
    public let capabilities = RuntimeCapabilities(
        supportsDryRun: true,
        supportsRuntimeMutation: false,
        supportedCommands: [.up, .down, .logs, .status, .run]
    )

    public init() {}

    public func renderDryRun(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions = RuntimeOptions()
    ) throws -> DryRunResult {
        var actions: [PlannedAction] = []
        var order = 1
        for diagnostic in plan.diagnostics {
            actions.append(
                PlannedAction(
                    order: order,
                    kind: .reportDiagnostic,
                    description: diagnostic.message,
                    mutatesRuntime: false,
                    metadata: ["severity": diagnostic.severity.rawValue, "code": diagnostic.code]
                )
            )
            order += 1
        }
        for service in plan.services {
            actions.append(
                PlannedAction(
                    order: order,
                    kind: .renderPlan,
                    resourceName: service.name,
                    description: "Render \(service.kind.rawValue) \(service.name) from image \(service.image).",
                    mutatesRuntime: false,
                    metadata: metadata(for: service)
                )
            )
            order += 1
        }
        if command == .down && options.includeVolumes {
            for volume in plan.volumes {
                actions.append(
                    PlannedAction(
                        order: order,
                        kind: .cleanupNamedVolume,
                        resourceName: volume.name,
                        description: "Would include named volume cleanup in a runtime backend.",
                        mutatesRuntime: false
                    )
                )
                order += 1
            }
        }
        return DryRunResult(
            backend: kind,
            command: command,
            project: plan.project.sanitized,
            approvalRequired: false,
            diagnostics: plan.diagnostics,
            actions: actions
        )
    }

    public func execute(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions = RuntimeOptions(),
        approval: RuntimeApproval = RuntimeApproval()
    ) async throws -> ExecutionResult {
        throw RuntimeBackendError.runtimeUnavailable(
            "NoopDryRunBackend never creates, starts, stops, or deletes runtime resources."
        )
    }

    private func metadata(for service: ServicePlan) -> [String: String] {
        var values: [String: String] = [:]
        if !service.command.isEmpty {
            values["command"] = service.command.joined(separator: " ")
        }
        if !service.environment.isEmpty {
            values["environment"] = service.environment
                .map { "\($0.key)=\($0.redactedValue)" }
                .joined(separator: ",")
        }
        return values
    }
}
