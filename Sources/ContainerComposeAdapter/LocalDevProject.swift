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
    public let diagnostics: [Diagnostic]

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
        profiles: [String] = [],
        diagnostics: [Diagnostic] = []
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
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceFiles
        case services
        case jobs
        case volumes
        case networks
        case routes
        case secrets
        case configs
        case profiles
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            sourceFiles: try container.decode([String].self, forKey: .sourceFiles),
            services: try container.decode([LocalDevService].self, forKey: .services),
            jobs: try container.decode([LocalDevJob].self, forKey: .jobs),
            volumes: try container.decode([LocalDevVolume].self, forKey: .volumes),
            networks: try container.decode([LocalDevNetwork].self, forKey: .networks),
            routes: try container.decode([LocalDevRoute].self, forKey: .routes),
            secrets: try container.decode([LocalDevSecret].self, forKey: .secrets),
            configs: try container.decode([LocalDevConfig].self, forKey: .configs),
            profiles: try container.decode([String].self, forKey: .profiles),
            diagnostics: try container.decodeIfPresent([Diagnostic].self, forKey: .diagnostics) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceFiles, forKey: .sourceFiles)
        try container.encode(services, forKey: .services)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(volumes, forKey: .volumes)
        try container.encode(networks, forKey: .networks)
        try container.encode(routes, forKey: .routes)
        try container.encode(secrets, forKey: .secrets)
        try container.encode(configs, forKey: .configs)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(diagnostics, forKey: .diagnostics)
    }

    public func runtimePlan() -> RuntimePlan {
        AppleNativePlanner().plan(self).runtimePlan
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
    public let resources: LocalDevResourcePolicy?
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
        resources: LocalDevResourcePolicy? = nil,
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
        self.resources = resources
        self.restartPolicy = restartPolicy
        self.profiles = profiles
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
    public let resources: LocalDevResourcePolicy?
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
        resources: LocalDevResourcePolicy? = nil,
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
        self.resources = resources
        self.profiles = profiles
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

public struct LocalDevResourcePolicy: Codable, Equatable, Sendable {
    public let cpuLimit: String?
    public let memoryLimitBytes: Int64?
    public let diskLimitBytes: Int64?

    public init(
        cpuLimit: String? = nil,
        memoryLimitBytes: Int64? = nil,
        diskLimitBytes: Int64? = nil
    ) {
        self.cpuLimit = cpuLimit
        self.memoryLimitBytes = memoryLimitBytes
        self.diskLimitBytes = diskLimitBytes
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
