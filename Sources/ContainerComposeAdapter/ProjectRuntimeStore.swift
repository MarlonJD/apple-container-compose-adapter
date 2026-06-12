// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct ProjectRuntimeStore: Sendable {
    public static let adapterOwnedRuntimePrefix = "cca-linuxpod-"
    public static let sentinelFileName = ".container-compose-adapter-owned"

    public let baseDirectory: URL

    public init(
        baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ContainerComposeAdapter", isDirectory: true)
    ) {
        self.baseDirectory = baseDirectory
    }

    public var cacheDirectory: URL {
        baseDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    public var imageCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("images", isDirectory: true)
    }

    public var rootfsCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("rootfs-by-digest", isDirectory: true)
    }

    public var initfsCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("initfs", isDirectory: true)
    }

    public var kernelsCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("kernels", isDirectory: true)
    }

    public var buildCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("build", isDirectory: true)
    }

    public var projectsDirectory: URL {
        baseDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    public func projectDirectory(for project: ProjectName) -> URL {
        projectsDirectory.appendingPathComponent(project.sanitized, isDirectory: true)
    }

    public func projectSentinelURL(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent(Self.sentinelFileName)
    }

    public func projectStateURL(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("project-state.json")
    }

    public func projectStorageURL(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("project-storage.ext4")
    }

    public func podDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("pod", isDirectory: true)
    }

    public func servicesDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("services", isDirectory: true)
    }

    public func jobsDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("jobs", isDirectory: true)
    }

    public func volumesDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("volumes", isDirectory: true)
    }

    public func volumeDirectory(for project: ProjectName, volumeName: String) -> URL {
        volumesDirectory(for: project).appendingPathComponent(ProjectName(volumeName).sanitized, isDirectory: true)
    }

    public func portsDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("ports", isDirectory: true)
    }

    public func logsDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("logs", isDirectory: true)
    }

    public func metricsDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("metrics", isDirectory: true)
    }

    public func tmpDirectory(for project: ProjectName) -> URL {
        projectDirectory(for: project).appendingPathComponent("tmp", isDirectory: true)
    }

    public func requiredProjectSubdirectories(for project: ProjectName) -> [URL] {
        [
            podDirectory(for: project),
            servicesDirectory(for: project),
            jobsDirectory(for: project),
            volumesDirectory(for: project),
            portsDirectory(for: project),
            logsDirectory(for: project),
            metricsDirectory(for: project),
            tmpDirectory(for: project)
        ]
    }

    public func cacheSubdirectories() -> [URL] {
        [
            imageCacheDirectory,
            rootfsCacheDirectory,
            initfsCacheDirectory,
            kernelsCacheDirectory,
            buildCacheDirectory
        ]
    }

    public func rootfsCacheURL(imageReference: String) -> URL {
        rootfsCacheDirectory.appendingPathComponent("\(cacheKey(for: imageReference)).ext4")
    }

    public func adapterOwnedRuntimeName(for project: ProjectName) -> String {
        project.adapterOwnedName(prefix: Self.adapterOwnedRuntimePrefix)
    }

    public func isProjectRuntimePath(_ url: URL) -> Bool {
        isStrictDescendant(url, of: projectsDirectory)
    }

    public func isReusableCachePath(_ url: URL) -> Bool {
        isStrictDescendant(url, of: cacheDirectory)
    }

    public func validateAdapterOwnedProjectDirectory(_ projectDirectory: URL) throws {
        let projectsRoot = canonicalPath(projectsDirectory)
        let projectPath = canonicalPath(projectDirectory)
        guard projectPath != projectsRoot else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing cleanup for \(projectPath) because it is not a project directory under \(projectsRoot)."
            )
        }
        guard isStrictDescendant(projectDirectory, of: projectsDirectory) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing cleanup for \(projectPath) because it is outside \(projectsRoot)."
            )
        }

        let sentinel = projectDirectory.appendingPathComponent(Self.sentinelFileName)
        guard FileManager.default.fileExists(atPath: sentinel.path) else {
            throw RuntimeBackendError.runtimeUnavailable(
                "Refusing cleanup for \(projectDirectory.path) because the adapter-owned sentinel is missing."
            )
        }
    }

    private func cacheKey(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        var result = ""
        var previousWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            if allowed.contains(scalar) {
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

    private func isStrictDescendant(_ child: URL, of parent: URL) -> Bool {
        let parentPath = canonicalPath(parent)
        let childPath = canonicalPath(child)
        return childPath.hasPrefix(parentPath + "/")
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

public enum ProjectSessionLifecycle: String, Codable, Equatable, Sendable {
    case persistentLinuxPod = "persistent-linuxpod"
}

public struct ProjectSessionPaths: Codable, Equatable, Sendable {
    public let projectDirectory: String
    public let sentinelFile: String
    public let projectStateFile: String
    public let projectStorageFile: String
    public let runtimeStateDirectories: [String: String]
    public let reusableCacheDirectories: [String: String]
    public let volumeDirectories: [String: String]

    public init(
        projectDirectory: String,
        sentinelFile: String,
        projectStateFile: String,
        projectStorageFile: String,
        runtimeStateDirectories: [String: String],
        reusableCacheDirectories: [String: String],
        volumeDirectories: [String: String]
    ) {
        self.projectDirectory = projectDirectory
        self.sentinelFile = sentinelFile
        self.projectStateFile = projectStateFile
        self.projectStorageFile = projectStorageFile
        self.runtimeStateDirectories = runtimeStateDirectories
        self.reusableCacheDirectories = reusableCacheDirectories
        self.volumeDirectories = volumeDirectories
    }
}

public struct ProjectSessionPlan: Codable, Equatable, Sendable {
    public let localDevProjectID: String
    public let displayName: String
    public let runtimeResourceName: String
    public let lifecycle: ProjectSessionLifecycle
    public let paths: ProjectSessionPaths

    public init(
        localDevProjectID: String,
        displayName: String,
        runtimeResourceName: String,
        lifecycle: ProjectSessionLifecycle,
        paths: ProjectSessionPaths
    ) {
        self.localDevProjectID = localDevProjectID
        self.displayName = displayName
        self.runtimeResourceName = runtimeResourceName
        self.lifecycle = lifecycle
        self.paths = paths
    }
}

public struct ProjectSessionManager: Sendable {
    public let store: ProjectRuntimeStore

    public init(store: ProjectRuntimeStore = ProjectRuntimeStore()) {
        self.store = store
    }

    public func planSession(for project: LocalDevProject) -> ProjectSessionPlan {
        planSession(
            localDevProjectID: project.id,
            displayName: project.name,
            volumes: project.volumes.map(\.name)
        )
    }

    public func planSession(for plan: RuntimePlan) -> ProjectSessionPlan {
        planSession(
            localDevProjectID: plan.project.sanitized,
            displayName: plan.project.rawValue,
            volumes: plan.volumes.map(\.name)
        )
    }

    private func planSession(
        localDevProjectID: String,
        displayName: String,
        volumes: [String]
    ) -> ProjectSessionPlan {
        let project = ProjectName(localDevProjectID)
        let runtimeDirectories = Dictionary(
            uniqueKeysWithValues: [
                ("pod", store.podDirectory(for: project).path),
                ("services", store.servicesDirectory(for: project).path),
                ("jobs", store.jobsDirectory(for: project).path),
                ("volumes", store.volumesDirectory(for: project).path),
                ("ports", store.portsDirectory(for: project).path),
                ("logs", store.logsDirectory(for: project).path),
                ("metrics", store.metricsDirectory(for: project).path),
                ("tmp", store.tmpDirectory(for: project).path)
            ]
        )
        let cacheDirectories = Dictionary(
            uniqueKeysWithValues: [
                ("images", store.imageCacheDirectory.path),
                ("rootfs-by-digest", store.rootfsCacheDirectory.path),
                ("initfs", store.initfsCacheDirectory.path),
                ("kernels", store.kernelsCacheDirectory.path),
                ("build", store.buildCacheDirectory.path)
            ]
        )
        let volumeDirectories = Dictionary(
            uniqueKeysWithValues: volumes.map { volume in
                (volume, store.volumeDirectory(for: project, volumeName: volume).path)
            }
        )

        return ProjectSessionPlan(
            localDevProjectID: localDevProjectID,
            displayName: displayName,
            runtimeResourceName: store.adapterOwnedRuntimeName(for: project),
            lifecycle: .persistentLinuxPod,
            paths: ProjectSessionPaths(
                projectDirectory: store.projectDirectory(for: project).path,
                sentinelFile: store.projectSentinelURL(for: project).path,
                projectStateFile: store.projectStateURL(for: project).path,
                projectStorageFile: store.projectStorageURL(for: project).path,
                runtimeStateDirectories: runtimeDirectories,
                reusableCacheDirectories: cacheDirectories,
                volumeDirectories: volumeDirectories
            )
        )
    }
}
