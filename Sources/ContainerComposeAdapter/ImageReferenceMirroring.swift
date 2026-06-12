// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum DockerHubOfficialImageMirror {
    public static func validatedMirror(_ mirror: String) throws -> String {
        guard !mirror.contains("://") else {
            throw Phase6BenchmarkOptionsError.usage(
                "--docker-hub-mirror expects a registry host or host/path prefix without a URL scheme"
            )
        }
        return normalizedMirror(mirror)
    }

    public static func normalizedMirror(_ mirror: String) -> String {
        mirror.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func rewrite(image: String, mirror: String) -> String {
        let normalized = normalizedMirror(mirror)
        guard !normalized.isEmpty else {
            return image
        }

        for prefix in [
            "docker.io/library/",
            "registry-1.docker.io/library/",
            "index.docker.io/library/"
        ] where image.hasPrefix(prefix) {
            return "\(normalized)/library/\(image.dropFirst(prefix.count))"
        }

        for prefix in [
            "docker.io/",
            "registry-1.docker.io/",
            "index.docker.io/"
        ] where image.hasPrefix(prefix) {
            let repository = String(image.dropFirst(prefix.count))
            if isSingleComponentRepository(repository) {
                return "\(normalized)/library/\(repository)"
            }
            return image
        }

        if image.hasPrefix("library/") {
            return "\(normalized)/\(image)"
        }

        if !image.contains("/") {
            return "\(normalized)/library/\(image)"
        }

        return image
    }

    private static func isSingleComponentRepository(_ repository: String) -> Bool {
        let nameEnd = repository.firstIndex { character in
            character == ":" || character == "@"
        } ?? repository.endIndex
        return !repository[..<nameEnd].contains("/")
    }

    public static func rewrite(plan: RuntimePlan, mirror: String?) -> RuntimePlan {
        guard let mirror else {
            return plan
        }
        let normalized = normalizedMirror(mirror)
        guard !normalized.isEmpty else {
            return plan
        }

        let services = plan.services.map { service in
            ServicePlan(
                name: service.name,
                kind: service.kind,
                image: rewrite(image: service.image, mirror: normalized),
                command: service.command,
                environment: service.environment,
                ports: service.ports,
                mounts: service.mounts,
                readiness: service.readiness,
                dependencies: service.dependencies
            )
        }

        return RuntimePlan(
            project: plan.project,
            services: services,
            volumes: plan.volumes,
            diagnostics: plan.diagnostics
        )
    }
}
