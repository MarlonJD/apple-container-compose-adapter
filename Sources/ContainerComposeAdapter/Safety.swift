// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum SecretRedactor {
    private static let secretMarkers = [
        "PASSWORD",
        "TOKEN",
        "SECRET",
        "KEY",
        "CREDENTIAL",
        "PRIVATE",
        "AUTH",
        "SESSION"
    ]

    public static func redact(_ value: String, key: String) -> String {
        let uppercasedKey = key.uppercased()
        guard secretMarkers.contains(where: { uppercasedKey.contains($0) }) else {
            return value
        }
        return "<redacted>"
    }
}

public enum MountSafetyAnalyzer {
    public static func diagnostics(for mount: MountPlan, fileManager: FileManager = .default) -> [Diagnostic] {
        guard mount.kind == .bind else {
            return []
        }
        var diagnostics: [Diagnostic] = []
        let source = NSString(string: mount.source).expandingTildeInPath
        let standardized = URL(fileURLWithPath: source).standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        let broadMounts = ["/", "/Users", home]
        if broadMounts.contains(standardized) {
            diagnostics.append(
                Diagnostic(
                    severity: .warning,
                    code: "broad-bind-mount",
                    message: "Bind mount \(mount.source) exposes a broad host path.",
                    suggestion: "Mount the smallest project-local directory that the service needs."
                )
            )
        }

        let credentialMarkers = [
            "/.ssh",
            "/.docker",
            "/.aws",
            "/.config/gcloud",
            "/Library/Keychains",
            "/login.keychain"
        ]
        if credentialMarkers.contains(where: { standardized.contains($0) }) {
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "credential-bind-mount",
                    message: "Bind mount \(mount.source) appears to expose host credentials.",
                    suggestion: "Use a documented secret/config mechanism instead of mounting credential directories."
                )
            )
        }

        if !fileManager.fileExists(atPath: standardized) {
            diagnostics.append(
                Diagnostic(
                    severity: .blocking,
                    code: "missing-bind-mount-source",
                    message: "Bind mount source \(mount.source) does not exist.",
                    suggestion: "Create the source path or remove the mount from the selected Compose service."
                )
            )
        }
        return diagnostics
    }
}

public enum ImageReferencePolicy {
    public static func diagnostics(for image: String) -> [Diagnostic] {
        if isPublicImageReference(image) {
            return []
        }
        return [
            Diagnostic(
                severity: .blocking,
                code: "non-public-image-reference",
                message: "Image \(image) is not accepted by the public-image LinuxPod path.",
                suggestion: "Use docker.io/library, mirror.gcr.io/library, or another explicitly allowed public fixture image."
            )
        ]
    }

    public static func isPublicImageReference(_ image: String) -> Bool {
        let allowedPrefixes = [
            "docker.io/library/",
            "mirror.gcr.io/library/",
            "ghcr.io/apple/containerization/"
        ]
        if allowedPrefixes.contains(where: { image.hasPrefix($0) }) {
            return true
        }
        let slashCount = image.filter { $0 == "/" }.count
        return slashCount == 0 || (slashCount == 1 && !image.split(separator: "/")[0].contains("."))
    }
}
