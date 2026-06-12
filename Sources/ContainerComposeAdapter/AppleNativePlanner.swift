// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct AppleNativePlanner: Sendable {
    public init() {}

    public func plan(_ project: LocalDevProject) -> AppleNativePlannerResult {
        var diagnostics = project.diagnostics
        let support = AppleNativeSupportMatrix(project: project)
        diagnostics.append(contentsOf: support.diagnostics)

        let servicePlans = project.services.map { service in
            service.runtimeServicePlan(diagnostics: &diagnostics)
        }
        let jobPlans = project.jobs.map { job in
            job.runtimeServicePlan(diagnostics: &diagnostics)
        }
        let runtimeVolumes = project.volumes.compactMap { volume in
            volume.runtimeVolumePlan(diagnostics: &diagnostics)
        }
        let runtimePlan = RuntimePlan(
            project: ProjectName(project.name),
            services: servicePlans + jobPlans,
            volumes: runtimeVolumes,
            diagnostics: diagnostics
        )

        return AppleNativePlannerResult(
            runtimePlan: runtimePlan,
            support: support,
            diagnostics: diagnostics
        )
    }
}

public struct AppleNativePlannerResult: Equatable, Sendable {
    public let runtimePlan: RuntimePlan
    public let support: AppleNativeSupportMatrix
    public let diagnostics: [Diagnostic]

    public init(runtimePlan: RuntimePlan, support: AppleNativeSupportMatrix, diagnostics: [Diagnostic]) {
        self.runtimePlan = runtimePlan
        self.support = support
        self.diagnostics = diagnostics
    }
}

public enum AppleNativeSupportStatus: String, Codable, Equatable, Sendable {
    case supported
    case supportedWithSafetyChecks = "supported-with-safety-checks"
    case preservedIntent = "preserved-intent"
    case unsupported
}

public struct AppleNativeSupportEntry: Codable, Equatable, Sendable {
    public let feature: String
    public let status: AppleNativeSupportStatus
    public let diagnosticCode: String?

    public init(feature: String, status: AppleNativeSupportStatus, diagnosticCode: String? = nil) {
        self.feature = feature
        self.status = status
        self.diagnosticCode = diagnosticCode
    }
}

public struct AppleNativeSupportMatrix: Codable, Equatable, Sendable {
    public let entries: [AppleNativeSupportEntry]
    public let diagnostics: [Diagnostic]

    public init(project: LocalDevProject) {
        self.entries = Self.stageTwoEntries
        self.diagnostics = Self.diagnostics(for: project)
    }

    private static let stageTwoEntries: [AppleNativeSupportEntry] = [
        AppleNativeSupportEntry(feature: "service image", status: .supported),
        AppleNativeSupportEntry(feature: "command and entrypoint", status: .supported),
        AppleNativeSupportEntry(feature: "environment map/list values", status: .supported),
        AppleNativeSupportEntry(
            feature: "env files",
            status: .unsupported,
            diagnosticCode: "unsupported-apple-native-env-file"
        ),
        AppleNativeSupportEntry(feature: "deterministic host ports", status: .supported),
        AppleNativeSupportEntry(
            feature: "dynamic host ports",
            status: .unsupported,
            diagnosticCode: "unsupported-localdev-dynamic-port"
        ),
        AppleNativeSupportEntry(feature: "bind mounts", status: .supportedWithSafetyChecks),
        AppleNativeSupportEntry(feature: "named-volume mounts", status: .supported),
        AppleNativeSupportEntry(
            feature: "tmpfs mounts",
            status: .unsupported,
            diagnosticCode: "unsupported-localdev-tmpfs-mount"
        ),
        AppleNativeSupportEntry(
            feature: "build specs",
            status: .unsupported,
            diagnosticCode: "unsupported-localdev-build"
        ),
        AppleNativeSupportEntry(feature: "depends_on conditions", status: .supported),
        AppleNativeSupportEntry(feature: "healthcheck test", status: .supported),
        AppleNativeSupportEntry(feature: "one-off jobs", status: .supported),
        AppleNativeSupportEntry(
            feature: "routes",
            status: .preservedIntent,
            diagnosticCode: "preserved-apple-native-route-intent"
        ),
        AppleNativeSupportEntry(
            feature: "secrets",
            status: .preservedIntent,
            diagnosticCode: "preserved-apple-native-secret-intent"
        ),
        AppleNativeSupportEntry(
            feature: "configs",
            status: .preservedIntent,
            diagnosticCode: "preserved-apple-native-config-intent"
        ),
        AppleNativeSupportEntry(
            feature: "network aliases",
            status: .preservedIntent,
            diagnosticCode: "preserved-apple-native-network-intent"
        ),
        AppleNativeSupportEntry(
            feature: "restart policy",
            status: .preservedIntent,
            diagnosticCode: "preserved-apple-native-restart-policy"
        ),
        AppleNativeSupportEntry(
            feature: "job allow-failure policy",
            status: .unsupported,
            diagnosticCode: "unsupported-apple-native-job-allow-failure"
        )
    ]

    private static func diagnostics(for project: LocalDevProject) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        for service in project.services {
            if !service.envFiles.isEmpty {
                diagnostics.append(
                    Diagnostic(
                        severity: .blocking,
                        code: "unsupported-apple-native-env-file",
                        message: "services.\(service.name).env_file is preserved in LocalDevProject but AppleNativePlanner does not load env files yet.",
                        suggestion: "Inline required values into environment until env-file loading is implemented."
                    )
                )
            }
            if !service.aliases.isEmpty {
                diagnostics.append(networkIntentDiagnostic("services.\(service.name).aliases"))
            }
            if service.restartPolicy != .unlessStopped {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        code: "preserved-apple-native-restart-policy",
                        message: "services.\(service.name).restartPolicy \(service.restartPolicy.rawValue) is preserved as intent but is not enforced by the current runtime plan.",
                        suggestion: "Use the default local-dev restart behavior until LinuxPod lifecycle semantics are proven."
                    )
                )
            }
        }
        for job in project.jobs {
            if !job.envFiles.isEmpty {
                diagnostics.append(
                    Diagnostic(
                        severity: .blocking,
                        code: "unsupported-apple-native-env-file",
                        message: "jobs.\(job.name).env_file is preserved in LocalDevProject but AppleNativePlanner does not load env files yet.",
                        suggestion: "Inline required values into environment until env-file loading is implemented."
                    )
                )
            }
            if job.completionPolicy == .allowFailure {
                diagnostics.append(
                    Diagnostic(
                        severity: .blocking,
                        code: "unsupported-apple-native-job-allow-failure",
                        message: "jobs.\(job.name).completionPolicy allowFailure is unsupported because readiness ordering assumes successful completion.",
                        suggestion: "Use runToCompletion until allow-failure job semantics are explicitly planned."
                    )
                )
            }
        }
        for network in project.networks {
            diagnostics.append(networkIntentDiagnostic("networks.\(network.name)"))
        }
        for route in project.routes {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "preserved-apple-native-route-intent",
                    message: "routes.\(route.name) is preserved in LocalDevProject but no local route layer exists yet.",
                    suggestion: "Use direct host ports until route planning is implemented."
                )
            )
        }
        for secret in project.secrets {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "preserved-apple-native-secret-intent",
                    message: "secrets.\(secret.name) is preserved in LocalDevProject but runtime secret injection is not implemented yet.",
                    suggestion: "Use redacted environment values in dry-run only until secret injection is implemented."
                )
            )
        }
        for config in project.configs {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "preserved-apple-native-config-intent",
                    message: "configs.\(config.name) is preserved in LocalDevProject but runtime config injection is not implemented yet.",
                    suggestion: "Use explicit environment or bind mounts until config injection is implemented."
                )
            )
        }
        return diagnostics
    }

    private static func networkIntentDiagnostic(_ owner: String) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            code: "preserved-apple-native-network-intent",
            message: "\(owner) is preserved in LocalDevProject but AppleNativePlanner does not own DNS or hosts semantics yet.",
            suggestion: "Use service names from the runtime plan until explicit DNS/hosts planning is implemented."
        )
    }
}

private extension LocalDevService {
    func runtimeServicePlan(diagnostics: inout [Diagnostic]) -> ServicePlan {
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

private extension LocalDevJob {
    func runtimeServicePlan(diagnostics: inout [Diagnostic]) -> ServicePlan {
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

private extension LocalDevVolume {
    func runtimeVolumePlan(diagnostics: inout [Diagnostic]) -> VolumePlan? {
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

private extension LocalDevMount {
    func runtimeMountPlan(diagnostics: inout [Diagnostic], owner: String) -> MountPlan? {
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

private extension LocalDevPort {
    func runtimePortMapping(diagnostics: inout [Diagnostic], owner: String) -> PortMapping? {
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

private extension LocalDevHealthcheck {
    func runtimeReadinessProbe() -> ReadinessProbe {
        ReadinessProbe(
            kind: .serviceHealthy,
            command: test,
            timeoutSeconds: Int(timeoutSeconds.rounded(.up))
        )
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
