// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

/// Translates rendered Kubernetes YAML (kubectl/Helm/Kustomize output) into
/// `LocalDevProject`. This is local-development manifest translation only: it
/// is not a Kubernetes cluster and does not run controllers or operators.
public struct KubernetesSubsetFrontend: Sendable {
    public init() {}

    public func parseProject(
        fileURL: URL,
        projectName: String? = nil
    ) throws -> KubernetesSubsetFrontendResult {
        let data = try Data(contentsOf: fileURL)
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw KubernetesSubsetFrontendError.invalidUTF8(fileURL.path)
        }
        return try parseProject(
            yaml: yaml,
            sourceName: fileURL.path,
            projectName: projectName ?? fileURL.deletingLastPathComponent().lastPathComponent
        )
    }

    public func parseProject(
        yaml: String,
        sourceName: String = "k8s.yaml",
        projectName: String = "kubernetes-project"
    ) throws -> KubernetesSubsetFrontendResult {
        var diagnostics: [Diagnostic] = []
        var scan = DocumentScan()

        for document in Self.splitDocuments(yaml) {
            var parser = ComposeYAMLSubsetParser(yaml: document)
            let root = try parser.parse()
            guard let pairs = root.mappingPairs, !pairs.isEmpty else {
                continue
            }
            try scanDocument(OrderedYAMLMap(pairs), scan: &scan, diagnostics: &diagnostics)
        }

        let project = try buildProject(
            scan: scan,
            sourceName: sourceName,
            projectName: projectName,
            diagnostics: &diagnostics
        )
        return KubernetesSubsetFrontendResult(project: project, diagnostics: diagnostics)
    }

    // MARK: - Document scanning

    private static let supportedKinds = Set([
        "Namespace", "Secret", "ConfigMap", "Deployment", "StatefulSet",
        "Service", "Job", "PersistentVolumeClaim", "Ingress"
    ])

    private func scanDocument(
        _ document: OrderedYAMLMap,
        scan: inout DocumentScan,
        diagnostics: inout [Diagnostic]
    ) throws {
        guard let kind = document.value(for: "kind")?.stringValue, !kind.isEmpty else {
            throw KubernetesSubsetFrontendError.invalidDocument(
                "Every Kubernetes document must declare a kind."
            )
        }
        let metadata = OrderedYAMLMap(document.value(for: "metadata")?.mappingPairs ?? [])
        let name = metadata.value(for: "name")?.stringValue ?? ""
        let annotations = stringMap(metadata.value(for: "annotations"))
        if annotations["cca.local/ignore"] == "true" {
            return
        }
        if let namespace = metadata.value(for: "namespace")?.stringValue, !namespace.isEmpty {
            scan.namespaces.insert(namespace)
        }

        guard Self.supportedKinds.contains(kind) else {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "unsupported-kubernetes-kind",
                    message: "Kubernetes kind \(kind) (\(name)) is not part of the local-development subset and is ignored.",
                    suggestion: "Remove the object from the local render or mark it cca.local/ignore. Kubernetes support means local-development manifest translation, not cluster behavior."
                )
            )
            return
        }
        guard !name.isEmpty || kind == "Namespace" else {
            throw KubernetesSubsetFrontendError.invalidDocument(
                "Kubernetes \(kind) document is missing metadata.name."
            )
        }

        switch kind {
        case "Namespace":
            if !name.isEmpty {
                scan.namespaces.insert(name)
            }
        case "Secret":
            scan.secrets[name] = secretData(document)
            scan.secretOrder.append(name)
        case "ConfigMap":
            scan.configMaps[name] = stringMap(document.value(for: "data"))
            scan.configMapOrder.append(name)
        case "PersistentVolumeClaim":
            scan.volumes.append(
                LocalDevVolume(
                    name: name,
                    kind: .named,
                    sizeBytes: Self.storageBytes(requestedStorage(document))
                )
            )
        case "Deployment", "StatefulSet":
            scan.workloads.append(
                try workloadDraft(kind: kind, name: name, annotations: annotations, document: document, diagnostics: &diagnostics)
            )
        case "Job":
            scan.jobs.append(
                try jobDraft(name: name, annotations: annotations, document: document, diagnostics: &diagnostics)
            )
        case "Service":
            scan.services.append(serviceDraft(name: name, annotations: annotations, document: document))
        case "Ingress":
            scan.routes.append(contentsOf: routeDrafts(name: name, document: document, diagnostics: &diagnostics))
        default:
            break
        }
    }

    private func secretData(_ document: OrderedYAMLMap) -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in stringMap(document.value(for: "data")) {
            guard let decoded = Data(base64Encoded: value),
                  let text = String(data: decoded, encoding: .utf8) else {
                continue
            }
            values[key] = text
        }
        for (key, value) in stringMap(document.value(for: "stringData")) {
            values[key] = value
        }
        return values
    }

    private func requestedStorage(_ document: OrderedYAMLMap) -> String? {
        let spec = OrderedYAMLMap(document.value(for: "spec")?.mappingPairs ?? [])
        let resources = OrderedYAMLMap(spec.value(for: "resources")?.mappingPairs ?? [])
        let requests = OrderedYAMLMap(resources.value(for: "requests")?.mappingPairs ?? [])
        return requests.value(for: "storage")?.stringValue
    }

    private func workloadDraft(
        kind: String,
        name: String,
        annotations: [String: String],
        document: OrderedYAMLMap,
        diagnostics: inout [Diagnostic]
    ) throws -> WorkloadDraft {
        let spec = OrderedYAMLMap(document.value(for: "spec")?.mappingPairs ?? [])
        if let replicas = spec.value(for: "replicas")?.intValue, replicas > 1 {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-multi-replica",
                    message: "\(kind) \(name) requests \(replicas) replicas but local development runs a single replica.",
                    suggestion: "Set replicas to 1 in the local render; multi-replica controllers are out of the local-development subset."
                )
            )
        }
        let template = OrderedYAMLMap(spec.value(for: "template")?.mappingPairs ?? [])
        let templateMetadata = OrderedYAMLMap(template.value(for: "metadata")?.mappingPairs ?? [])
        let podSpec = OrderedYAMLMap(template.value(for: "spec")?.mappingPairs ?? [])
        let container = try primaryContainer(owner: "\(kind) \(name)", podSpec: podSpec, diagnostics: &diagnostics)
        return WorkloadDraft(
            name: name,
            annotations: annotations,
            podLabels: stringMap(templateMetadata.value(for: "labels")),
            podVolumes: podVolumes(owner: "\(kind) \(name)", podSpec: podSpec, diagnostics: &diagnostics),
            container: container
        )
    }

    private func jobDraft(
        name: String,
        annotations: [String: String],
        document: OrderedYAMLMap,
        diagnostics: inout [Diagnostic]
    ) throws -> JobDraft {
        let spec = OrderedYAMLMap(document.value(for: "spec")?.mappingPairs ?? [])
        let template = OrderedYAMLMap(spec.value(for: "template")?.mappingPairs ?? [])
        let podSpec = OrderedYAMLMap(template.value(for: "spec")?.mappingPairs ?? [])
        let restartPolicy = podSpec.value(for: "restartPolicy")?.stringValue
        if restartPolicy != "Never" && restartPolicy != "OnFailure" {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-job-restart-policy",
                    message: "Job \(name) should declare restartPolicy Never or OnFailure; treating it as run-to-completion.",
                    suggestion: "Set restartPolicy: Never for one-off local jobs."
                )
            )
        }
        let container = try primaryContainer(owner: "Job \(name)", podSpec: podSpec, diagnostics: &diagnostics)
        return JobDraft(
            name: name,
            annotations: annotations,
            podVolumes: podVolumes(owner: "Job \(name)", podSpec: podSpec, diagnostics: &diagnostics),
            container: container
        )
    }

    private func serviceDraft(
        name: String,
        annotations: [String: String],
        document: OrderedYAMLMap
    ) -> ServiceDraft {
        let spec = OrderedYAMLMap(document.value(for: "spec")?.mappingPairs ?? [])
        let ports = (spec.value(for: "ports")?.sequenceValues ?? []).compactMap { value -> ServiceDraft.Port? in
            guard let pairs = value.mappingPairs else {
                return nil
            }
            let map = OrderedYAMLMap(pairs)
            guard let port = map.value(for: "port")?.intValue else {
                return nil
            }
            return ServiceDraft.Port(
                port: port,
                targetPort: map.value(for: "targetPort")?.intValue,
                protocolName: (map.value(for: "protocol")?.stringValue ?? "TCP").lowercased()
            )
        }
        return ServiceDraft(
            name: name,
            annotations: annotations,
            selector: stringMap(spec.value(for: "selector")),
            ports: ports
        )
    }

    private func routeDrafts(
        name: String,
        document: OrderedYAMLMap,
        diagnostics: inout [Diagnostic]
    ) -> [LocalDevRoute] {
        let spec = OrderedYAMLMap(document.value(for: "spec")?.mappingPairs ?? [])
        var routes: [LocalDevRoute] = []
        for rule in spec.value(for: "rules")?.sequenceValues ?? [] {
            let ruleMap = OrderedYAMLMap(rule.mappingPairs ?? [])
            let host = ruleMap.value(for: "host")?.stringValue
            let http = OrderedYAMLMap(ruleMap.value(for: "http")?.mappingPairs ?? [])
            for path in http.value(for: "paths")?.sequenceValues ?? [] {
                let pathMap = OrderedYAMLMap(path.mappingPairs ?? [])
                let backend = OrderedYAMLMap(pathMap.value(for: "backend")?.mappingPairs ?? [])
                let backendService = OrderedYAMLMap(backend.value(for: "service")?.mappingPairs ?? [])
                let backendPort = OrderedYAMLMap(backendService.value(for: "port")?.mappingPairs ?? [])
                guard let targetService = backendService.value(for: "name")?.stringValue,
                      let targetPort = backendPort.value(for: "number")?.intValue else {
                    diagnostics.append(
                        Diagnostic(
                            severity: .warning,
                            code: "kubernetes-ingress-backend",
                            message: "Ingress \(name) has a path without a service name and numeric port; the route is ignored.",
                            suggestion: "Use a service backend with a numeric port for ingress-lite local routes."
                        )
                    )
                    continue
                }
                routes.append(
                    LocalDevRoute(
                        name: name,
                        host: host,
                        pathPrefix: pathMap.value(for: "path")?.stringValue ?? "/",
                        targetService: targetService,
                        targetPort: targetPort
                    )
                )
            }
        }
        return routes
    }

    private func primaryContainer(
        owner: String,
        podSpec: OrderedYAMLMap,
        diagnostics: inout [Diagnostic]
    ) throws -> ContainerDraft {
        if podSpec.value(for: "initContainers") != nil {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-init-containers",
                    message: "\(owner) declares initContainers, which are not part of the local-development subset.",
                    suggestion: "Model ordered setup work as a Job with a cca.local/depends-on annotation."
                )
            )
        }
        let containers = podSpec.value(for: "containers")?.sequenceValues ?? []
        guard let first = containers.first, let pairs = first.mappingPairs else {
            throw KubernetesSubsetFrontendError.invalidDocument(
                "\(owner) must declare at least one container."
            )
        }
        if containers.count > 1 {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-multi-container",
                    message: "\(owner) declares \(containers.count) containers; only the first container is translated.",
                    suggestion: "Split sidecars into separate Deployments or drop them from the local render."
                )
            )
        }
        let container = OrderedYAMLMap(pairs)
        if container.value(for: "livenessProbe") != nil {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-liveness-probe",
                    message: "\(owner) livenessProbe is ignored; readinessProbe drives local readiness.",
                    suggestion: "Keep restart semantics out of the local-development subset."
                )
            )
        }
        return ContainerDraft(
            image: container.value(for: "image")?.stringValue ?? "",
            command: stringArray(container.value(for: "command")),
            args: stringArray(container.value(for: "args")),
            env: envEntries(container),
            healthcheck: readinessHealthcheck(owner: owner, container: container, diagnostics: &diagnostics),
            volumeMounts: volumeMounts(container)
        )
    }

    private func envEntries(_ container: OrderedYAMLMap) -> [EnvEntry] {
        var entries: [EnvEntry] = []
        for item in container.value(for: "env")?.sequenceValues ?? [] {
            guard let pairs = item.mappingPairs else {
                continue
            }
            let map = OrderedYAMLMap(pairs)
            guard let name = map.value(for: "name")?.stringValue else {
                continue
            }
            if let value = map.value(for: "value")?.stringValue {
                entries.append(.value(name: name, value: value))
                continue
            }
            let valueFrom = OrderedYAMLMap(map.value(for: "valueFrom")?.mappingPairs ?? [])
            if let secretRef = valueFrom.value(for: "secretKeyRef")?.mappingPairs {
                let refMap = OrderedYAMLMap(secretRef)
                entries.append(
                    .secretKey(
                        name: name,
                        secret: refMap.value(for: "name")?.stringValue ?? "",
                        key: refMap.value(for: "key")?.stringValue ?? ""
                    )
                )
                continue
            }
            if let configRef = valueFrom.value(for: "configMapKeyRef")?.mappingPairs {
                let refMap = OrderedYAMLMap(configRef)
                entries.append(
                    .configMapKey(
                        name: name,
                        configMap: refMap.value(for: "name")?.stringValue ?? "",
                        key: refMap.value(for: "key")?.stringValue ?? ""
                    )
                )
                continue
            }
            entries.append(.unresolvable(name: name))
        }
        for item in container.value(for: "envFrom")?.sequenceValues ?? [] {
            guard let pairs = item.mappingPairs else {
                continue
            }
            let map = OrderedYAMLMap(pairs)
            if let secretRef = map.value(for: "secretRef")?.mappingPairs {
                entries.append(.allSecretKeys(secret: OrderedYAMLMap(secretRef).value(for: "name")?.stringValue ?? ""))
            }
            if let configRef = map.value(for: "configMapRef")?.mappingPairs {
                entries.append(.allConfigMapKeys(configMap: OrderedYAMLMap(configRef).value(for: "name")?.stringValue ?? ""))
            }
        }
        return entries
    }

    private func readinessHealthcheck(
        owner: String,
        container: OrderedYAMLMap,
        diagnostics: inout [Diagnostic]
    ) -> LocalDevHealthcheck? {
        guard let probePairs = container.value(for: "readinessProbe")?.mappingPairs else {
            return nil
        }
        let probe = OrderedYAMLMap(probePairs)
        guard let execPairs = probe.value(for: "exec")?.mappingPairs else {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-probe-type",
                    message: "\(owner) readinessProbe is not an exec probe; httpGet/tcpSocket probes are not translated.",
                    suggestion: "Use an exec probe (for example sh -ec with curl or pg_isready) for local readiness."
                )
            )
            return nil
        }
        let command = stringArray(OrderedYAMLMap(execPairs).value(for: "command"))
        guard !command.isEmpty else {
            return nil
        }
        return LocalDevHealthcheck(
            test: command,
            intervalSeconds: Double(probe.value(for: "periodSeconds")?.intValue ?? 10),
            timeoutSeconds: Double(probe.value(for: "timeoutSeconds")?.intValue ?? 1),
            retries: probe.value(for: "failureThreshold")?.intValue ?? 3,
            startPeriodSeconds: Double(probe.value(for: "initialDelaySeconds")?.intValue ?? 0)
        )
    }

    private func volumeMounts(_ container: OrderedYAMLMap) -> [ContainerDraft.VolumeMount] {
        (container.value(for: "volumeMounts")?.sequenceValues ?? []).compactMap { item in
            guard let pairs = item.mappingPairs else {
                return nil
            }
            let map = OrderedYAMLMap(pairs)
            guard let name = map.value(for: "name")?.stringValue,
                  let mountPath = map.value(for: "mountPath")?.stringValue else {
                return nil
            }
            return ContainerDraft.VolumeMount(
                name: name,
                mountPath: mountPath,
                readOnly: map.value(for: "readOnly")?.boolValue ?? false
            )
        }
    }

    private func podVolumes(
        owner: String,
        podSpec: OrderedYAMLMap,
        diagnostics: inout [Diagnostic]
    ) -> [String: String] {
        var claimsByVolumeName: [String: String] = [:]
        for item in podSpec.value(for: "volumes")?.sequenceValues ?? [] {
            guard let pairs = item.mappingPairs else {
                continue
            }
            let map = OrderedYAMLMap(pairs)
            guard let name = map.value(for: "name")?.stringValue else {
                continue
            }
            if let claimPairs = map.value(for: "persistentVolumeClaim")?.mappingPairs,
               let claim = OrderedYAMLMap(claimPairs).value(for: "claimName")?.stringValue {
                claimsByVolumeName[name] = claim
            } else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        code: "kubernetes-volume-source",
                        message: "\(owner) volume \(name) does not use a persistentVolumeClaim source and is not translated.",
                        suggestion: "Use a PersistentVolumeClaim for adapter-owned named volumes."
                    )
                )
            }
        }
        return claimsByVolumeName
    }

    // MARK: - Project assembly

    private func buildProject(
        scan: DocumentScan,
        sourceName: String,
        projectName: String,
        diagnostics: inout [Diagnostic]
    ) throws -> LocalDevProject {
        if scan.namespaces.count > 1 {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-namespace-collapse",
                    message: "Render declares namespaces \(scan.namespaces.sorted().joined(separator: ", ")); all objects collapse into one local project scope.",
                    suggestion: "Render one namespace per local project for predictable scoping."
                )
            )
        }

        var services: [LocalDevService] = []
        for workload in scan.workloads {
            let environment = resolveEnvironment(
                owner: workload.name,
                entries: workload.container.env,
                scan: scan,
                diagnostics: &diagnostics
            )
            let matches = matchingServices(for: workload.podLabels, name: workload.name, scan: scan)
            services.append(
                LocalDevService(
                    name: workload.name,
                    image: workload.container.image,
                    command: workload.container.args,
                    entrypoint: workload.container.command,
                    environment: environment,
                    mounts: mounts(
                        owner: workload.name,
                        container: workload.container,
                        podVolumes: workload.podVolumes,
                        diagnostics: &diagnostics
                    ),
                    ports: ports(owner: workload.name, services: matches, diagnostics: &diagnostics),
                    aliases: matches.map(\.name).filter { $0 != workload.name },
                    dependencies: dependencies(from: workload.annotations),
                    healthcheck: workload.container.healthcheck,
                    profiles: profiles(from: workload.annotations)
                )
            )
        }

        var jobs: [LocalDevJob] = []
        for job in scan.jobs {
            let environment = resolveEnvironment(
                owner: job.name,
                entries: job.container.env,
                scan: scan,
                diagnostics: &diagnostics
            )
            jobs.append(
                LocalDevJob(
                    name: job.name,
                    image: job.container.image,
                    command: job.container.command + job.container.args,
                    environment: environment,
                    mounts: mounts(
                        owner: job.name,
                        container: job.container,
                        podVolumes: job.podVolumes,
                        diagnostics: &diagnostics
                    ),
                    dependencies: dependencies(from: job.annotations),
                    completionPolicy: .runToCompletion,
                    profiles: profiles(from: job.annotations)
                )
            )
        }

        let workloadNames = Set(scan.workloads.map(\.name) + scan.jobs.map(\.name))
        for service in scan.services where !hasWorkloadMatch(service, scan: scan, workloadNames: workloadNames) {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "kubernetes-service-selector",
                    message: "Service \(service.name) does not select any translated workload and is ignored.",
                    suggestion: "Point spec.selector at a Deployment, StatefulSet, or Job pod label in the same render."
                )
            )
        }

        let profileSet = Set(services.flatMap(\.profiles) + jobs.flatMap(\.profiles))
        return LocalDevProject(
            id: projectName,
            name: projectName,
            sourceFiles: [sourceName],
            services: services,
            jobs: jobs,
            volumes: scan.volumes,
            routes: scan.routes,
            secrets: scan.secretOrder.map { LocalDevSecret(name: $0, source: sourceName) },
            configs: scan.configMapOrder.map { LocalDevConfig(name: $0, source: sourceName) },
            profiles: profileSet.sorted(),
            diagnostics: diagnostics
        )
    }

    private func resolveEnvironment(
        owner: String,
        entries: [EnvEntry],
        scan: DocumentScan,
        diagnostics: inout [Diagnostic]
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in entries {
            switch entry {
            case .value(let name, let value):
                environment[name] = value
            case .secretKey(let name, let secret, let key):
                if let value = scan.secrets[secret]?[key] {
                    environment[name] = value
                } else {
                    diagnostics.append(missingSource(owner: owner, env: name, kind: "Secret", source: "\(secret)/\(key)"))
                }
            case .configMapKey(let name, let configMap, let key):
                if let value = scan.configMaps[configMap]?[key] {
                    environment[name] = value
                } else {
                    diagnostics.append(missingSource(owner: owner, env: name, kind: "ConfigMap", source: "\(configMap)/\(key)"))
                }
            case .allSecretKeys(let secret):
                if let values = scan.secrets[secret] {
                    environment.merge(values) { _, new in new }
                } else {
                    diagnostics.append(missingSource(owner: owner, env: "envFrom", kind: "Secret", source: secret))
                }
            case .allConfigMapKeys(let configMap):
                if let values = scan.configMaps[configMap] {
                    environment.merge(values) { _, new in new }
                } else {
                    diagnostics.append(missingSource(owner: owner, env: "envFrom", kind: "ConfigMap", source: configMap))
                }
            case .unresolvable(let name):
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        code: "kubernetes-env-source",
                        message: "\(owner) env \(name) uses a valueFrom source outside the local-development subset and is dropped.",
                        suggestion: "Use plain values, secretKeyRef, or configMapKeyRef in the local render."
                    )
                )
            }
        }
        return environment
    }

    private func missingSource(owner: String, env: String, kind: String, source: String) -> Diagnostic {
        Diagnostic(
            severity: .blocking,
            code: "kubernetes-secret-resolution",
            message: "\(owner) env \(env) references \(kind) \(source), which cannot be loaded safely from this render.",
            suggestion: "Include the \(kind) document in the rendered output or inline a local-development value."
        )
    }

    private func mounts(
        owner: String,
        container: ContainerDraft,
        podVolumes: [String: String],
        diagnostics: inout [Diagnostic]
    ) -> [LocalDevMount] {
        container.volumeMounts.compactMap { mount in
            guard let claim = podVolumes[mount.name] else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        code: "kubernetes-volume-source",
                        message: "\(owner) volumeMount \(mount.name) has no persistentVolumeClaim-backed pod volume and is dropped.",
                        suggestion: "Back the mount with a PersistentVolumeClaim for adapter-owned named volumes."
                    )
                )
                return nil
            }
            return LocalDevMount(
                kind: .namedVolume,
                source: claim,
                target: mount.mountPath,
                readOnly: mount.readOnly
            )
        }
    }

    private func matchingServices(
        for podLabels: [String: String],
        name: String,
        scan: DocumentScan
    ) -> [ServiceDraft] {
        scan.services.filter { service in
            guard !service.selector.isEmpty else {
                return false
            }
            return service.selector.allSatisfy { key, value in
                podLabels[key] == value || (key == "app" && value == name && podLabels.isEmpty)
            }
        }
    }

    private func hasWorkloadMatch(
        _ service: ServiceDraft,
        scan: DocumentScan,
        workloadNames: Set<String>
    ) -> Bool {
        for workload in scan.workloads
        where !matchingServices(for: workload.podLabels, name: workload.name, scan: scan)
            .filter({ $0.name == service.name }).isEmpty {
            return true
        }
        return false
    }

    private func ports(
        owner: String,
        services: [ServiceDraft],
        diagnostics: inout [Diagnostic]
    ) -> [LocalDevPort] {
        var ports: [LocalDevPort] = []
        for service in services {
            guard let hostPortValue = service.annotations["cca.local/host-port"] else {
                continue
            }
            guard let hostPort = Int(hostPortValue) else {
                diagnostics.append(hostPortDiagnostic(service: service.name, reason: "is not an integer"))
                continue
            }
            guard service.ports.count == 1, let servicePort = service.ports.first else {
                diagnostics.append(hostPortDiagnostic(service: service.name, reason: "requires exactly one service port"))
                continue
            }
            ports.append(
                LocalDevPort(
                    hostIP: service.annotations["cca.local/host-ip"],
                    hostPort: hostPort,
                    containerPort: servicePort.targetPort ?? servicePort.port,
                    protocolName: servicePort.protocolName
                )
            )
        }
        return ports
    }

    private func hostPortDiagnostic(service: String, reason: String) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            code: "kubernetes-host-port-annotation",
            message: "Service \(service) cca.local/host-port \(reason); no deterministic host port is published.",
            suggestion: "Use one service port and an integer cca.local/host-port value."
        )
    }

    private func dependencies(from annotations: [String: String]) -> [LocalDevDependency] {
        guard let raw = annotations["cca.local/depends-on"], !raw.isEmpty else {
            return []
        }
        return raw.split(separator: ",").map { item in
            let parts = item.trimmingCharacters(in: .whitespaces)
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let target = String(parts[0])
            let condition: LocalDevDependencyCondition
            switch parts.count == 2 ? String(parts[1]) : "service_started" {
            case "service_healthy":
                condition = .serviceHealthy
            case "service_completed_successfully":
                condition = .serviceCompletedSuccessfully
            default:
                condition = .serviceStarted
            }
            return LocalDevDependency(target: target, condition: condition)
        }
    }

    private func profiles(from annotations: [String: String]) -> [String] {
        guard let profile = annotations["cca.local/profile"], !profile.isEmpty else {
            return []
        }
        return [profile]
    }

    // MARK: - Helpers

    private func stringMap(_ value: YAMLValue?) -> [String: String] {
        guard let pairs = value?.mappingPairs else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value.stringValue ?? "") })
    }

    private func stringArray(_ value: YAMLValue?) -> [String] {
        guard let value else {
            return []
        }
        if let string = value.stringValue {
            return [string]
        }
        return value.sequenceValues?.compactMap(\.stringValue) ?? []
    }

    static func splitDocuments(_ yaml: String) -> [String] {
        var documents: [String] = []
        var current: [Substring] = []
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if !current.isEmpty {
                    documents.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            documents.append(current.joined(separator: "\n"))
        }
        return documents
    }

    static func storageBytes(_ value: String?) -> Int64? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let multipliers: [(String, Int64)] = [
            ("Gi", 1024 * 1024 * 1024),
            ("Mi", 1024 * 1024),
            ("Ki", 1024)
        ]
        for (suffix, multiplier) in multipliers {
            if value.hasSuffix(suffix), let base = Int64(value.dropLast(suffix.count)) {
                return base * multiplier
            }
        }
        return Int64(value)
    }
}

public struct KubernetesSubsetFrontendResult: Equatable, Sendable {
    public let project: LocalDevProject
    public let diagnostics: [Diagnostic]

    public init(project: LocalDevProject, diagnostics: [Diagnostic] = []) {
        self.project = project
        self.diagnostics = diagnostics
    }
}

public enum KubernetesSubsetFrontendError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidUTF8(String)
    case invalidDocument(String)

    public var description: String {
        switch self {
        case .invalidUTF8(let source):
            return "Kubernetes render \(source) is not valid UTF-8."
        case .invalidDocument(let message):
            return message
        }
    }
}

private struct DocumentScan {
    var namespaces: Set<String> = []
    var secrets: [String: [String: String]] = [:]
    var secretOrder: [String] = []
    var configMaps: [String: [String: String]] = [:]
    var configMapOrder: [String] = []
    var volumes: [LocalDevVolume] = []
    var workloads: [WorkloadDraft] = []
    var jobs: [JobDraft] = []
    var services: [ServiceDraft] = []
    var routes: [LocalDevRoute] = []
}

private struct WorkloadDraft {
    let name: String
    let annotations: [String: String]
    let podLabels: [String: String]
    let podVolumes: [String: String]
    let container: ContainerDraft
}

private struct JobDraft {
    let name: String
    let annotations: [String: String]
    let podVolumes: [String: String]
    let container: ContainerDraft
}

private struct ServiceDraft {
    struct Port {
        let port: Int
        let targetPort: Int?
        let protocolName: String
    }

    let name: String
    let annotations: [String: String]
    let selector: [String: String]
    let ports: [Port]
}

private struct ContainerDraft {
    struct VolumeMount {
        let name: String
        let mountPath: String
        let readOnly: Bool
    }

    let image: String
    let command: [String]
    let args: [String]
    let env: [EnvEntry]
    let healthcheck: LocalDevHealthcheck?
    let volumeMounts: [VolumeMount]
}

private enum EnvEntry {
    case value(name: String, value: String)
    case secretKey(name: String, secret: String, key: String)
    case configMapKey(name: String, configMap: String, key: String)
    case allSecretKeys(secret: String)
    case allConfigMapKeys(configMap: String)
    case unresolvable(name: String)
}
