// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public final class RuntimeLogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    public init() {}

    public func appendStdout(_ data: Data) {
        append(data, to: \.stdout)
    }

    public func appendStderr(_ data: Data) {
        append(data, to: \.stderr)
    }

    public func stdoutTail(maxCharacters: Int = 512) -> String {
        tail(lock.withLock { stdout }, maxCharacters: maxCharacters)
    }

    public func stderrTail(maxCharacters: Int = 512) -> String {
        tail(lock.withLock { stderr }, maxCharacters: maxCharacters)
    }

    public func evidenceMetadata(exitCode: Int32, maxPreviewCharacters: Int = 512) -> [String: String] {
        let snapshot = lock.withLock {
            (stdout: stdout, stderr: stderr)
        }
        return [
            "exitCode": "\(exitCode)",
            "logs": "captured",
            "stdoutBytes": "\(snapshot.stdout.count)",
            "stderrBytes": "\(snapshot.stderr.count)",
            "stdoutPreview": preview(snapshot.stdout, maxCharacters: maxPreviewCharacters),
            "stderrPreview": preview(snapshot.stderr, maxCharacters: maxPreviewCharacters)
        ]
    }

    private func append(_ data: Data, to keyPath: ReferenceWritableKeyPath<RuntimeLogCapture, Data>) {
        lock.withLock {
            self[keyPath: keyPath].append(data)
        }
    }

    private func preview(_ data: Data, maxCharacters: Int) -> String {
        guard maxCharacters >= 0 else {
            return ""
        }
        let text = String(decoding: data, as: UTF8.self)
        guard text.count > maxCharacters else {
            return text
        }
        return "\(text.prefix(maxCharacters))..."
    }

    private func tail(_ data: Data, maxCharacters: Int) -> String {
        guard maxCharacters >= 0 else {
            return ""
        }
        let text = String(decoding: data, as: UTF8.self)
        guard text.count > maxCharacters else {
            return text
        }
        return "...\(text.suffix(maxCharacters))"
    }
}
