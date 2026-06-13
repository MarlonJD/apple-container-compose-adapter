// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Darwin
import Foundation

public enum RootfsMaterializationError: Error, Equatable, CustomStringConvertible {
    case sourceMissing(String)
    case sourceAndDestinationSame(String)
    case destinationOutsideAdapterOwnedRoot(String, String)

    public var description: String {
        switch self {
        case .sourceMissing(let path):
            return "Rootfs materialization source does not exist: \(path)"
        case .sourceAndDestinationSame(let path):
            return "Rootfs materialization source and destination are the same path: \(path)"
        case .destinationOutsideAdapterOwnedRoot(let destination, let root):
            return "Refusing to materialize rootfs outside adapter-owned root \(root): \(destination)"
        }
    }
}

public struct RootfsMaterializationContext: Equatable, Sendable {
    public let adapterOwnedRoot: URL
    public let phase: RootfsMaterializationPhase
    public let publicCloneAPIsAvailable: Bool

    public init(
        adapterOwnedRoot: URL,
        phase: RootfsMaterializationPhase,
        publicCloneAPIsAvailable: Bool = true
    ) {
        self.adapterOwnedRoot = adapterOwnedRoot
        self.phase = phase
        self.publicCloneAPIsAvailable = publicCloneAPIsAvailable
    }
}

public struct RootfsMaterializationResult: Equatable, Sendable {
    public let requestedStrategy: RootfsMaterializationStrategy
    public let actualStrategy: RootfsMaterializationStrategy
    public let fallbackStrategy: RootfsMaterializationStrategy?
    public let fallbackReason: String?
    public let cloneSupported: Bool
    public let cloneAttempted: Bool
    public let cloneReturnedSuccess: Bool
    public let cloneVerified: Bool
    public let cloneVerificationStrength: RootfsCloneVerificationStrength
    public let cloneSucceeded: Bool
    public let copyAttempted: Bool
    public let copySucceeded: Bool
    public let publicCloneAPIMissing: Bool
    public let byteForByteCopyAvoided: EvidenceTruthValue
    public let rootfsWorkAvoided: EvidenceTruthValue
    public let durationSeconds: Double
    public let sourceBytes: UInt64?
    public let destinationBytes: UInt64?
    public let apparentSizeBytes: UInt64?
    public let allocatedSizeBytes: UInt64?
    public let bytesCopiedIfKnown: UInt64?
    public let sourceAndDestinationSameVolume: Bool?
    public let sourceUnchanged: EvidenceTruthValue

    public var diagnostics: RootfsMaterializationDiagnostics {
        RootfsMaterializationDiagnostics(
            requestedStrategy: requestedStrategy,
            actualStrategy: actualStrategy,
            fallbackStrategy: fallbackStrategy,
            fallbackReason: fallbackReason,
            cloneSupported: cloneSupported,
            cloneAttempted: cloneAttempted,
            cloneReturnedSuccess: cloneReturnedSuccess,
            cloneVerified: cloneVerified,
            cloneVerificationStrength: cloneVerificationStrength,
            cloneSucceeded: cloneSucceeded,
            copyAttempted: copyAttempted,
            copySucceeded: copySucceeded,
            publicCloneAPIMissing: publicCloneAPIMissing,
            byteForByteCopyAvoided: byteForByteCopyAvoided,
            rootfsWorkAvoided: rootfsWorkAvoided
        )
    }
}

public struct RootfsMaterializer: Sendable {
    public init() {}

    public func materialize(
        source: URL,
        destination: URL,
        strategy: RootfsMaterializationStrategy,
        context: RootfsMaterializationContext
    ) async throws -> RootfsMaterializationResult {
        let sourceURL = source.standardizedFileURL
        let destinationURL = destination.standardizedFileURL
        let adapterRoot = context.adapterOwnedRoot.standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw RootfsMaterializationError.sourceMissing(source.path)
        }
        guard sourceURL.path != destinationURL.path else {
            throw RootfsMaterializationError.sourceAndDestinationSame(source.path)
        }
        guard isStrictDescendant(destinationURL, of: adapterRoot) else {
            throw RootfsMaterializationError.destinationOutsideAdapterOwnedRoot(destination.path, context.adapterOwnedRoot.path)
        }

        let sourceSignatureBefore = fileSignature(sourceURL)
        let sourceBytes = fileSize(sourceURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sameVolume = sameVolume(sourceURL, destinationURL.deletingLastPathComponent())
        let started = Date()

        if shouldUseFullCopy(strategy) {
            try copyReplacing(source: sourceURL, destination: destinationURL)
            return result(
                requestedStrategy: strategy,
                actualStrategy: strategy == .fileManagerCopy ? .fileManagerCopy : .fullCopy,
                fallbackStrategy: nil,
                fallbackReason: nil,
                cloneSupported: false,
                cloneAttempted: false,
                cloneReturnedSuccess: false,
                cloneVerified: false,
                cloneVerificationStrength: .notApplicable,
                cloneSucceeded: false,
                copyAttempted: true,
                copySucceeded: true,
                publicCloneAPIMissing: false,
                byteForByteCopyAvoided: .false,
                rootfsWorkAvoided: .false,
                started: started,
                source: sourceURL,
                sourceBytes: sourceBytes,
                destination: destinationURL,
                sameVolume: sameVolume,
                sourceSignatureBefore: sourceSignatureBefore,
                bytesCopiedIfKnown: fileSize(destinationURL)
            )
        }

        guard context.publicCloneAPIsAvailable else {
            try copyReplacing(source: sourceURL, destination: destinationURL)
            return result(
                requestedStrategy: strategy,
                actualStrategy: .fullCopy,
                fallbackStrategy: .fullCopy,
                fallbackReason: "public clone API unavailable; fell back to fullCopy",
                cloneSupported: false,
                cloneAttempted: false,
                cloneReturnedSuccess: false,
                cloneVerified: false,
                cloneVerificationStrength: .notApplicable,
                cloneSucceeded: false,
                copyAttempted: true,
                copySucceeded: true,
                publicCloneAPIMissing: true,
                byteForByteCopyAvoided: .false,
                rootfsWorkAvoided: .false,
                started: started,
                source: sourceURL,
                sourceBytes: sourceBytes,
                destination: destinationURL,
                sameVolume: sameVolume,
                sourceSignatureBefore: sourceSignatureBefore,
                bytesCopiedIfKnown: fileSize(destinationURL)
            )
        }

        let cloneStrategy = resolvedCloneStrategy(for: strategy)
        let cloneOutcome = try attemptClone(
            source: sourceURL,
            destination: destinationURL,
            strategy: cloneStrategy
        )
        if cloneOutcome.succeeded {
            let cloneVerified = fileSize(sourceURL) == fileSize(destinationURL) && FileManager.default.fileExists(atPath: destinationURL.path)
            return result(
                requestedStrategy: strategy,
                actualStrategy: strategy == .auto ? cloneStrategy : strategy,
                fallbackStrategy: nil,
                fallbackReason: nil,
                cloneSupported: true,
                cloneAttempted: true,
                cloneReturnedSuccess: true,
                cloneVerified: cloneVerified,
                cloneVerificationStrength: cloneVerified ? .strong : .unknown,
                cloneSucceeded: cloneVerified,
                copyAttempted: false,
                copySucceeded: false,
                publicCloneAPIMissing: false,
                byteForByteCopyAvoided: cloneVerified ? .true : .unknown,
                rootfsWorkAvoided: cloneVerified ? .true : .unknown,
                started: started,
                source: sourceURL,
                sourceBytes: sourceBytes,
                destination: destinationURL,
                sameVolume: sameVolume,
                sourceSignatureBefore: sourceSignatureBefore,
                bytesCopiedIfKnown: nil
            )
        }

        try copyReplacing(source: sourceURL, destination: destinationURL)
        return result(
            requestedStrategy: strategy,
            actualStrategy: .fullCopy,
            fallbackStrategy: .fullCopy,
            fallbackReason: "\(cloneOutcome.failureReason ?? "clone failed"); fell back to fullCopy",
            cloneSupported: false,
            cloneAttempted: true,
            cloneReturnedSuccess: false,
            cloneVerified: false,
            cloneVerificationStrength: .notApplicable,
            cloneSucceeded: false,
            copyAttempted: true,
            copySucceeded: true,
            publicCloneAPIMissing: false,
            byteForByteCopyAvoided: .false,
            rootfsWorkAvoided: .false,
            started: started,
            source: sourceURL,
            sourceBytes: sourceBytes,
            destination: destinationURL,
            sameVolume: sameVolume,
            sourceSignatureBefore: sourceSignatureBefore,
            bytesCopiedIfKnown: fileSize(destinationURL)
        )
    }

    private func shouldUseFullCopy(_ strategy: RootfsMaterializationStrategy) -> Bool {
        switch strategy {
        case .fullCopy, .fileManagerCopy, .copy:
            return true
        case .apfsClone,
             .clonefile,
             .copyfileClone,
             .auto,
             .clone,
             .unsupported,
             .unpack,
             .reuse,
             .unknown:
            return false
        }
    }

    private func resolvedCloneStrategy(for strategy: RootfsMaterializationStrategy) -> RootfsMaterializationStrategy {
        switch strategy {
        case .copyfileClone:
            return .copyfileClone
        case .apfsClone:
            return .apfsClone
        case .auto, .clone, .clonefile, .unsupported, .unpack, .reuse, .unknown:
            return .clonefile
        case .fullCopy, .fileManagerCopy, .copy:
            return .fullCopy
        }
    }

    private func result(
        requestedStrategy: RootfsMaterializationStrategy,
        actualStrategy: RootfsMaterializationStrategy,
        fallbackStrategy: RootfsMaterializationStrategy?,
        fallbackReason: String?,
        cloneSupported: Bool,
        cloneAttempted: Bool,
        cloneReturnedSuccess: Bool,
        cloneVerified: Bool,
        cloneVerificationStrength: RootfsCloneVerificationStrength,
        cloneSucceeded: Bool,
        copyAttempted: Bool,
        copySucceeded: Bool,
        publicCloneAPIMissing: Bool,
        byteForByteCopyAvoided: EvidenceTruthValue,
        rootfsWorkAvoided: EvidenceTruthValue,
        started: Date,
        source: URL,
        sourceBytes: UInt64?,
        destination: URL,
        sameVolume: Bool?,
        sourceSignatureBefore: FileSignature?,
        bytesCopiedIfKnown: UInt64?
    ) -> RootfsMaterializationResult {
        let destinationBytes = fileSize(destination)
        return RootfsMaterializationResult(
            requestedStrategy: requestedStrategy,
            actualStrategy: actualStrategy,
            fallbackStrategy: fallbackStrategy,
            fallbackReason: fallbackReason,
            cloneSupported: cloneSupported,
            cloneAttempted: cloneAttempted,
            cloneReturnedSuccess: cloneReturnedSuccess,
            cloneVerified: cloneVerified,
            cloneVerificationStrength: cloneVerificationStrength,
            cloneSucceeded: cloneSucceeded,
            copyAttempted: copyAttempted,
            copySucceeded: copySucceeded,
            publicCloneAPIMissing: publicCloneAPIMissing,
            byteForByteCopyAvoided: byteForByteCopyAvoided,
            rootfsWorkAvoided: rootfsWorkAvoided,
            durationSeconds: Date().timeIntervalSince(started),
            sourceBytes: sourceBytes,
            destinationBytes: destinationBytes,
            apparentSizeBytes: destinationBytes,
            allocatedSizeBytes: allocatedSize(destination),
            bytesCopiedIfKnown: bytesCopiedIfKnown,
            sourceAndDestinationSameVolume: sameVolume,
            sourceUnchanged: sourceSignatureBefore == nil
                ? .unknown
                : (sourceSignatureBefore == fileSignature(source) ? .true : .false)
        )
    }

    private func copyReplacing(source: URL, destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func attemptClone(
        source: URL,
        destination: URL,
        strategy: RootfsMaterializationStrategy
    ) throws -> CloneOutcome {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let returnCode: Int32
        switch strategy {
        case .copyfileClone:
            returnCode = source.withUnsafeFileSystemRepresentation { sourcePath in
                destination.withUnsafeFileSystemRepresentation { destinationPath in
                    guard let sourcePath, let destinationPath else {
                        errno = EINVAL
                        return -1
                    }
                    return copyfile(sourcePath, destinationPath, nil, copyfile_flags_t(COPYFILE_CLONE_FORCE))
                }
            }
        case .apfsClone, .clonefile:
            returnCode = source.withUnsafeFileSystemRepresentation { sourcePath in
                destination.withUnsafeFileSystemRepresentation { destinationPath in
                    guard let sourcePath, let destinationPath else {
                        errno = EINVAL
                        return -1
                    }
                    return clonefile(sourcePath, destinationPath, 0)
                }
            }
        case .fullCopy,
             .fileManagerCopy,
             .auto,
             .unsupported,
             .unpack,
             .copy,
             .clone,
             .reuse,
             .unknown:
            return CloneOutcome(succeeded: false, failureReason: "unsupported clone strategy \(strategy.rawValue)")
        }
        guard returnCode == 0 else {
            let errorNumber = errno
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            return CloneOutcome(
                succeeded: false,
                failureReason: "clone API returned \(returnCode) errno \(errorNumber) \(String(cString: strerror(errorNumber)))"
            )
        }
        return CloneOutcome(succeeded: true, failureReason: nil)
    }

    private func fileSize(_ url: URL) -> UInt64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return UInt64(value)
    }

    private func allocatedSize(_ url: URL) -> UInt64? {
        guard let value = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize else {
            return nil
        }
        return UInt64(value)
    }

    private func sameVolume(_ lhs: URL, _ rhs: URL) -> Bool? {
        guard let lhsValue = try? lhs.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let rhsValue = try? rhs.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
            return nil
        }
        return String(describing: lhsValue) == String(describing: rhsValue)
    }

    private func fileSignature(_ url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        return FileSignature(path: url.path, size: size, modified: modified, inode: inode)
    }

    private func isStrictDescendant(_ child: URL, of parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
        let childPath = child.standardizedFileURL.resolvingSymlinksInPath().path
        return childPath.hasPrefix(parentPath + "/")
    }
}

private struct CloneOutcome: Equatable {
    let succeeded: Bool
    let failureReason: String?
}

private struct FileSignature: Equatable {
    let path: String
    let size: UInt64?
    let modified: TimeInterval?
    let inode: UInt64?
}
