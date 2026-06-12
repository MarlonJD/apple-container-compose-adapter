// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum RuntimeKind: String, Codable, Equatable, Sendable {
    case noopDryRun = "noop-dry-run"
    case linuxpod
}

public enum AdapterCommand: String, Codable, Equatable, Sendable {
    case up
    case down
    case logs
    case status
    case run
}

public struct ProjectName: Codable, Equatable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var sanitized: String {
        let lowered = rawValue.lowercased()
        var result = ""
        var previousWasDash = false
        for scalar in lowered.unicodeScalars {
            let isAllowed = CharacterSet.alphanumerics.contains(scalar)
            if isAllowed {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    public func adapterOwnedName(prefix: String) -> String {
        "\(prefix)\(sanitized)"
    }
}

public enum DiagnosticSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case blocking
}

public struct Diagnostic: Codable, Equatable, Sendable {
    public let severity: DiagnosticSeverity
    public let code: String
    public let message: String
    public let suggestion: String?

    public init(
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        suggestion: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.suggestion = suggestion
    }

    public static func unsupported(_ feature: String, suggestion: String) -> Diagnostic {
        Diagnostic(
            severity: .blocking,
            code: "unsupported-compose-feature",
            message: "\(feature) is not supported by the selected runtime subset.",
            suggestion: suggestion
        )
    }
}

public struct EnvironmentVariable: Codable, Equatable, Sendable {
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    public var redactedValue: String {
        SecretRedactor.redact(value, key: key)
    }
}

public enum ServiceKind: String, Codable, Equatable, Sendable {
    case service
    case oneOffJob
}

public struct PortMapping: Codable, Equatable, Sendable {
    public let hostPort: Int
    public let containerPort: Int
    public let protocolName: String

    public init(hostPort: Int, containerPort: Int, protocolName: String = "tcp") {
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
    }
}

public enum MountKind: String, Codable, Equatable, Sendable {
    case namedVolume
    case bind
}

public struct MountPlan: Codable, Equatable, Sendable {
    public let kind: MountKind
    public let source: String
    public let target: String
    public let readOnly: Bool

    public init(kind: MountKind, source: String, target: String, readOnly: Bool = false) {
        self.kind = kind
        self.source = source
        self.target = target
        self.readOnly = readOnly
    }
}

public struct VolumePlan: Codable, Equatable, Sendable {
    public let name: String
    public let preserveByDefault: Bool

    public init(name: String, preserveByDefault: Bool = true) {
        self.name = name
        self.preserveByDefault = preserveByDefault
    }
}

public enum ReadinessKind: String, Codable, Equatable, Sendable {
    case serviceStarted = "service_started"
    case serviceHealthy = "service_healthy"
    case serviceCompletedSuccessfully = "service_completed_successfully"
}

public struct ReadinessProbe: Codable, Equatable, Sendable {
    public let kind: ReadinessKind
    public let command: [String]
    public let timeoutSeconds: Int

    public init(kind: ReadinessKind, command: [String] = [], timeoutSeconds: Int = 60) {
        self.kind = kind
        self.command = command
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct ServiceDependency: Codable, Equatable, Sendable {
    public let serviceName: String
    public let condition: ReadinessKind

    public init(serviceName: String, condition: ReadinessKind) {
        self.serviceName = serviceName
        self.condition = condition
    }
}

public struct ServicePlan: Codable, Equatable, Sendable {
    public let name: String
    public let kind: ServiceKind
    public let image: String
    public let command: [String]
    public let environment: [EnvironmentVariable]
    public let ports: [PortMapping]
    public let mounts: [MountPlan]
    public let readiness: [ReadinessProbe]
    public let dependencies: [ServiceDependency]

    public init(
        name: String,
        kind: ServiceKind = .service,
        image: String,
        command: [String] = [],
        environment: [EnvironmentVariable] = [],
        ports: [PortMapping] = [],
        mounts: [MountPlan] = [],
        readiness: [ReadinessProbe] = [],
        dependencies: [ServiceDependency] = []
    ) {
        self.name = name
        self.kind = kind
        self.image = image
        self.command = command
        self.environment = environment
        self.ports = ports
        self.mounts = mounts
        self.readiness = readiness
        self.dependencies = dependencies
    }
}

public struct RuntimePlan: Codable, Equatable, Sendable {
    public let project: ProjectName
    public let services: [ServicePlan]
    public let volumes: [VolumePlan]
    public let diagnostics: [Diagnostic]

    public init(
        project: ProjectName,
        services: [ServicePlan],
        volumes: [VolumePlan] = [],
        diagnostics: [Diagnostic] = []
    ) {
        self.project = project
        self.services = services
        self.volumes = volumes
        self.diagnostics = diagnostics
    }

    public var hasBlockingDiagnostics: Bool {
        diagnostics.contains { $0.severity == .blocking }
    }
}

public enum PlannedActionKind: String, Codable, Equatable, Sendable {
    case reportDiagnostic
    case renderPlan
    case prepareImageRootfs
    case createNamedVolume
    case validateBindMount
    case createProjectRuntime
    case addContainer
    case startContainer
    case waitForReadiness
    case runJob
    case collectLogs
    case inspectStatus
    case stopProjectRuntime
    case deleteProjectRuntime
    case cleanupNamedVolume
}

public struct PlannedAction: Codable, Equatable, Sendable {
    public let order: Int
    public let kind: PlannedActionKind
    public let resourceName: String?
    public let description: String
    public let mutatesRuntime: Bool
    public let metadata: [String: String]

    public init(
        order: Int,
        kind: PlannedActionKind,
        resourceName: String? = nil,
        description: String,
        mutatesRuntime: Bool,
        metadata: [String: String] = [:]
    ) {
        self.order = order
        self.kind = kind
        self.resourceName = resourceName
        self.description = description
        self.mutatesRuntime = mutatesRuntime
        self.metadata = metadata
    }
}

public struct RuntimeOptions: Codable, Equatable, Sendable {
    public let includeVolumes: Bool

    public init(includeVolumes: Bool = false) {
        self.includeVolumes = includeVolumes
    }
}
