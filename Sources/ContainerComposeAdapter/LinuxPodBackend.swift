// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct LinuxPodStateStore: Sendable {
    public static let ownedPrefix = "cca-linuxpod-"

    public let root: URL

    public init(root: URL = URL(fileURLWithPath: ".container-compose-adapter", isDirectory: true)) {
        self.root = root
    }

    public func projectName(for project: ProjectName) -> String {
        project.adapterOwnedName(prefix: Self.ownedPrefix)
    }

    public func projectDirectory(for project: ProjectName) -> URL {
        root.appendingPathComponent(projectName(for: project), isDirectory: true)
    }

    public func runtimeDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    public func rootfsPath(project: ProjectName, image: String) -> URL {
        let escaped = image
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return runtimeDirectory(for: project)
            .appendingPathComponent("rootfs", isDirectory: true)
            .appendingPathComponent("\(escaped).ext4")
    }

    public func volumePath(project: ProjectName, volume: VolumePlan) -> URL {
        projectDirectory(for: project)
            .appendingPathComponent("volumes", isDirectory: true)
            .appendingPathComponent(volume.name, isDirectory: true)
    }

    public func removeEmptyProjectDirectories(project: ProjectName) throws {
        try removeEmptyProjectDirectories(projectDirectory: projectDirectory(for: project))
    }

    public func removeEmptyProjectDirectories(projectDirectory: URL) throws {
        try ensureAdapterOwnedProjectDirectory(projectDirectory)
        let volumesDirectory = projectDirectory
            .appendingPathComponent("volumes", isDirectory: true)
        try removeIfEmpty(volumesDirectory)
        try removeIfEmpty(projectDirectory)
        try removeIfEmpty(root)
    }

    private func ensureAdapterOwnedProjectDirectory(_ projectDirectory: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let projectPath = projectDirectory.standardizedFileURL.path
        let isInsideRoot = projectPath == rootPath || projectPath.hasPrefix(rootPath + "/")
        guard isInsideRoot,
              projectDirectory.standardizedFileURL.lastPathComponent.hasPrefix(Self.ownedPrefix) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing to remove non-adapter-owned project directory \(projectDirectory.path)."
            )
        }
    }

    private func removeIfEmpty(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        if contents.isEmpty {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

public struct LinuxPodBackend: RuntimeBackend {
    public static let runtimeApprovalToken = "I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION"

    public let kind: RuntimeKind = .linuxpod
    public let capabilities = RuntimeCapabilities(
        supportsDryRun: true,
        supportsRuntimeMutation: true,
        supportedCommands: [.up, .down, .logs, .status, .run]
    )

    public let stateStore: LinuxPodStateStore
    private let runtimeExecutor: any LinuxPodRuntimeExecuting

    public init(
        stateStore: LinuxPodStateStore = LinuxPodStateStore(),
        runtimeExecutor: any LinuxPodRuntimeExecuting = UnavailableLinuxPodRuntimeExecutor()
    ) {
        self.stateStore = stateStore
        self.runtimeExecutor = runtimeExecutor
    }

    public func renderDryRun(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions = RuntimeOptions()
    ) throws -> DryRunResult {
        guard capabilities.supportedCommands.contains(command) else {
            throw RuntimeBackendError.unsupportedCommand(command)
        }

        let diagnostics = plan.diagnostics + linuxPodDiagnostics(for: plan)
        let actions = buildActions(command: command, plan: plan, options: options, diagnostics: diagnostics)
        return DryRunResult(
            backend: kind,
            command: command,
            project: stateStore.projectName(for: plan.project),
            approvalRequired: actions.contains(where: \.mutatesRuntime),
            diagnostics: diagnostics,
            actions: actions
        )
    }

    public func execute(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions = RuntimeOptions(),
        approval: RuntimeApproval = RuntimeApproval()
    ) async throws -> ExecutionResult {
        let dryRun = try renderDryRun(command: command, plan: plan, options: options)
        let blocking = dryRun.diagnostics.filter { $0.severity == .blocking }
        if !blocking.isEmpty {
            throw RuntimeBackendError.blockingDiagnostics(blocking)
        }
        if dryRun.actions.contains(where: \.mutatesRuntime) {
            guard approval.approved, approval.token == Self.runtimeApprovalToken else {
                throw RuntimeBackendError.runtimeMutationRequiresApproval(
                    "LinuxPod runtime mutation requires explicit current-task approval and token \(Self.runtimeApprovalToken)."
                )
            }
        }
        var actionResults: [RuntimeActionResult] = []
        for action in dryRun.actions.sorted(by: { $0.order < $1.order }) {
            guard action.kind != .reportDiagnostic else {
                continue
            }
            let actionResult = try await runtimeExecutor.execute(
                LinuxPodRuntimeEvent(
                    project: dryRun.project,
                    action: action,
                    service: service(for: action, in: plan),
                    volume: volume(for: action, in: plan)
                )
            )
            actionResults.append(actionResult)
        }
        return ExecutionResult(
            backend: kind,
            command: command,
            status: "executed",
            diagnostics: dryRun.diagnostics,
            actionResults: actionResults
        )
    }

    private func linuxPodDiagnostics(for plan: RuntimePlan) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        for service in plan.services {
            diagnostics += ImageReferencePolicy.diagnostics(for: service.image)
            for mount in service.mounts {
                diagnostics += MountSafetyAnalyzer.diagnostics(for: mount)
            }
        }
        return diagnostics
    }

    private func buildActions(
        command: AdapterCommand,
        plan: RuntimePlan,
        options: RuntimeOptions,
        diagnostics: [Diagnostic]
    ) -> [PlannedAction] {
        var builder = ActionBuilder()
        for diagnostic in diagnostics {
            builder.append(
                kind: .reportDiagnostic,
                description: diagnostic.message,
                mutatesRuntime: false,
                metadata: ["severity": diagnostic.severity.rawValue, "code": diagnostic.code]
            )
        }

        switch command {
        case .up:
            appendUpActions(plan: plan, builder: &builder)
        case .down:
            appendDownActions(plan: plan, includeVolumes: options.includeVolumes, builder: &builder)
        case .logs:
            for service in plan.services {
                builder.append(
                    kind: .collectLogs,
                    resourceName: serviceResourceName(plan: plan, service: service),
                    description: "Collect logs for \(service.name) from the project LinuxPod.",
                    mutatesRuntime: false,
                    metadata: ["service": service.name]
                )
            }
        case .status:
            builder.append(
                kind: .inspectStatus,
                resourceName: stateStore.projectName(for: plan.project),
                description: "Inspect adapter-owned LinuxPod state without starting or stopping resources.",
                mutatesRuntime: false,
                metadata: ["services": dependencyOrderedServices(plan.services).map(\.name).joined(separator: ",")]
            )
        case .run:
            appendRunActions(plan: plan, builder: &builder)
        }
        return builder.actions
    }

    private func appendUpActions(plan: RuntimePlan, builder: inout ActionBuilder) {
        let projectResource = stateStore.projectName(for: plan.project)
        builder.append(
            kind: .createProjectRuntime,
            resourceName: projectResource,
            description: "Create or reuse one project-scoped LinuxPod VM.",
            mutatesRuntime: true,
            metadata: [
                "state": stateStore.runtimeDirectory(for: plan.project).path,
                "hosts": serviceHostsMetadata(plan)
            ]
        )

        let images = Set(plan.services.map(\.image)).sorted()
        for image in images {
            let rootfsPath = stateStore.rootfsPath(project: plan.project, image: image)
            let cacheStatus = FileManager.default.fileExists(atPath: rootfsPath.path) ? "hit" : "miss"
            builder.append(
                kind: .prepareImageRootfs,
                resourceName: image,
                description: "Prepare public image rootfs for \(image); cache \(cacheStatus).",
                mutatesRuntime: true,
                metadata: ["rootfs": rootfsPath.path, "cache": cacheStatus]
            )
        }

        for volume in plan.volumes {
            builder.append(
                kind: .createNamedVolume,
                resourceName: volume.name,
                description: "Map Compose named volume \(volume.name) to adapter-owned state.",
                mutatesRuntime: true,
                metadata: ["path": stateStore.volumePath(project: plan.project, volume: volume).path]
            )
        }

        // LinuxPod only accepts container registration before the pod VM is
        // created, so every addContainer must precede the first start/run.
        let orderedServices = dependencyOrderedServices(plan.services)
        for service in orderedServices {
            for mount in service.mounts where mount.kind == .bind {
                builder.append(
                    kind: .validateBindMount,
                    resourceName: mount.source,
                    description: "Validate bind mount \(mount.source) -> \(mount.target).",
                    mutatesRuntime: false,
                    metadata: ["readOnly": "\(mount.readOnly)"]
                )
            }
            builder.append(
                kind: .addContainer,
                resourceName: serviceResourceName(plan: plan, service: service),
                description: "Add \(service.kind.rawValue) \(service.name) to shared LinuxPod with project hosts entries.",
                mutatesRuntime: true,
                metadata: serviceMetadata(service, plan: plan)
            )
        }
        for service in orderedServices {
            if service.kind == .oneOffJob {
                builder.append(
                    kind: .runJob,
                    resourceName: serviceResourceName(plan: plan, service: service),
                    description: "Run job \(service.name) and capture exit status/logs.",
                    mutatesRuntime: true
                )
            } else {
                builder.append(
                    kind: .startContainer,
                    resourceName: serviceResourceName(plan: plan, service: service),
                    description: "Start service \(service.name) inside the project LinuxPod.",
                    mutatesRuntime: true
                )
            }
            for readiness in service.readiness {
                builder.append(
                    kind: .waitForReadiness,
                    resourceName: service.name,
                    description: "Wait for \(readiness.kind.rawValue) with readiness wait budget \(readiness.timeoutSeconds)s.",
                    mutatesRuntime: false,
                    metadata: readinessMetadata(readiness)
                )
            }
        }
    }

    private func appendRunActions(plan: RuntimePlan, builder: inout ActionBuilder) {
        let services = jobDependencyClosure(plan)
        guard !services.isEmpty else {
            return
        }
        let projectResource = stateStore.projectName(for: plan.project)
        builder.append(
            kind: .createProjectRuntime,
            resourceName: projectResource,
            description: "Create or reuse one project-scoped LinuxPod VM for one-off jobs.",
            mutatesRuntime: true,
            metadata: [
                "state": stateStore.runtimeDirectory(for: plan.project).path,
                "hosts": serviceHostsMetadata(plan)
            ]
        )

        let images = Set(services.map(\.image)).sorted()
        for image in images {
            let rootfsPath = stateStore.rootfsPath(project: plan.project, image: image)
            let cacheStatus = FileManager.default.fileExists(atPath: rootfsPath.path) ? "hit" : "miss"
            builder.append(
                kind: .prepareImageRootfs,
                resourceName: image,
                description: "Prepare public image rootfs for \(image); cache \(cacheStatus).",
                mutatesRuntime: true,
                metadata: ["rootfs": rootfsPath.path, "cache": cacheStatus]
            )
        }

        let selectedVolumeNames = Set(
            services.flatMap(\.mounts).compactMap { mount in
                mount.kind == .namedVolume ? mount.source : nil
            }
        )
        for volume in plan.volumes where selectedVolumeNames.contains(volume.name) {
            builder.append(
                kind: .createNamedVolume,
                resourceName: volume.name,
                description: "Map Compose named volume \(volume.name) to adapter-owned state.",
                mutatesRuntime: true,
                metadata: ["path": stateStore.volumePath(project: plan.project, volume: volume).path]
            )
        }

        // LinuxPod only accepts container registration before the pod VM is
        // created, so every addContainer must precede the first start/run.
        for service in services {
            for mount in service.mounts where mount.kind == .bind {
                builder.append(
                    kind: .validateBindMount,
                    resourceName: mount.source,
                    description: "Validate bind mount \(mount.source) -> \(mount.target).",
                    mutatesRuntime: false,
                    metadata: ["readOnly": "\(mount.readOnly)"]
                )
            }
            builder.append(
                kind: .addContainer,
                resourceName: serviceResourceName(plan: plan, service: service),
                description: "Add \(service.kind.rawValue) \(service.name) to shared LinuxPod with project hosts entries.",
                mutatesRuntime: true,
                metadata: serviceMetadata(service, plan: plan)
            )
        }
        for service in services {
            if service.kind == .oneOffJob {
                builder.append(
                    kind: .runJob,
                    resourceName: serviceResourceName(plan: plan, service: service),
                    description: "Run one-off job \(service.name) in the project LinuxPod.",
                    mutatesRuntime: true,
                    metadata: serviceMetadata(service, plan: plan)
                )
            } else {
                builder.append(
                    kind: .startContainer,
                    resourceName: serviceResourceName(plan: plan, service: service),
                    description: "Start dependency service \(service.name) inside the project LinuxPod.",
                    mutatesRuntime: true
                )
            }
            for readiness in service.readiness {
                builder.append(
                    kind: .waitForReadiness,
                    resourceName: service.name,
                    description: "Wait for \(readiness.kind.rawValue) with readiness wait budget \(readiness.timeoutSeconds)s.",
                    mutatesRuntime: false,
                    metadata: readinessMetadata(readiness)
                )
            }
        }
    }

    private func appendDownActions(
        plan: RuntimePlan,
        includeVolumes: Bool,
        builder: inout ActionBuilder
    ) {
        let projectResource = stateStore.projectName(for: plan.project)
        builder.append(
            kind: .stopProjectRuntime,
            resourceName: projectResource,
            description: "Stop only the adapter-owned project LinuxPod.",
            mutatesRuntime: true,
            metadata: ["state": stateStore.runtimeDirectory(for: plan.project).path]
        )
        builder.append(
            kind: .deleteProjectRuntime,
            resourceName: projectResource,
            description: "Delete only adapter-owned project runtime state.",
            mutatesRuntime: true,
            metadata: ["state": stateStore.runtimeDirectory(for: plan.project).path]
        )
        if includeVolumes {
            for volume in plan.volumes {
                builder.append(
                    kind: .cleanupNamedVolume,
                    resourceName: volume.name,
                    description: "Delete adapter-owned named volume because down --volumes was requested.",
                    mutatesRuntime: true,
                    metadata: ["path": stateStore.volumePath(project: plan.project, volume: volume).path]
                )
            }
        }
    }

    private func serviceResourceName(plan: RuntimePlan, service: ServicePlan) -> String {
        "\(stateStore.projectName(for: plan.project))-\(ProjectName(service.name).sanitized)"
    }

    private func serviceMetadata(_ service: ServicePlan, plan: RuntimePlan) -> [String: String] {
        var metadata: [String: String] = [
            "hosts": serviceHostsMetadata(plan),
            "image": service.image,
            "process": service.command.isEmpty ? "image-defaults" : "explicit-command"
        ]
        if !service.command.isEmpty {
            metadata["command"] = service.command.joined(separator: " ")
        } else {
            metadata["imageDefaults"] = "Entrypoint+Cmd+Env+WorkingDir+DeclaredVolumes resolved during prepareImageRootfs"
        }
        if !service.environment.isEmpty {
            metadata["environment"] = service.environment
                .map { "\($0.key)=\($0.redactedValue)" }
                .joined(separator: ",")
        }
        if !service.ports.isEmpty {
            metadata["ports"] = service.ports
                .map { "\($0.hostPort):\($0.containerPort)/\($0.protocolName)" }
                .joined(separator: ",")
        }
        if !service.dependencies.isEmpty {
            metadata["dependsOn"] = service.dependencies
                .map { "\($0.serviceName):\($0.condition.rawValue)" }
                .joined(separator: ",")
        }
        return metadata
    }

    private func readinessMetadata(_ readiness: ReadinessProbe) -> [String: String] {
        var metadata = [
            "condition": readiness.kind.rawValue,
            "timeoutSeconds": "\(readiness.timeoutSeconds)",
            "readinessWaitBudgetSeconds": "\(readiness.timeoutSeconds)"
        ]
        if !readiness.command.isEmpty {
            metadata["command"] = readiness.command.joined(separator: " ")
        }
        return metadata
    }

    private func serviceHostsMetadata(_ plan: RuntimePlan) -> String {
        let hostnames = dependencyOrderedServices(plan.services).map(\.name).joined(separator: " ")
        return "127.0.0.1 \(hostnames)"
    }

    private func jobDependencyClosure(_ plan: RuntimePlan) -> [ServicePlan] {
        let servicesByName = Dictionary(uniqueKeysWithValues: plan.services.map { ($0.name, $0) })
        var included = Set<String>()

        func include(_ service: ServicePlan) {
            guard included.insert(service.name).inserted else {
                return
            }
            for dependency in service.dependencies {
                if let dependencyService = servicesByName[dependency.serviceName] {
                    include(dependencyService)
                }
            }
        }

        for job in plan.services where job.kind == .oneOffJob {
            include(job)
        }
        return dependencyOrderedServices(plan.services).filter { included.contains($0.name) }
    }

    private func service(for action: PlannedAction, in plan: RuntimePlan) -> ServicePlan? {
        guard let resourceName = action.resourceName else {
            return nil
        }
        return plan.services.first { service in
            let serviceResource = serviceResourceName(plan: plan, service: service)
            return resourceName == serviceResource || resourceName == service.name
        }
    }

    private func volume(for action: PlannedAction, in plan: RuntimePlan) -> VolumePlan? {
        guard let resourceName = action.resourceName else {
            return nil
        }
        return plan.volumes.first { $0.name == resourceName }
    }

    private func dependencyOrderedServices(_ services: [ServicePlan]) -> [ServicePlan] {
        var ordered: [ServicePlan] = []
        var pending = services
        var emitted = Set<String>()
        while !pending.isEmpty {
            let ready = pending.filter { service in
                service.dependencies.allSatisfy { emitted.contains($0.serviceName) }
            }
            if ready.isEmpty {
                ordered.append(contentsOf: pending)
                break
            }
            for service in ready {
                ordered.append(service)
                emitted.insert(service.name)
            }
            pending.removeAll { service in ready.contains(where: { $0.name == service.name }) }
        }
        return ordered
    }
}

private struct ActionBuilder {
    private(set) var actions: [PlannedAction] = []

    mutating func append(
        kind: PlannedActionKind,
        resourceName: String? = nil,
        description: String,
        mutatesRuntime: Bool,
        metadata: [String: String] = [:]
    ) {
        actions.append(
            PlannedAction(
                order: actions.count + 1,
                kind: kind,
                resourceName: resourceName,
                description: description,
                mutatesRuntime: mutatesRuntime,
                metadata: metadata
            )
        )
    }
}
