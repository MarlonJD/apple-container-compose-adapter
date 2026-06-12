// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct LinuxPodRuntimeEvent: Codable, Equatable, Sendable {
    public let project: String
    public let order: Int
    public let kind: PlannedActionKind
    public let resourceName: String?
    public let description: String
    public let mutatesRuntime: Bool
    public let metadata: [String: String]
    public let service: ServicePlan?
    public let volume: VolumePlan?

    public init(
        project: String,
        action: PlannedAction,
        service: ServicePlan? = nil,
        volume: VolumePlan? = nil
    ) {
        self.project = project
        self.order = action.order
        self.kind = action.kind
        self.resourceName = action.resourceName
        self.description = action.description
        self.mutatesRuntime = action.mutatesRuntime
        self.metadata = action.metadata
        self.service = service
        self.volume = volume
    }
}

public protocol LinuxPodRuntimeExecuting: Sendable {
    func execute(_ event: LinuxPodRuntimeEvent) async throws -> RuntimeActionResult
}

public struct UnavailableLinuxPodRuntimeExecutor: LinuxPodRuntimeExecuting {
    public init() {}

    public func execute(_ event: LinuxPodRuntimeEvent) async throws -> RuntimeActionResult {
        throw RuntimeBackendError.runtimeUnavailable(
            "No concrete LinuxPod runtime executor is configured for \(event.kind.rawValue)."
        )
    }
}
