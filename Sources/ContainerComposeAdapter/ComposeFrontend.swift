// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct ComposeFrontend: Sendable {
    public init() {}

    public func parseProject(
        fileURL: URL,
        projectName: String? = nil
    ) throws -> ComposeFrontendResult {
        let data = try Data(contentsOf: fileURL)
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw ComposeFrontendError.invalidUTF8(fileURL.path)
        }
        return try parseProject(
            yaml: yaml,
            sourceName: fileURL.path,
            projectName: projectName ?? fileURL.deletingLastPathComponent().lastPathComponent
        )
    }

    public func parseProject(
        yaml: String,
        sourceName: String = "compose.yaml",
        projectName: String = "compose-project"
    ) throws -> ComposeFrontendResult {
        var parser = ComposeYAMLSubsetParser(yaml: yaml)
        let root = try parser.parse()
        guard let rootPairs = root.mappingPairs else {
            throw ComposeFrontendError.invalidDocument("Compose document must be a mapping.")
        }

        var diagnostics: [Diagnostic] = []
        let rootMap = OrderedYAMLMap(rootPairs)
        for key in rootMap.keys where !Self.supportedTopLevelKeys.contains(key) {
            diagnostics.append(unsupportedDiagnostic("compose.\(key)"))
        }

        let volumeNames = parseTopLevelVolumeNames(rootMap.value(for: "volumes"))
        let parsedVolumes = volumeNames.map { LocalDevVolume(name: $0) }
        let parsedServices = try parseServices(
            rootMap.value(for: "services"),
            topLevelVolumeNames: Set(volumeNames),
            diagnostics: &diagnostics
        )
        let profiles = Array(
            Set(parsedServices.services.flatMap(\.profiles) + parsedServices.jobs.flatMap(\.profiles))
        ).sorted()

        let project = LocalDevProject(
            id: projectName,
            name: projectName,
            sourceFiles: [sourceName],
            services: parsedServices.services,
            jobs: parsedServices.jobs,
            volumes: parsedVolumes,
            profiles: profiles,
            diagnostics: diagnostics
        )
        return ComposeFrontendResult(project: project, diagnostics: diagnostics)
    }

    public func parseProject(
        yaml data: Data,
        sourceName: String = "compose.yaml",
        projectName: String = "compose-project"
    ) throws -> ComposeFrontendResult {
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw ComposeFrontendError.invalidUTF8(sourceName)
        }
        return try parseProject(yaml: yaml, sourceName: sourceName, projectName: projectName)
    }

    private static let supportedTopLevelKeys = Set(["name", "services", "volumes"])
    private static let supportedServiceKeys = Set([
        "image",
        "build",
        "command",
        "entrypoint",
        "environment",
        "env_file",
        "ports",
        "volumes",
        "depends_on",
        "healthcheck",
        "profiles",
        "labels",
        "restart"
    ])

    private func parseServices(
        _ value: YAMLValue?,
        topLevelVolumeNames: Set<String>,
        diagnostics: inout [Diagnostic]
    ) throws -> (services: [LocalDevService], jobs: [LocalDevJob]) {
        guard let servicePairs = value?.mappingPairs else {
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "missing-compose-services",
                    message: "Compose document must define a services mapping.",
                    suggestion: "Add at least one service under services."
                )
            )
            return ([], [])
        }

        var services: [LocalDevService] = []
        var jobs: [LocalDevJob] = []
        for servicePair in servicePairs {
            let parsed = try parseService(
                name: servicePair.key,
                value: servicePair.value,
                topLevelVolumeNames: topLevelVolumeNames,
                diagnostics: &diagnostics
            )
            switch parsed {
            case .service(let service):
                services.append(service)
            case .job(let job):
                jobs.append(job)
            }
        }
        return (services, jobs)
    }

    private func parseService(
        name: String,
        value: YAMLValue,
        topLevelVolumeNames: Set<String>,
        diagnostics: inout [Diagnostic]
    ) throws -> ParsedComposeService {
        guard let pairs = value.mappingPairs else {
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "invalid-compose-service",
                    message: "services.\(name) must be a mapping.",
                    suggestion: "Use Compose service mapping syntax for \(name)."
                )
            )
            return .service(LocalDevService(name: name, image: ""))
        }

        let serviceMap = OrderedYAMLMap(pairs)
        for key in serviceMap.keys where !Self.supportedServiceKeys.contains(key) {
            diagnostics.append(unsupportedDiagnostic("services.\(name).\(key)"))
        }

        let image = serviceMap.value(for: "image")?.stringValue ?? ""
        if image.isEmpty && serviceMap.value(for: "build") == nil {
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "missing-compose-image",
                    message: "services.\(name) does not define an image.",
                    suggestion: "Use a prebuilt public image for the first Compose frontend slice."
                )
            )
        }

        let build = parseBuild(serviceMap.value(for: "build"))
        let command = parseCommand(serviceMap.value(for: "command"))
        let entrypoint = parseCommand(serviceMap.value(for: "entrypoint"))
        let environment = parseEnvironment(serviceMap.value(for: "environment"))
        let envFiles = parseStringArray(serviceMap.value(for: "env_file"))
        let mounts = parseMounts(serviceMap.value(for: "volumes"), topLevelVolumeNames: topLevelVolumeNames)
        let ports = parsePorts(serviceMap.value(for: "ports"))
        let dependencies = parseDependencies(serviceMap.value(for: "depends_on"))
        let healthcheck = parseHealthcheck(serviceMap.value(for: "healthcheck"))
        let profiles = parseStringArray(serviceMap.value(for: "profiles"))
        let labels = parseLabels(serviceMap.value(for: "labels"))
        let restartPolicy = parseRestartPolicy(serviceMap.value(for: "restart"))

        if isOneOffJob(name: name, labels: labels) {
            return .job(
                LocalDevJob(
                    name: name,
                    image: image,
                    build: build,
                    command: entrypoint + command,
                    environment: environment,
                    envFiles: envFiles,
                    mounts: mounts,
                    dependencies: dependencies,
                    completionPolicy: .runToCompletion,
                    profiles: profiles
                )
            )
        }

        return .service(
            LocalDevService(
                name: name,
                image: image,
                build: build,
                command: command,
                entrypoint: entrypoint,
                environment: environment,
                envFiles: envFiles,
                mounts: mounts,
                ports: ports,
                dependencies: dependencies,
                healthcheck: healthcheck,
                restartPolicy: restartPolicy,
                profiles: profiles
            )
        )
    }

    private func parseTopLevelVolumeNames(_ value: YAMLValue?) -> [String] {
        guard let pairs = value?.mappingPairs else {
            return []
        }
        return pairs.map(\.key)
    }

    private func parseBuild(_ value: YAMLValue?) -> LocalDevBuildSpec? {
        guard let value else {
            return nil
        }
        if let context = value.stringValue {
            return LocalDevBuildSpec(context: context)
        }
        guard let pairs = value.mappingPairs else {
            return nil
        }
        let map = OrderedYAMLMap(pairs)
        return LocalDevBuildSpec(
            context: map.value(for: "context")?.stringValue ?? ".",
            dockerfile: map.value(for: "dockerfile")?.stringValue,
            target: map.value(for: "target")?.stringValue,
            args: parseEnvironment(map.value(for: "args"))
        )
    }

    private func parseCommand(_ value: YAMLValue?) -> [String] {
        guard let value else {
            return []
        }
        if let string = value.stringValue {
            return ["sh", "-ec", string]
        }
        return value.sequenceValues?.compactMap(\.stringValue) ?? []
    }

    private func parseEnvironment(_ value: YAMLValue?) -> [String: String] {
        guard let value else {
            return [:]
        }
        if let pairs = value.mappingPairs {
            return Dictionary(uniqueKeysWithValues: pairs.map { pair in
                (pair.key, pair.value.stringValue ?? "")
            })
        }
        var environment: [String: String] = [:]
        for entry in value.sequenceValues ?? [] {
            guard let item = entry.stringValue else {
                continue
            }
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                environment[String(parts[0])] = String(parts[1])
            } else {
                environment[item] = ""
            }
        }
        return environment
    }

    private func parseStringArray(_ value: YAMLValue?) -> [String] {
        guard let value else {
            return []
        }
        if let string = value.stringValue {
            return [string]
        }
        return value.sequenceValues?.compactMap(\.stringValue) ?? []
    }

    private func parsePorts(_ value: YAMLValue?) -> [LocalDevPort] {
        (value?.sequenceValues ?? []).compactMap { item in
            if let string = item.stringValue {
                return parsePortString(string)
            }
            guard let pairs = item.mappingPairs else {
                return nil
            }
            let map = OrderedYAMLMap(pairs)
            guard let target = map.value(for: "target")?.intValue else {
                return nil
            }
            return LocalDevPort(
                hostIP: map.value(for: "host_ip")?.stringValue,
                hostPort: map.value(for: "published")?.intValue,
                containerPort: target,
                protocolName: map.value(for: "protocol")?.stringValue ?? "tcp"
            )
        }
    }

    private func parsePortString(_ value: String) -> LocalDevPort? {
        let protocolSplit = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let portPart = String(protocolSplit[0])
        let protocolName = protocolSplit.count == 2 ? String(protocolSplit[1]) : "tcp"
        let parts = portPart.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1:
            guard let containerPort = Int(parts[0]) else {
                return nil
            }
            return LocalDevPort(hostPort: nil, containerPort: containerPort, protocolName: protocolName)
        case 2:
            guard let containerPort = Int(parts[1]) else {
                return nil
            }
            return LocalDevPort(hostPort: Int(parts[0]), containerPort: containerPort, protocolName: protocolName)
        case 3:
            guard let containerPort = Int(parts[2]) else {
                return nil
            }
            return LocalDevPort(
                hostIP: parts[0].isEmpty ? nil : parts[0],
                hostPort: Int(parts[1]),
                containerPort: containerPort,
                protocolName: protocolName
            )
        default:
            return nil
        }
    }

    private func parseMounts(_ value: YAMLValue?, topLevelVolumeNames: Set<String>) -> [LocalDevMount] {
        (value?.sequenceValues ?? []).compactMap { item in
            if let string = item.stringValue {
                return parseMountString(string, topLevelVolumeNames: topLevelVolumeNames)
            }
            guard let pairs = item.mappingPairs else {
                return nil
            }
            let map = OrderedYAMLMap(pairs)
            guard let target = map.value(for: "target")?.stringValue else {
                return nil
            }
            let type = map.value(for: "type")?.stringValue ?? "volume"
            let source = map.value(for: "source")?.stringValue ?? map.value(for: "src")?.stringValue
            let readOnly = map.value(for: "read_only")?.boolValue ?? false
            switch type {
            case "bind":
                return LocalDevMount(kind: .bind, source: source, target: target, readOnly: readOnly)
            case "tmpfs":
                return LocalDevMount(kind: .tmpfs, source: source, target: target, readOnly: readOnly)
            default:
                return LocalDevMount(kind: .namedVolume, source: source, target: target, readOnly: readOnly)
            }
        }
    }

    private func parseMountString(_ value: String, topLevelVolumeNames: Set<String>) -> LocalDevMount? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else {
            return LocalDevMount(kind: .namedVolume, source: nil, target: value)
        }
        let source = parts[0]
        let target = parts[1]
        let mode = parts.dropFirst(2).joined(separator: ":")
        let readOnly = mode.split(separator: ",").contains("ro") || mode == "ro"
        let kind: LocalDevMountKind = isBindMountSource(source, topLevelVolumeNames: topLevelVolumeNames) ? .bind : .namedVolume
        return LocalDevMount(kind: kind, source: source, target: target, readOnly: readOnly)
    }

    private func isBindMountSource(_ source: String, topLevelVolumeNames: Set<String>) -> Bool {
        if topLevelVolumeNames.contains(source) {
            return false
        }
        return source.hasPrefix(".")
            || source.hasPrefix("/")
            || source.hasPrefix("~")
    }

    private func parseDependencies(_ value: YAMLValue?) -> [LocalDevDependency] {
        guard let value else {
            return []
        }
        if let sequence = value.sequenceValues {
            return sequence.compactMap { item in
                guard let name = item.stringValue else {
                    return nil
                }
                return LocalDevDependency(target: name, condition: .serviceStarted)
            }
        }
        guard let pairs = value.mappingPairs else {
            return []
        }
        return pairs.map { pair in
            if let dependencyMap = pair.value.mappingPairs {
                let map = OrderedYAMLMap(dependencyMap)
                return LocalDevDependency(
                    target: pair.key,
                    condition: parseDependencyCondition(map.value(for: "condition")?.stringValue),
                    required: map.value(for: "required")?.boolValue ?? true
                )
            }
            return LocalDevDependency(target: pair.key, condition: .serviceStarted)
        }
    }

    private func parseDependencyCondition(_ value: String?) -> LocalDevDependencyCondition {
        switch value {
        case "service_healthy":
            return .serviceHealthy
        case "service_completed_successfully":
            return .serviceCompletedSuccessfully
        default:
            return .serviceStarted
        }
    }

    private func parseHealthcheck(_ value: YAMLValue?) -> LocalDevHealthcheck? {
        guard let pairs = value?.mappingPairs else {
            return nil
        }
        let map = OrderedYAMLMap(pairs)
        let test = normalizeHealthcheckTest(map.value(for: "test"))
        guard !test.isEmpty else {
            return nil
        }
        return LocalDevHealthcheck(
            test: test,
            intervalSeconds: parseDurationSeconds(map.value(for: "interval")?.stringValue, defaultValue: 30),
            timeoutSeconds: parseDurationSeconds(map.value(for: "timeout")?.stringValue, defaultValue: 30),
            retries: map.value(for: "retries")?.intValue ?? 3,
            startPeriodSeconds: parseDurationSeconds(map.value(for: "start_period")?.stringValue, defaultValue: 0)
        )
    }

    private func normalizeHealthcheckTest(_ value: YAMLValue?) -> [String] {
        if let string = value?.stringValue {
            return ["sh", "-ec", string]
        }
        let values = value?.sequenceValues?.compactMap(\.stringValue) ?? []
        guard let first = values.first else {
            return []
        }
        switch first.uppercased() {
        case "CMD-SHELL":
            return ["sh", "-ec", values.dropFirst().joined(separator: " ")]
        case "CMD":
            return Array(values.dropFirst())
        case "NONE":
            return []
        default:
            return values
        }
    }

    private func parseDurationSeconds(_ value: String?, defaultValue: Double) -> Double {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return defaultValue
        }
        if let numeric = Double(rawValue) {
            return numeric
        }
        if rawValue.hasSuffix("ms"),
           let numeric = Double(rawValue.dropLast(2)) {
            return numeric / 1000
        }
        if rawValue.hasSuffix("s"),
           let numeric = Double(rawValue.dropLast()) {
            return numeric
        }
        if rawValue.hasSuffix("m"),
           let numeric = Double(rawValue.dropLast()) {
            return numeric * 60
        }
        if rawValue.hasSuffix("h"),
           let numeric = Double(rawValue.dropLast()) {
            return numeric * 3600
        }
        return defaultValue
    }

    private func parseLabels(_ value: YAMLValue?) -> [String: String] {
        parseEnvironment(value)
    }

    private func parseRestartPolicy(_ value: YAMLValue?) -> LocalDevRestartPolicy {
        switch value?.stringValue {
        case "no":
            return .no
        case "on-failure":
            return .onFailure
        case "always":
            return .always
        default:
            return .unlessStopped
        }
    }

    private func isOneOffJob(name: String, labels: [String: String]) -> Bool {
        let role = labels["com.container-compose-adapter.pilot.role"]?.lowercased()
        return role == "migrate" || role == "seed" || role == "job" || role == "one-off-job"
    }

    private func unsupportedDiagnostic(_ feature: String) -> Diagnostic {
        Diagnostic.unsupported(
            feature,
            suggestion: "Remove this field or add explicit support in a follow-up Compose compatibility slice."
        )
    }
}

public struct ComposeFrontendResult: Equatable, Sendable {
    public let project: LocalDevProject
    public let diagnostics: [Diagnostic]

    public init(project: LocalDevProject, diagnostics: [Diagnostic] = []) {
        self.project = project
        self.diagnostics = diagnostics
    }
}

public enum ComposeFrontendError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidUTF8(String)
    case invalidDocument(String)

    public var description: String {
        switch self {
        case .invalidUTF8(let source):
            return "Compose file \(source) is not valid UTF-8."
        case .invalidDocument(let message):
            return message
        }
    }
}

private enum ParsedComposeService {
    case service(LocalDevService)
    case job(LocalDevJob)
}

private struct OrderedYAMLMap {
    let pairs: [YAMLPair]

    init(_ pairs: [YAMLPair]) {
        self.pairs = pairs
    }

    var keys: [String] {
        pairs.map(\.key)
    }

    func value(for key: String) -> YAMLValue? {
        pairs.last { $0.key == key }?.value
    }
}

private struct ComposeYAMLSubsetParser {
    private let lines: [YAMLLine]
    private var index = 0

    init(yaml: String) {
        self.lines = yaml
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, line in
                let raw = String(line)
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    return nil
                }
                let indent = raw.prefix { $0 == " " }.count
                return YAMLLine(
                    number: offset + 1,
                    indent: indent,
                    content: String(raw.dropFirst(indent)),
                    raw: raw
                )
            }
    }

    mutating func parse() throws -> YAMLValue {
        guard let first = lines.first else {
            return .mapping([])
        }
        return try parseNode(indent: first.indent)
    }

    private mutating func parseNode(indent: Int) throws -> YAMLValue {
        guard index < lines.count else {
            return .mapping([])
        }
        if lines[index].content.hasPrefix("- ") {
            return try parseSequence(indent: indent)
        }
        return try parseMapping(indent: indent)
    }

    private mutating func parseMapping(indent: Int) throws -> YAMLValue {
        var pairs: [YAMLPair] = []
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, !line.content.hasPrefix("- ") else {
                break
            }
            let entry = try splitKeyValue(line)
            if let rawValue = entry.value {
                if rawValue.hasPrefix("|") {
                    let scalar = parseBlockScalar(parentIndent: line.indent)
                    pairs.append(YAMLPair(key: entry.key, value: .scalar(scalar)))
                } else {
                    pairs.append(YAMLPair(key: entry.key, value: try parseInlineValue(rawValue, line: line)))
                    index += 1
                }
            } else {
                index += 1
                if index < lines.count, lines[index].indent > line.indent {
                    let child = try parseNode(indent: lines[index].indent)
                    pairs.append(YAMLPair(key: entry.key, value: child))
                } else {
                    pairs.append(YAMLPair(key: entry.key, value: .mapping([])))
                }
            }
        }
        return .mapping(pairs)
    }

    private mutating func parseSequence(indent: Int) throws -> YAMLValue {
        var values: [YAMLValue] = []
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, line.content.hasPrefix("- ") else {
                break
            }
            let rawValue = String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if rawValue.isEmpty {
                index += 1
                if index < lines.count, lines[index].indent > line.indent {
                    values.append(try parseNode(indent: lines[index].indent))
                } else {
                    values.append(.null)
                }
            } else if rawValue.hasPrefix("|") {
                values.append(.scalar(parseBlockScalar(parentIndent: line.indent)))
            } else {
                values.append(try parseInlineValue(rawValue, line: line))
                index += 1
            }
        }
        return .sequence(values)
    }

    private func splitKeyValue(_ line: YAMLLine) throws -> (key: String, value: String?) {
        guard let colon = line.content.firstIndex(of: ":") else {
            throw ComposeFrontendError.invalidDocument("Line \(line.number) is not a YAML mapping entry.")
        }
        let rawKey = String(line.content[..<colon]).trimmingCharacters(in: .whitespaces)
        let rawValue = String(line.content[line.content.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)
        let key = unquote(rawKey)
        return (key, rawValue.isEmpty ? nil : rawValue)
    }

    private mutating func parseBlockScalar(parentIndent: Int) -> String {
        index += 1
        guard index < lines.count else {
            return ""
        }
        let contentIndent = lines[index].indent
        var blockLines: [String] = []
        while index < lines.count, lines[index].indent > parentIndent {
            let raw = lines[index].raw
            let dropCount = min(contentIndent, raw.prefix { $0 == " " }.count)
            blockLines.append(String(raw.dropFirst(dropCount)))
            index += 1
        }
        return blockLines.joined(separator: "\n") + (blockLines.isEmpty ? "" : "\n")
    }

    private func parseInlineValue(_ value: String, line: YAMLLine) throws -> YAMLValue {
        if value == "null" || value == "~" {
            return .null
        }
        if value == "true" {
            return .bool(true)
        }
        if value == "false" {
            return .bool(false)
        }
        if value.hasPrefix("[") {
            guard value.hasSuffix("]") else {
                throw ComposeFrontendError.invalidDocument("Line \(line.number) has an unterminated inline sequence.")
            }
            return .sequence(try parseInlineSequence(value, line: line))
        }
        return .scalar(unquote(value))
    }

    private func parseInlineSequence(_ value: String, line: YAMLLine) throws -> [YAMLValue] {
        let inner = value.dropFirst().dropLast()
        var items: [String] = []
        var current = ""
        var quote: Character?
        var previousWasEscape = false
        for character in inner {
            if previousWasEscape {
                current.append(character)
                previousWasEscape = false
                continue
            }
            if character == "\\" {
                current.append(character)
                previousWasEscape = true
                continue
            }
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                current.append(character)
                continue
            }
            if character == ",", quote == nil {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        guard quote == nil else {
            throw ComposeFrontendError.invalidDocument("Line \(line.number) has an unterminated quoted string.")
        }
        if !current.isEmpty {
            items.append(current.trimmingCharacters(in: .whitespaces))
        }
        return try items.map { item in
            try parseInlineValue(item, line: line)
        }
    }
}

private struct YAMLLine {
    let number: Int
    let indent: Int
    let content: String
    let raw: String
}

private struct YAMLPair {
    let key: String
    let value: YAMLValue
}

private indirect enum YAMLValue {
    case mapping([YAMLPair])
    case sequence([YAMLValue])
    case scalar(String)
    case bool(Bool)
    case null

    var mappingPairs: [YAMLPair]? {
        if case .mapping(let pairs) = self {
            return pairs
        }
        return nil
    }

    var sequenceValues: [YAMLValue]? {
        if case .sequence(let values) = self {
            return values
        }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .scalar(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return ""
        case .mapping, .sequence:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .scalar(let value):
            if value == "true" {
                return true
            }
            if value == "false" {
                return false
            }
            return nil
        case .mapping, .sequence, .null:
            return nil
        }
    }

    var intValue: Int? {
        stringValue.flatMap(Int.init)
    }
}

private func unquote(_ value: String) -> String {
    if value.count >= 2, value.first == "\"", value.last == "\"" {
        let body = value.dropFirst().dropLast()
        return body
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    if value.count >= 2, value.first == "'", value.last == "'" {
        return value.dropFirst().dropLast().replacingOccurrences(of: "''", with: "'")
    }
    return value
}
