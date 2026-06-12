// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct ProjectRuntimeStore: Sendable {
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

    public func requiredProjectSubdirectories(for project: ProjectName) -> [URL] {
        ["pod", "services", "jobs", "volumes", "ports", "logs", "metrics", "tmp"].map { name in
            projectDirectory(for: project).appendingPathComponent(name, isDirectory: true)
        }
    }

    public func cacheSubdirectories() -> [URL] {
        ["images", "rootfs-by-digest", "initfs", "kernels", "build"].map { name in
            cacheDirectory.appendingPathComponent(name, isDirectory: true)
        }
    }

    public func validateAdapterOwnedProjectDirectory(_ projectDirectory: URL) throws {
        let projectsRoot = projectsDirectory.standardizedFileURL.path
        let projectPath = projectDirectory.standardizedFileURL.path
        let isInsideProjectsRoot = projectPath == projectsRoot || projectPath.hasPrefix(projectsRoot + "/")
        guard isInsideProjectsRoot else {
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
}
