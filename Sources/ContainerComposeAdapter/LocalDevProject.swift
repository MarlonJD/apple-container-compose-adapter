// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct LocalDevProject: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let sourceFiles: [String]
    public let services: [LocalDevService]
    public let jobs: [LocalDevJob]
    public let volumes: [LocalDevVolume]
    public let networks: [LocalDevNetwork]
    public let routes: [LocalDevRoute]
    public let secrets: [LocalDevSecret]
    public let configs: [LocalDevConfig]
    public let profiles: [String]

    public init(
        id: String,
        name: String,
        sourceFiles: [String] = [],
        services: [LocalDevService] = [],
        jobs: [LocalDevJob] = [],
        volumes: [LocalDevVolume] = [],
        networks: [LocalDevNetwork] = [],
        routes: [LocalDevRoute] = [],
        secrets: [LocalDevSecret] = [],
        configs: [LocalDevConfig] = [],
        profiles: [String] = []
    ) {
        self.id = id
        self.name = name
        self.sourceFiles = sourceFiles
        self.services = services
        self.jobs = jobs
        self.volumes = volumes
        self.networks = networks
        self.routes = routes
        self.secrets = secrets
        self.configs = configs
        self.profiles = profiles
    }

    public func runtimePlan() -> RuntimePlan {
        var diagnostics: [Diagnostic] = []
        let servicePlans = services.map { service in
            service.runtimeServicePlan(diagnostics: &diagnostics)
        }
        let jobPlans = jobs.map { job in
            job.runtimeServicePlan(diagnostics: &diagnostics)
        }
        let runtimeVolumes = volumes.compactMap { volume in
            volume.runtimeVolumePlan(diagnostics: &diagnostics)
        }
        return RuntimePlan(
            project: ProjectName(name),
            services: servicePlans + jobPlans,
            volumes: runtimeVolumes,
            diagnostics: diagnostics
        )
    }
}

public struct LocalDevService: Codable, Equatable, Sendable {
    public let name: String
    public let image: String
    public let build: LocalDevBuildSpec?
    public let command: [String]
    public let entrypoint: [String]
    public let environment: [String: String]
    public let envFiles: [String]
    public let mounts: [LocalDevMount]
    public let ports: [LocalDevPort]
    public let aliases: [String]
    public let dependencies: [LocalDevDependency]
    public let healthcheck: LocalDevHealthcheck?
    public let restartPolicy: LocalDevRestartPolicy
    public let profiles: [String]

    public init(
        name: String,
        image: String,
        build: LocalDevBuildSpec? = nil,
        command: [String] = [],
        entrypoint: [String] = [],
        environment: [String: String] = [:],
        envFiles: [String] = [],
        mounts: [LocalDevMount] = [],
        ports: [LocalDevPort] = [],
        aliases: [String] = [],
        dependencies: [LocalDevDependency] = [],
        healthcheck: LocalDevHealthcheck? = nil,
        restartPolicy: LocalDevRestartPolicy = .unlessStopped,
        profiles: [String] = []
    ) {
        self.name = name
        self.image = image
        self.build = build
        self.command = command
        self.entrypoint = entrypoint
        self.environment = environment
        self.envFiles = envFiles
        self.mounts = mounts
        self.ports = ports
        self.aliases = aliases
        self.dependencies = dependencies
        self.healthcheck = healthcheck
        self.restartPolicy = restartPolicy
        self.profiles = profiles
    }

    fileprivate func runtimeServicePlan(diagnostics: inout [Diagnostic]) -> ServicePlan {
        if build != nil {
            diagnostics.append(.unsupported(
                "services.\(name).build",
                suggestion: "Use a prebuilt image until local build planning is implemented."
            ).renamed(code: "unsupported-localdev-build"))
        }
        return ServicePlan(
            name: name,
            kind: .service,
            image: image,
            command: entrypoint + command,
            environment: environment.runtimeEnvironment,
            ports: ports.runtimePorts(diagnostics: &diagnostics, owner: "services.\(name).ports"),
            mounts: mounts.runtimeMounts(diagnostics: &diagnostics, owner: "services.\(name).mounts"),
            readiness: healthcheck.map { [$0.runtimeReadinessProbe()] } ?? [],
            dependencies: dependencies.runtimeDependencies
        )
    }
}

public struct LocalDevJob: Codable, Equatable, Sendable {
    public let name: String
    public let image: String
    public let build: LocalDevBuildSpec?
    public let command: [String]
    public let environment: [String: String]
    public let envFiles: [String]
    public let mounts: [LocalDevMount]
    public let dependencies: [LocalDevDependency]
    public let completionPolicy: LocalDevCompletionPolicy
    public let profiles: [String]

    public init(
        name: String,
        image: String,
        build: LocalDevBuildSpec? = nil,
        command: [String] = [],
        environment: [String: String] = [:],
        envFiles: [String] = [],
        mounts: [LocalDevMount] = [],
        dependencies: [LocalDevDependency] = [],
        completionPolicy: LocalDevCompletionPolicy = .runToCompletion,
        profiles: [String] = []
    ) {
        self.name = name
        self.image = image
        self.build = build
        self.command = command
        self.environment = environment
        self.envFiles = envFiles
        self.mounts = mounts
        self.dependencies = dependencies
        self.completionPolicy = completionPolicy
        self.profiles = profiles
    }

    fileprivate func runtimeServicePlan(diagnostics: inout [Diagnostic]) -> ServicePlan {
        if build != nil {
            diagnostics.append(.unsupported(
                "jobs.\(name).build",
                suggestion: "Use a prebuilt image until local build planning is implemented."
            ).renamed(code: "unsupported-localdev-build"))
        }
        return ServicePlan(
            name: name,
            kind: .oneOffJob,
            image: image,
            command: command,
            environment: environment.runtimeEnvironment,
            mounts: mounts.runtimeMounts(diagnostics: &diagnostics, owner: "jobs.\(name).mounts"),
            readiness: [ReadinessProbe(kind: .serviceCompletedSuccessfully, timeoutSeconds: 60)],
            dependencies: dependencies.runtimeDependencies
        )
    }
}

public struct LocalDevBuildSpec: Codable, Equatable, Sendable {
    public let context: String
    public let dockerfile: String?
    public let target: String?
    public let args: [String: String]

    public init(
        context: String,
        dockerfile: String? = nil,
        target: String? = nil,
        args: [String: String] = [:]
    ) {
        self.context = context
        self.dockerfile = dockerfile
        self.target = target
        self.args = args
    }
}

public enum LocalDevVolumeKind: String, Codable, Equatable, Sendable {
    case named
    case bind
    case tmpfs
}

public struct LocalDevVolume: Codable, Equatable, Sendable {
    public let name: String
    public let kind: LocalDevVolumeKind
    public let source: String?
    public let sizeBytes: Int64?
    public let preserveByDefault: Bool
    public let labels: [String: String]

    public init(
        name: String,
        kind: LocalDevVolumeKind = .named,
        source: String? = nil,
        sizeBytes: Int64? = nil,
        preserveByDefault: Bool = true,
        labels: [String: String] = [:]
    ) {
        self.name = name
        self.kind = kind
        self.source = source
        self.sizeBytes = sizeBytes
        self.preserveByDefault = preserveByDefault
        self.labels = labels
    }

    fileprivate func runtimeVolumePlan(diagnostics: inout [Diagnostic]) -> VolumePlan? {
        switch kind {
        case .named:
            return VolumePlan(name: name, preserveByDefault: preserveByDefault)
        case .bind, .tmpfs:
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "non-named-localdev-volume",
                    message: "Project volume \(name) is represented in LocalDevProject but is not a runtime named volume.",
                    suggestion: "Use service mounts for bind or tmpfs intent until runtime support is expanded."
                )
            )
            return nil
        }
    }
}

public enum LocalDevMountKind: String, Codable, Equatable, Sendable {
    case namedVolume
    case bind
    case tmpfs
}

public struct LocalDevMount: Codable, Equatable, Sendable {
    public let kind: LocalDevMountKind
    public let source: String?
    public let target: String
    public let readOnly: Bool
    public let sizeBytes: Int64?

    public init(
        kind: LocalDevMountKind,
        source: String? = nil,
        target: String,
        readOnly: Bool = false,
        sizeBytes: Int64? = nil
    ) {
        self.kind = kind
        self.source = source
        self.target = target
        self.readOnly = readOnly
        self.sizeBytes = sizeBytes
    }

    fileprivate func runtimeMountPlan(diagnostics: inout [Diagnostic], owner: String) -> MountPlan? {
        switch kind {
        case .bind:
            guard let source, !source.isEmpty else {
                diagnostics.append(invalidMountSourceDiagnostic(owner: owner, kind: kind))
                return nil
            }
            return MountPlan(kind: .bind, source: source, target: target, readOnly: readOnly)
        case .namedVolume:
            guard let source, !source.isEmpty else {
                diagnostics.append(invalidMountSourceDiagnostic(owner: owner, kind: kind))
                return nil
            }
            return MountPlan(kind: .namedVolume, source: source, target: target, readOnly: readOnly)
        case .tmpfs:
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "unsupported-localdev-tmpfs-mount",
                    message: "\(owner) requests tmpfs mount \(target), which is not implemented by the current LinuxPod runtime plan.",
                    suggestion: "Use a named volume or remove the tmpfs mount until tmpfs runtime support is added."
                )
            )
            return nil
        }
    }

    private func invalidMountSourceDiagnostic(owner: String, kind: LocalDevMountKind) -> Diagnostic {
        Diagnostic(
            severity: .blocking,
            code: "invalid-localdev-mount-source",
            message: "\(owner) contains a \(kind.rawValue) mount without a source.",
            suggestion: "Provide a named volume name or bind source path."
        )
    }
}

public struct LocalDevPort: Codable, Equatable, Sendable {
    public let name: String?
    public let hostIP: String?
    public let hostPort: Int?
    public let containerPort: Int
    public let protocolName: String

    public init(
        name: String? = nil,
        hostIP: String? = nil,
        hostPort: Int? = nil,
        containerPort: Int,
        protocolName: String = "tcp"
    ) {
        self.name = name
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
    }

    fileprivate func runtimePortMapping(diagnostics: inout [Diagnostic], owner: String) -> PortMapping? {
        guard let hostPort else {
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "unsupported-localdev-dynamic-port",
                    message: "\(owner) requests dynamic host port publishing for container port \(containerPort).",
                    suggestion: "Choose a deterministic host port for the current LinuxPod runtime plan."
                )
            )
            return nil
        }
        return PortMapping(hostPort: hostPort, containerPort: containerPort, protocolName: protocolName)
    }
}

public enum LocalDevDependencyCondition: String, Codable, Equatable, Sendable {
    case serviceStarted
    case serviceHealthy
    case serviceCompletedSuccessfully
}

public struct LocalDevDependency: Codable, Equatable, Sendable {
    public let target: String
    public let condition: LocalDevDependencyCondition
    public let required: Bool

    public init(
        target: String,
        condition: LocalDevDependencyCondition,
        required: Bool = true
    ) {
        self.target = target
        self.condition = condition
        self.required = required
    }
}

public struct LocalDevHealthcheck: Codable, Equatable, Sendable {
    public let test: [String]
    public let intervalSeconds: Double
    public let timeoutSeconds: Double
    public let retries: Int
    public let startPeriodSeconds: Double

    public init(
        test: [String],
        intervalSeconds: Double = 30,
        timeoutSeconds: Double = 30,
        retries: Int = 3,
        startPeriodSeconds: Double = 0
    ) {
        self.test = test
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.retries = retries
        self.startPeriodSeconds = startPeriodSeconds
    }

    fileprivate func runtimeReadinessProbe() -> ReadinessProbe {
        ReadinessProbe(
            kind: .serviceHealthy,
            command: test,
            timeoutSeconds: Int(timeoutSeconds.rounded(.up))
        )
    }
}

public enum LocalDevRestartPolicy: String, Codable, Equatable, Sendable {
    case no
    case onFailure
    case unlessStopped
    case always
}

public enum LocalDevCompletionPolicy: String, Codable, Equatable, Sendable {
    case runToCompletion
    case allowFailure
}

public struct LocalDevSecret: Codable, Equatable, Sendable {
    public let name: String
    public let source: String?
    public let environmentKey: String?
    public let mountPath: String?

    public init(
        name: String,
        source: String? = nil,
        environmentKey: String? = nil,
        mountPath: String? = nil
    ) {
        self.name = name
        self.source = source
        self.environmentKey = environmentKey
        self.mountPath = mountPath
    }
}

public struct LocalDevConfig: Codable, Equatable, Sendable {
    public let name: String
    public let source: String?
    public let environmentKey: String?
    public let mountPath: String?

    public init(
        name: String,
        source: String? = nil,
        environmentKey: String? = nil,
        mountPath: String? = nil
    ) {
        self.name = name
        self.source = source
        self.environmentKey = environmentKey
        self.mountPath = mountPath
    }
}

public struct LocalDevRoute: Codable, Equatable, Sendable {
    public let name: String
    public let host: String?
    public let pathPrefix: String
    public let targetService: String
    public let targetPort: Int

    public init(
        name: String,
        host: String? = nil,
        pathPrefix: String = "/",
        targetService: String,
        targetPort: Int
    ) {
        self.name = name
        self.host = host
        self.pathPrefix = pathPrefix
        self.targetService = targetService
        self.targetPort = targetPort
    }
}

public struct LocalDevNetwork: Codable, Equatable, Sendable {
    public let name: String
    public let aliases: [String]

    public init(name: String, aliases: [String] = []) {
        self.name = name
        self.aliases = aliases
    }
}

private extension Dictionary where Key == String, Value == String {
    var runtimeEnvironment: [EnvironmentVariable] {
        keys.sorted().map { key in
            EnvironmentVariable(key, self[key] ?? "")
        }
    }
}

private extension Array where Element == LocalDevPort {
    func runtimePorts(diagnostics: inout [Diagnostic], owner: String) -> [PortMapping] {
        compactMap { port in
            port.runtimePortMapping(diagnostics: &diagnostics, owner: owner)
        }
    }
}

private extension Array where Element == LocalDevMount {
    func runtimeMounts(diagnostics: inout [Diagnostic], owner: String) -> [MountPlan] {
        compactMap { mount in
            mount.runtimeMountPlan(diagnostics: &diagnostics, owner: owner)
        }
    }
}

private extension Array where Element == LocalDevDependency {
    var runtimeDependencies: [ServiceDependency] {
        map { dependency in
            ServiceDependency(
                serviceName: dependency.target,
                condition: dependency.condition.runtimeReadinessKind
            )
        }
    }
}

private extension LocalDevDependencyCondition {
    var runtimeReadinessKind: ReadinessKind {
        switch self {
        case .serviceStarted:
            return .serviceStarted
        case .serviceHealthy:
            return .serviceHealthy
        case .serviceCompletedSuccessfully:
            return .serviceCompletedSuccessfully
        }
    }
}

private extension Diagnostic {
    func renamed(code: String) -> Diagnostic {
        Diagnostic(
            severity: severity,
            code: code,
            message: message,
            suggestion: suggestion
        )
    }
}
