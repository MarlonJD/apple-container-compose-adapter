// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public enum Phase6BenchmarkSchema {
    public static let version = "container-compose-adapter/linuxpod-phase6-benchmark/v1"
    public static let iterationRecordType = "linuxpod-phase6-benchmark-iteration"
    public static let summaryRecordType = "linuxpod-phase6-benchmark-summary"
}

public enum BenchmarkLifecycle: String, Codable, Equatable, Sendable {
    case cold
    case imageStoreSeededFreshRuntime = "image-store-seeded-fresh-runtime"
    case persistentWarmProjectRuntime = "persistent-warm-project-runtime"
    /// Legacy value kept so older Stage 4/6 evidence can still decode.
    case warm
}

public enum BenchmarkLifecycleMode: String, Codable, Equatable, CaseIterable, Sendable {
    case coldRuntime = "cold-runtime"
    case imageStoreSeededFreshRuntime = "image-store-seeded-fresh-runtime"
    case rootfsCacheHitRuntime = "rootfs-cache-hit-runtime"
    case initfsCacheHitRuntime = "initfs-cache-hit-runtime"
    case warmPreservedVolume = "warm-preserved-volume"
    case persistentPodHotplug = "persistent-pod-hotplug"
    case allWarmProjectRuntime = "all-warm-project-runtime"

    public var id: String {
        switch self {
        case .coldRuntime:
            return "A"
        case .imageStoreSeededFreshRuntime:
            return "B"
        case .rootfsCacheHitRuntime:
            return "C"
        case .initfsCacheHitRuntime:
            return "D"
        case .warmPreservedVolume:
            return "E"
        case .persistentPodHotplug:
            return "F"
        case .allWarmProjectRuntime:
            return "G"
        }
    }

    public var legacyLifecycle: BenchmarkLifecycle {
        switch self {
        case .coldRuntime:
            return .cold
        case .imageStoreSeededFreshRuntime:
            return .imageStoreSeededFreshRuntime
        case .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime,
             .warmPreservedVolume,
             .persistentPodHotplug,
             .allWarmProjectRuntime:
            return .persistentWarmProjectRuntime
        }
    }

    public var targetName: String {
        switch self {
        case .coldRuntime:
            return "LinuxPod cold runtime"
        case .imageStoreSeededFreshRuntime:
            return "LinuxPod image-store-seeded fresh runtime"
        case .rootfsCacheHitRuntime:
            return "LinuxPod rootfs-cache hit runtime"
        case .initfsCacheHitRuntime:
            return "LinuxPod initfs-cache hit runtime"
        case .warmPreservedVolume:
            return "LinuxPod warm preserved volume runtime"
        case .persistentPodHotplug:
            return "LinuxPod persistent pod hotplug runtime"
        case .allWarmProjectRuntime:
            return "LinuxPod all-warm project runtime"
        }
    }

    public static func compatibilityDefault(for lifecycle: BenchmarkLifecycle) -> BenchmarkLifecycleMode {
        switch lifecycle {
        case .cold:
            return .coldRuntime
        case .imageStoreSeededFreshRuntime:
            return .imageStoreSeededFreshRuntime
        case .persistentWarmProjectRuntime:
            return .allWarmProjectRuntime
        case .warm:
            return .allWarmProjectRuntime
        }
    }

    public static func classify(
        lifecycle: BenchmarkLifecycle,
        seedImageStoreCopied: Bool,
        rootfsCacheStatus: BenchmarkCacheStatus,
        initfsCacheStatus: BenchmarkCacheStatus,
        volumeExistedBeforeRun: Bool,
        podExistedBeforeRun: Bool
    ) -> BenchmarkLifecycleMode {
        let rootfsHit = rootfsCacheStatus.isHitLike
        let initfsHit = initfsCacheStatus.isHitLike

        if rootfsHit && initfsHit && volumeExistedBeforeRun && podExistedBeforeRun {
            return .allWarmProjectRuntime
        }
        if podExistedBeforeRun {
            return .persistentPodHotplug
        }
        if volumeExistedBeforeRun {
            return .warmPreservedVolume
        }
        if initfsHit {
            return .initfsCacheHitRuntime
        }
        if rootfsHit {
            return .rootfsCacheHitRuntime
        }
        if seedImageStoreCopied || lifecycle == .imageStoreSeededFreshRuntime {
            return .imageStoreSeededFreshRuntime
        }
        return .coldRuntime
    }
}

public enum BenchmarkCacheStatus: String, Codable, Equatable, Sendable {
    case hit
    case miss
    case unknown
    case blocked
    case unverifiedSeedRequested
    case verifiedHit
    case partialHit
    case invalid

    public var isHitLike: Bool {
        self == .hit || self == .verifiedHit
    }
}

public enum EvidenceTruthValue: String, Codable, Equatable, Sendable {
    case `true` = "true"
    case `false` = "false"
    case unknown
}

public enum RootfsMaterializationStrategy: String, Codable, Equatable, Sendable {
    case fullCopy
    case fileManagerCopy
    case apfsClone
    case clonefile
    case copyfileClone
    case auto
    case unsupported
    case unpack
    case copy
    case clone
    case reuse
    case unknown

    public static var stage10AValues: [RootfsMaterializationStrategy] {
        [
            .fullCopy,
            .fileManagerCopy,
            .apfsClone,
            .clonefile,
            .copyfileClone,
            .auto,
            .unsupported,
            .unknown
        ]
    }

    public var isCloneStrategy: Bool {
        switch self {
        case .apfsClone, .clonefile, .copyfileClone, .auto, .clone:
            return true
        case .fullCopy,
             .fileManagerCopy,
             .unsupported,
             .unpack,
             .copy,
             .reuse,
             .unknown:
            return false
        }
    }
}

public enum RootfsCacheClaim: String, Codable, Equatable, Sendable {
    case baseArtifactHit
    case fullContainerRootfsHit
    case noHit
    case unknown
}

public struct RootfsPreparationBreakdown: Codable, Equatable, Sendable {
    public let actionKind: String
    public let resourceName: String?
    public let image: String?
    public let service: String?
    public let imageReferenceResolveDuration: Double?
    public let imageStoreLookupDuration: Double?
    public let platformValidationDuration: Double?
    public let imagePullDuration: Double?
    public let baseRootfsCacheLookupDuration: Double?
    public let baseRootfsCacheHit: Bool?
    public let baseRootfsCreateOrUnpackDuration: Double?
    public let containerRootfsMaterializeDuration: Double?
    public let containerRootfsCopyDuration: Double?
    public let containerRootfsCloneDuration: Double?
    public let containerRootfsMountPrepareDuration: Double?
    public let rootfsBytesCopied: UInt64?
    public let rootfsSourcePath: String?
    public let rootfsDestinationPath: String?
    public let rootfsMountType: String?
    public let rootfsMountFormat: String?
    public let rootfsMountIsBlock: Bool?
    public let rootfsMaterializationStrategy: RootfsMaterializationStrategy
    public let rootfsWorkAvoided: EvidenceTruthValue
    public let rootfsCacheClaim: RootfsCacheClaim

    public init(
        actionKind: String,
        resourceName: String?,
        image: String? = nil,
        service: String? = nil,
        imageReferenceResolveDuration: Double? = nil,
        imageStoreLookupDuration: Double? = nil,
        platformValidationDuration: Double? = nil,
        imagePullDuration: Double? = nil,
        baseRootfsCacheLookupDuration: Double? = nil,
        baseRootfsCacheHit: Bool? = nil,
        baseRootfsCreateOrUnpackDuration: Double? = nil,
        containerRootfsMaterializeDuration: Double? = nil,
        containerRootfsCopyDuration: Double? = nil,
        containerRootfsCloneDuration: Double? = nil,
        containerRootfsMountPrepareDuration: Double? = nil,
        rootfsBytesCopied: UInt64? = nil,
        rootfsSourcePath: String? = nil,
        rootfsDestinationPath: String? = nil,
        rootfsMountType: String? = nil,
        rootfsMountFormat: String? = nil,
        rootfsMountIsBlock: Bool? = nil,
        rootfsMaterializationStrategy: RootfsMaterializationStrategy = .unknown,
        rootfsWorkAvoided: EvidenceTruthValue = .unknown,
        rootfsCacheClaim: RootfsCacheClaim = .unknown
    ) {
        self.actionKind = actionKind
        self.resourceName = resourceName
        self.image = image
        self.service = service
        self.imageReferenceResolveDuration = imageReferenceResolveDuration
        self.imageStoreLookupDuration = imageStoreLookupDuration
        self.platformValidationDuration = platformValidationDuration
        self.imagePullDuration = imagePullDuration
        self.baseRootfsCacheLookupDuration = baseRootfsCacheLookupDuration
        self.baseRootfsCacheHit = baseRootfsCacheHit
        self.baseRootfsCreateOrUnpackDuration = baseRootfsCreateOrUnpackDuration
        self.containerRootfsMaterializeDuration = containerRootfsMaterializeDuration
        self.containerRootfsCopyDuration = containerRootfsCopyDuration
        self.containerRootfsCloneDuration = containerRootfsCloneDuration
        self.containerRootfsMountPrepareDuration = containerRootfsMountPrepareDuration
        self.rootfsBytesCopied = rootfsBytesCopied
        self.rootfsSourcePath = rootfsSourcePath
        self.rootfsDestinationPath = rootfsDestinationPath
        self.rootfsMountType = rootfsMountType
        self.rootfsMountFormat = rootfsMountFormat
        self.rootfsMountIsBlock = rootfsMountIsBlock
        self.rootfsMaterializationStrategy = rootfsMaterializationStrategy
        self.rootfsWorkAvoided = rootfsWorkAvoided
        self.rootfsCacheClaim = rootfsCacheClaim
    }
}

public enum PodReuseClaim: String, Codable, Equatable, Sendable {
    case markerOnly
    case liveObject
    case reconnected
    case unknown
}

public enum AddContainerPhase: String, Codable, Equatable, Sendable {
    case beforePodCreate
    case afterPodCreate
    case uninitialized
    case unknown
}

public struct HotplugLifecycleDiagnostics: Codable, Equatable, Sendable {
    public let podMarkerExists: Bool
    public let runtimeDirectoryExists: Bool
    public let podObjectInitialized: Bool
    public let podObjectPhase: String?
    public let podCreatedStateKnown: Bool
    public let podActuallyRunning: Bool?
    public let podReconnectAttempted: Bool
    public let podReconnectSucceeded: Bool
    public let podReuseClaim: PodReuseClaim
    public let addContainerAttempted: Bool
    public let addContainerPhase: AddContainerPhase
    public let hotplugAttempted: Bool
    public let hotplugSucceeded: Bool
    public let hotplugUnsupported: Bool?
    public let duplicateContainerDetected: Bool
    public let vmConfigExtensionCount: Int?
    public let vmConfigExtensionTypes: [String]?
    public let hotplugProviderInstalled: Bool?
    public let hotplugProviderType: String?
    public let hotplugProviderStatus: String?
    public let failurePhase: String?
    public let failureErrorType: String?
    public let failureErrorMessage: String?
    public let mutationBeforeFailure: EvidenceTruthValue

    public init(
        podMarkerExists: Bool,
        runtimeDirectoryExists: Bool,
        podObjectInitialized: Bool,
        podObjectPhase: String?,
        podCreatedStateKnown: Bool,
        podActuallyRunning: Bool?,
        podReconnectAttempted: Bool,
        podReconnectSucceeded: Bool,
        podReuseClaim: PodReuseClaim,
        addContainerAttempted: Bool,
        addContainerPhase: AddContainerPhase,
        hotplugAttempted: Bool,
        hotplugSucceeded: Bool,
        hotplugUnsupported: Bool?,
        duplicateContainerDetected: Bool,
        vmConfigExtensionCount: Int? = nil,
        vmConfigExtensionTypes: [String]? = nil,
        hotplugProviderInstalled: Bool? = nil,
        hotplugProviderType: String? = nil,
        hotplugProviderStatus: String? = nil,
        failurePhase: String?,
        failureErrorType: String?,
        failureErrorMessage: String?,
        mutationBeforeFailure: EvidenceTruthValue
    ) {
        self.podMarkerExists = podMarkerExists
        self.runtimeDirectoryExists = runtimeDirectoryExists
        self.podObjectInitialized = podObjectInitialized
        self.podObjectPhase = podObjectPhase
        self.podCreatedStateKnown = podCreatedStateKnown
        self.podActuallyRunning = podActuallyRunning
        self.podReconnectAttempted = podReconnectAttempted
        self.podReconnectSucceeded = podReconnectSucceeded
        self.podReuseClaim = podReuseClaim
        self.addContainerAttempted = addContainerAttempted
        self.addContainerPhase = addContainerPhase
        self.hotplugAttempted = hotplugAttempted
        self.hotplugSucceeded = hotplugSucceeded
        self.hotplugUnsupported = hotplugUnsupported
        self.duplicateContainerDetected = duplicateContainerDetected
        self.vmConfigExtensionCount = vmConfigExtensionCount
        self.vmConfigExtensionTypes = vmConfigExtensionTypes
        self.hotplugProviderInstalled = hotplugProviderInstalled
        self.hotplugProviderType = hotplugProviderType
        self.hotplugProviderStatus = hotplugProviderStatus
        self.failurePhase = failurePhase
        self.failureErrorType = failureErrorType
        self.failureErrorMessage = failureErrorMessage
        self.mutationBeforeFailure = mutationBeforeFailure
    }
}

public enum ServiceRecreateStrategy: String, Codable, Equatable, Sendable {
    case hotplug
    case restart
    case fullPodRecreate
    case noOp
    case unsupported
    case failed
}

public struct WarmServiceRecreateMetadata: Codable, Equatable, Sendable {
    public let forcedServiceRecreateRequested: Bool
    public let forcedServiceName: String?
    public let serviceChanged: Bool?
    public let previousServiceStateKnown: Bool?
    public let recreateStrategy: ServiceRecreateStrategy
    public let dbVolumePreserved: Bool?
    public let podPreserved: Bool?
    public let serviceRecreateDuration: Double?
    public let postRecreateReadinessDuration: Double?
    public let hostPortStatus: String
    public let loadWindowStatus: String
    public let noOpWarmReconcile: Bool
    public let notProductViabilityEvidence: Bool

    public init(
        forcedServiceRecreateRequested: Bool,
        forcedServiceName: String?,
        serviceChanged: Bool?,
        previousServiceStateKnown: Bool?,
        recreateStrategy: ServiceRecreateStrategy,
        dbVolumePreserved: Bool?,
        podPreserved: Bool?,
        serviceRecreateDuration: Double?,
        postRecreateReadinessDuration: Double?,
        hostPortStatus: String,
        loadWindowStatus: String,
        noOpWarmReconcile: Bool,
        notProductViabilityEvidence: Bool
    ) {
        self.forcedServiceRecreateRequested = forcedServiceRecreateRequested
        self.forcedServiceName = forcedServiceName
        self.serviceChanged = serviceChanged
        self.previousServiceStateKnown = previousServiceStateKnown
        self.recreateStrategy = recreateStrategy
        self.dbVolumePreserved = dbVolumePreserved
        self.podPreserved = podPreserved
        self.serviceRecreateDuration = serviceRecreateDuration
        self.postRecreateReadinessDuration = postRecreateReadinessDuration
        self.hostPortStatus = hostPortStatus
        self.loadWindowStatus = loadWindowStatus
        self.noOpWarmReconcile = noOpWarmReconcile
        self.notProductViabilityEvidence = notProductViabilityEvidence
    }
}

public enum Stage9BHotplugProbeSchema {
    public static let version = "container-compose-adapter/linuxpod-stage9b-hotplug-probe/v1"
    public static let caseRecordType = "linuxpod-stage9b-hotplug-probe-case"
}

public enum Stage9BHotplugProbeCase: String, Codable, CaseIterable, Equatable, Sendable {
    case preCreateRegistrationControl = "pre-create-registration-control"
    case emptyPodPostCreateAddContainer = "empty-pod-post-create-add-container"
    case nonEmptyPodPostCreateAddSecondContainer = "non-empty-pod-post-create-add-second-container"
    case duplicateContainerIDGuard = "duplicate-container-id-guard"
    case cleanupProof = "cleanup-proof"

    public var runtimeResourceSuffix: String {
        switch self {
        case .preCreateRegistrationControl:
            return "pre"
        case .emptyPodPostCreateAddContainer:
            return "empty"
        case .nonEmptyPodPostCreateAddSecondContainer:
            return "nonempty"
        case .duplicateContainerIDGuard:
            return "dup"
        case .cleanupProof:
            return "cleanup"
        }
    }
}

public enum Stage9BAddContainerPhase: String, Codable, Equatable, Sendable {
    case beforePodCreate
    case afterPodCreateEmptyPod
    case afterPodCreateNonEmptyPod
    case duplicateContainer
    case unknown
    case fullPodRecreate
}

public struct Stage9BHotplugProbeRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let probeCase: Stage9BHotplugProbeCase
    public let podObjectCreated: Bool
    public let podCreateCalled: Bool
    public let podCreateSucceeded: Bool
    public let podObjectPhase: String?
    public let podCreatedStateKnown: Bool
    public let podActuallyRunning: Bool?
    public let initialContainerRegisteredBeforeCreate: Bool
    public let initialContainerStarted: Bool
    public let postCreateAddContainerAttempted: Bool
    public let postCreateAddContainerSucceeded: Bool
    public let addContainerPhase: Stage9BAddContainerPhase
    public let hotplugAttempted: Bool
    public let hotplugSucceeded: Bool
    public let hotplugUnsupported: Bool
    public let duplicateContainerDetected: Bool
    public let failurePhase: String?
    public let failureErrorType: String?
    public let failureErrorMessage: String?
    public let mutationBeforeFailure: EvidenceTruthValue
    public let cleanupResult: String
    public let cleanupStateDirectoryExistsAfterCleanup: Bool
    public let leftoverPathsCount: Int
    public let runtimePackageVersion: String?
    public let macOSVersion: String
    public let containerizationVersion: String?

    public init(
        timestamp: String,
        project: String,
        probeCase: Stage9BHotplugProbeCase,
        podObjectCreated: Bool,
        podCreateCalled: Bool,
        podCreateSucceeded: Bool,
        podObjectPhase: String?,
        podCreatedStateKnown: Bool,
        podActuallyRunning: Bool?,
        initialContainerRegisteredBeforeCreate: Bool,
        initialContainerStarted: Bool,
        postCreateAddContainerAttempted: Bool,
        postCreateAddContainerSucceeded: Bool,
        addContainerPhase: Stage9BAddContainerPhase,
        hotplugAttempted: Bool,
        hotplugSucceeded: Bool,
        hotplugUnsupported: Bool,
        duplicateContainerDetected: Bool,
        failurePhase: String?,
        failureErrorType: String?,
        failureErrorMessage: String?,
        mutationBeforeFailure: EvidenceTruthValue,
        cleanupResult: String,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        leftoverPathsCount: Int,
        runtimePackageVersion: String?,
        macOSVersion: String,
        containerizationVersion: String?
    ) {
        self.schemaVersion = Stage9BHotplugProbeSchema.version
        self.recordType = Stage9BHotplugProbeSchema.caseRecordType
        self.timestamp = timestamp
        self.project = project
        self.probeCase = probeCase
        self.podObjectCreated = podObjectCreated
        self.podCreateCalled = podCreateCalled
        self.podCreateSucceeded = podCreateSucceeded
        self.podObjectPhase = podObjectPhase
        self.podCreatedStateKnown = podCreatedStateKnown
        self.podActuallyRunning = podActuallyRunning
        self.initialContainerRegisteredBeforeCreate = initialContainerRegisteredBeforeCreate
        self.initialContainerStarted = initialContainerStarted
        self.postCreateAddContainerAttempted = postCreateAddContainerAttempted
        self.postCreateAddContainerSucceeded = postCreateAddContainerSucceeded
        self.addContainerPhase = addContainerPhase
        self.hotplugAttempted = hotplugAttempted
        self.hotplugSucceeded = hotplugSucceeded
        self.hotplugUnsupported = hotplugUnsupported
        self.duplicateContainerDetected = duplicateContainerDetected
        self.failurePhase = failurePhase
        self.failureErrorType = failureErrorType
        self.failureErrorMessage = failureErrorMessage
        self.mutationBeforeFailure = mutationBeforeFailure
        self.cleanupResult = cleanupResult
        self.cleanupStateDirectoryExistsAfterCleanup = cleanupStateDirectoryExistsAfterCleanup
        self.leftoverPathsCount = leftoverPathsCount
        self.runtimePackageVersion = runtimePackageVersion
        self.macOSVersion = macOSVersion
        self.containerizationVersion = containerizationVersion
    }
}

public struct Stage9BHotplugProbeEvidenceValidator: Sendable {
    public init() {}

    public func validate(records: [Stage9BHotplugProbeRecord]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let cases = Set(records.map(\.probeCase))
        if records.isEmpty {
            diagnostics.append(blocking("stage9b-evidence-empty", "Stage 9B hotplug probe evidence must include case records."))
        }
        for requiredCase in Stage9BHotplugProbeCase.allCases where !cases.contains(requiredCase) {
            diagnostics.append(blocking("stage9b-\(requiredCase.rawValue)-missing", "Stage 9B evidence is missing \(requiredCase.rawValue)."))
        }
        if !records.contains(where: { record in
            record.probeCase == .cleanupProof
                && record.cleanupResult == "clean"
                && !record.cleanupStateDirectoryExistsAfterCleanup
                && record.leftoverPathsCount == 0
        }) {
            diagnostics.append(blocking("stage9b-cleanup-proof-missing", "Stage 9B evidence must include final zero-leftover cleanup proof."))
        }
        for record in records {
            validate(record, diagnostics: &diagnostics)
        }
        return diagnostics
    }

    public func validate(evidenceURL: URL) throws -> [Diagnostic] {
        let records: [Stage9BHotplugProbeRecord] = try readStage9BHotplugProbeRecords(evidenceURL)
        return validate(records: records)
    }

    private func validate(
        _ record: Stage9BHotplugProbeRecord,
        diagnostics: inout [Diagnostic]
    ) {
        if record.cleanupResult != "clean"
            || record.cleanupStateDirectoryExistsAfterCleanup
            || record.leftoverPathsCount != 0 {
            diagnostics.append(blocking("stage9b-case-cleanup-leftovers", "Every Stage 9B probe case must prove clean adapter-owned cleanup."))
        }
        let expectedPhase: Stage9BAddContainerPhase
        switch record.probeCase {
        case .preCreateRegistrationControl:
            expectedPhase = .beforePodCreate
        case .emptyPodPostCreateAddContainer:
            expectedPhase = .afterPodCreateEmptyPod
        case .nonEmptyPodPostCreateAddSecondContainer:
            expectedPhase = .afterPodCreateNonEmptyPod
        case .duplicateContainerIDGuard:
            expectedPhase = .duplicateContainer
        case .cleanupProof:
            expectedPhase = .unknown
        }
        if record.addContainerPhase != expectedPhase {
            diagnostics.append(blocking("stage9b-add-container-phase-mismatch", "Stage 9B probe case \(record.probeCase.rawValue) has the wrong addContainer phase."))
        }
        if record.addContainerPhase == .fullPodRecreate {
            diagnostics.append(blocking("stage9b-full-pod-recreate-not-hotplug", "Stage 9B hotplug probe evidence must not label full pod recreate as hotplug."))
        }
        if record.probeCase == .duplicateContainerIDGuard && !record.duplicateContainerDetected {
            diagnostics.append(blocking("stage9b-duplicate-container-undetected", "Duplicate container guard evidence must mark duplicateContainerDetected."))
        }
        if record.probeCase == .preCreateRegistrationControl && !record.initialContainerRegisteredBeforeCreate {
            diagnostics.append(blocking("stage9b-pre-create-registration-missing", "Pre-create control must register an initial container before pod.create()."))
        }
        if record.probeCase == .emptyPodPostCreateAddContainer
            && (!record.podCreateCalled || !record.postCreateAddContainerAttempted || !record.hotplugAttempted) {
            diagnostics.append(blocking("stage9b-empty-post-create-attempt-missing", "Empty-pod case must create the pod and attempt post-create addContainer."))
        }
        if record.probeCase == .nonEmptyPodPostCreateAddSecondContainer
            && (!record.initialContainerRegisteredBeforeCreate || !record.postCreateAddContainerAttempted || !record.hotplugAttempted) {
            diagnostics.append(blocking("stage9b-non-empty-post-create-attempt-missing", "Non-empty-pod case must register an initial container and attempt post-create addContainer."))
        }
    }
}

public enum Stage9DHotplugProviderProbeSchema {
    public static let version = "container-compose-adapter/linuxpod-stage9d-hotplug-provider-probe/v1"
    public static let recordType = "stage9dHotplugProviderProbe"
}

public enum Stage9DHotplugProviderProbeRuntimeNames {
    public static let linuxPodIDMaximumLength = 64
    private static let providerSuffix = "-provider"
    private static let initialSuffix = "-initial"
    private static let secondSuffix = "-second"

    public static func projectName(projectPrefix: String, runLabel _: String) -> ProjectName {
        let maxProjectSlugLength = linuxPodIDMaximumLength
            - LinuxPodStateStore.ownedPrefix.count
            - initialSuffix.count
        let maxPrefixLength = max(1, maxProjectSlugLength - providerSuffix.count)
        let sanitizedPrefix = ProjectName(projectPrefix).sanitized
        let truncatedPrefix = String(sanitizedPrefix.prefix(maxPrefixLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safePrefix = truncatedPrefix.isEmpty ? "stage9d" : truncatedPrefix
        return ProjectName("\(safePrefix)\(providerSuffix)")
    }

    public static func ownedProjectResourceName(
        projectPrefix: String,
        runLabel: String,
        ownedPrefix: String = LinuxPodStateStore.ownedPrefix
    ) -> String {
        projectName(projectPrefix: projectPrefix, runLabel: runLabel)
            .adapterOwnedName(prefix: ownedPrefix)
    }

    public static func initialContainerID(projectResource: String) -> String {
        "\(projectResource)\(initialSuffix)"
    }

    public static func secondContainerID(projectResource: String) -> String {
        "\(projectResource)\(secondSuffix)"
    }
}

public enum Stage9DProbeStatus: String, Codable, Equatable, Sendable {
    case measured
    case failed
    case skipped
}

public enum Stage9DProbeCase: String, Codable, CaseIterable, Equatable, Sendable {
    case providerInstallOnly
    case providerReceivesHotplug
    case realSecondContainerHotplug
}

public enum Stage9DRootfsAttachStrategy: String, Codable, Equatable, Sendable {
    case none
    case vzUSBMassStorage
    case publicVZStorageAttach
    case virtiofsOnly
    case unsupported
    case notImplemented
    case unknown
}

public enum Stage9DBlocker: String, Codable, Equatable, Sendable {
    case none
    case providerNotInstalled
    case providerInstalledButAttachNotImplemented
    case publicBlockHotplugAPIMissing
    case unsupportedRootfsBlockHotplug
    case virtiofsOnlyProviderInsufficient
    case linuxPodLifecycle
    case upstreamRuntimeLimitation
    case unknown
}

public enum Stage9DNextRecommendedPath: String, Codable, Equatable, Sendable {
    case forcedWarmServiceRecreateWithHotplug
    case fastPodRecreateRootfsCopyAvoidance
    case upstreamIssue
    case providerSpikeNeedsMoreWork
    case abandonHotplugForNow
}

public struct Stage9DProviderEvidence: Codable, Equatable, Sendable {
    public let extensionInstalled: Bool
    public let extensionType: String?
    public let linuxPodConfigExtensionCount: Int
    public let vmConfigExtensionCount: Int
    public let vmInstanceType: String?
    public let hotplugProviderInstalled: Bool
    public let hotplugProviderType: String?
    public let providerDidCreateCalled: Bool
    public let providerHotplugCalled: Bool
    public let providerHotplugVirtioFSCalled: Bool
    public let providerReleaseHotplugCalled: Bool
    public let providerReleaseVirtioFSCalled: Bool

    public init(
        extensionInstalled: Bool,
        extensionType: String?,
        linuxPodConfigExtensionCount: Int,
        vmConfigExtensionCount: Int,
        vmInstanceType: String?,
        hotplugProviderInstalled: Bool,
        hotplugProviderType: String?,
        providerDidCreateCalled: Bool,
        providerHotplugCalled: Bool,
        providerHotplugVirtioFSCalled: Bool,
        providerReleaseHotplugCalled: Bool,
        providerReleaseVirtioFSCalled: Bool
    ) {
        self.extensionInstalled = extensionInstalled
        self.extensionType = extensionType
        self.linuxPodConfigExtensionCount = linuxPodConfigExtensionCount
        self.vmConfigExtensionCount = vmConfigExtensionCount
        self.vmInstanceType = vmInstanceType
        self.hotplugProviderInstalled = hotplugProviderInstalled
        self.hotplugProviderType = hotplugProviderType
        self.providerDidCreateCalled = providerDidCreateCalled
        self.providerHotplugCalled = providerHotplugCalled
        self.providerHotplugVirtioFSCalled = providerHotplugVirtioFSCalled
        self.providerReleaseHotplugCalled = providerReleaseHotplugCalled
        self.providerReleaseVirtioFSCalled = providerReleaseVirtioFSCalled
    }
}

public struct Stage9DRootfsEvidence: Codable, Equatable, Sendable {
    public let rootfsMountType: String?
    public let rootfsIsBlock: Bool?
    public let rootfsIsExt4: Bool?
    public let rootfsSourcePath: String?
    public let rootfsSourcePathRedacted: Bool
    public let rootfsAttachStrategy: Stage9DRootfsAttachStrategy
    public let attachedFilesystemSource: String?
    public let attachedFilesystemSourceKnown: Bool

    public init(
        rootfsMountType: String?,
        rootfsIsBlock: Bool?,
        rootfsIsExt4: Bool?,
        rootfsSourcePath: String?,
        rootfsSourcePathRedacted: Bool,
        rootfsAttachStrategy: Stage9DRootfsAttachStrategy,
        attachedFilesystemSource: String?,
        attachedFilesystemSourceKnown: Bool
    ) {
        self.rootfsMountType = rootfsMountType
        self.rootfsIsBlock = rootfsIsBlock
        self.rootfsIsExt4 = rootfsIsExt4
        self.rootfsSourcePath = rootfsSourcePath
        self.rootfsSourcePathRedacted = rootfsSourcePathRedacted
        self.rootfsAttachStrategy = rootfsAttachStrategy
        self.attachedFilesystemSource = attachedFilesystemSource
        self.attachedFilesystemSourceKnown = attachedFilesystemSourceKnown
    }
}

public struct Stage9DHotplugEvidence: Codable, Equatable, Sendable {
    public let preCreateRegistrationSucceeded: Bool
    public let podCreateSucceeded: Bool
    public let firstContainerStarted: Bool
    public let postCreateAddContainerAttempted: Bool
    public let postCreateAddContainerReachedProvider: Bool
    public let postCreateAddContainerSucceeded: Bool
    public let secondContainerStarted: Bool
    public let realHotplugSucceeded: Bool
    public let hotplugUnsupported: Bool
    public let providerInstalledButAttachUnsupported: Bool
    public let publicBlockHotplugAPIMissing: Bool
    public let failurePhase: String?
    public let failureErrorType: String?
    public let failureErrorMessage: String?
    public let blocker: Stage9DBlocker

    public init(
        preCreateRegistrationSucceeded: Bool,
        podCreateSucceeded: Bool,
        firstContainerStarted: Bool,
        postCreateAddContainerAttempted: Bool,
        postCreateAddContainerReachedProvider: Bool,
        postCreateAddContainerSucceeded: Bool,
        secondContainerStarted: Bool,
        realHotplugSucceeded: Bool,
        hotplugUnsupported: Bool,
        providerInstalledButAttachUnsupported: Bool,
        publicBlockHotplugAPIMissing: Bool,
        failurePhase: String?,
        failureErrorType: String?,
        failureErrorMessage: String?,
        blocker: Stage9DBlocker
    ) {
        self.preCreateRegistrationSucceeded = preCreateRegistrationSucceeded
        self.podCreateSucceeded = podCreateSucceeded
        self.firstContainerStarted = firstContainerStarted
        self.postCreateAddContainerAttempted = postCreateAddContainerAttempted
        self.postCreateAddContainerReachedProvider = postCreateAddContainerReachedProvider
        self.postCreateAddContainerSucceeded = postCreateAddContainerSucceeded
        self.secondContainerStarted = secondContainerStarted
        self.realHotplugSucceeded = realHotplugSucceeded
        self.hotplugUnsupported = hotplugUnsupported
        self.providerInstalledButAttachUnsupported = providerInstalledButAttachUnsupported
        self.publicBlockHotplugAPIMissing = publicBlockHotplugAPIMissing
        self.failurePhase = failurePhase
        self.failureErrorType = failureErrorType
        self.failureErrorMessage = failureErrorMessage
        self.blocker = blocker
    }
}

public struct Stage9DCleanupEvidence: Codable, Equatable, Sendable {
    public let cleanupResult: String
    public let cleanupStateDirectoryExistsAfterCleanup: Bool
    public let leftoverPathsCount: Int
    public let providerReleaseCalled: Bool
    public let attachedDeviceDetached: Bool?
    public let zeroAdapterOwnedLeftovers: Bool

    public init(
        cleanupResult: String,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        leftoverPathsCount: Int,
        providerReleaseCalled: Bool,
        attachedDeviceDetached: Bool?,
        zeroAdapterOwnedLeftovers: Bool
    ) {
        self.cleanupResult = cleanupResult
        self.cleanupStateDirectoryExistsAfterCleanup = cleanupStateDirectoryExistsAfterCleanup
        self.leftoverPathsCount = leftoverPathsCount
        self.providerReleaseCalled = providerReleaseCalled
        self.attachedDeviceDetached = attachedDeviceDetached
        self.zeroAdapterOwnedLeftovers = zeroAdapterOwnedLeftovers
    }
}

public struct Stage9DInterpretationEvidence: Codable, Equatable, Sendable {
    public let productHotplugAvailable: Bool
    public let productShouldDependOnHotplug: Bool
    public let nextRecommendedPath: Stage9DNextRecommendedPath

    public init(
        productHotplugAvailable: Bool,
        productShouldDependOnHotplug: Bool,
        nextRecommendedPath: Stage9DNextRecommendedPath
    ) {
        self.productHotplugAvailable = productHotplugAvailable
        self.productShouldDependOnHotplug = productShouldDependOnHotplug
        self.nextRecommendedPath = nextRecommendedPath
    }
}

public struct Stage9DHotplugProviderProbeRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let status: Stage9DProbeStatus
    public let containerizationVersion: String
    public let containerizationRevision: String?
    public let macOSVersion: String
    public let hostArchitecture: String
    public let probeCases: [Stage9DProbeCase]
    public let provider: Stage9DProviderEvidence
    public let rootfs: Stage9DRootfsEvidence
    public let hotplug: Stage9DHotplugEvidence
    public let cleanup: Stage9DCleanupEvidence
    public let interpretation: Stage9DInterpretationEvidence
    public let hostPortTTFBSeconds: Double?
    public let hostPortProbeStatus: String
    public let loadWindowSeconds: Double?
    public let loadWindowStatus: String

    public init(
        timestamp: String,
        status: Stage9DProbeStatus,
        containerizationVersion: String,
        containerizationRevision: String?,
        macOSVersion: String,
        hostArchitecture: String,
        probeCases: [Stage9DProbeCase],
        provider: Stage9DProviderEvidence,
        rootfs: Stage9DRootfsEvidence,
        hotplug: Stage9DHotplugEvidence,
        cleanup: Stage9DCleanupEvidence,
        interpretation: Stage9DInterpretationEvidence,
        hostPortTTFBSeconds: Double?,
        hostPortProbeStatus: String,
        loadWindowSeconds: Double?,
        loadWindowStatus: String
    ) {
        self.schemaVersion = Stage9DHotplugProviderProbeSchema.version
        self.recordType = Stage9DHotplugProviderProbeSchema.recordType
        self.timestamp = timestamp
        self.status = status
        self.containerizationVersion = containerizationVersion
        self.containerizationRevision = containerizationRevision
        self.macOSVersion = macOSVersion
        self.hostArchitecture = hostArchitecture
        self.probeCases = probeCases
        self.provider = provider
        self.rootfs = rootfs
        self.hotplug = hotplug
        self.cleanup = cleanup
        self.interpretation = interpretation
        self.hostPortTTFBSeconds = hostPortTTFBSeconds
        self.hostPortProbeStatus = hostPortProbeStatus
        self.loadWindowSeconds = loadWindowSeconds
        self.loadWindowStatus = loadWindowStatus
    }
}

public struct Stage9DHotplugProviderProbeEvidenceValidator: Sendable {
    public init() {}

    public func validate(records: [Stage9DHotplugProviderProbeRecord]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        if records.isEmpty {
            diagnostics.append(blocking("stage9d-evidence-empty", "Stage 9D hotplug provider probe evidence must include a record."))
        }
        for record in records {
            validate(record, diagnostics: &diagnostics)
        }
        return diagnostics
    }

    public func validate(evidenceURL: URL) throws -> [Diagnostic] {
        let records: [Stage9DHotplugProviderProbeRecord] = try readStage9DHotplugProviderProbeRecords(evidenceURL)
        return validate(records: records)
    }

    private func validate(
        _ record: Stage9DHotplugProviderProbeRecord,
        diagnostics: inout [Diagnostic]
    ) {
        let cases = Set(record.probeCases)
        if cases.contains(.providerInstallOnly) {
            if !record.provider.extensionInstalled
                || record.provider.linuxPodConfigExtensionCount <= 0
                || record.provider.vmConfigExtensionCount <= 0
                || !record.provider.providerDidCreateCalled
                || !record.provider.hotplugProviderInstalled {
                diagnostics.append(blocking("stage9d-provider-installation-incomplete", "Provider-install evidence must show a LinuxPod extension, VM extension, didCreate callback, and installed hotplug provider."))
            }
        }
        if cases.contains(.providerReceivesHotplug) {
            if !record.provider.providerHotplugCalled
                || !record.hotplug.postCreateAddContainerAttempted
                || !record.hotplug.postCreateAddContainerReachedProvider {
                diagnostics.append(blocking("stage9d-provider-call-not-proven", "Provider-receives-hotplug evidence must show addContainer reached the local provider."))
            }
        }
        if cases.contains(.realSecondContainerHotplug) && !record.hotplug.realHotplugSucceeded {
            diagnostics.append(blocking("stage9d-real-hotplug-case-not-proven", "The real hotplug probe case may be recorded only when realHotplugSucceeded is true."))
        }
        if record.hotplug.realHotplugSucceeded
            && (!record.provider.providerHotplugCalled
                || !record.hotplug.postCreateAddContainerSucceeded
                || !record.hotplug.secondContainerStarted
                || !isClean(record.cleanup)
                || !isKnownRealAttachedFilesystem(record.rootfs)) {
            diagnostics.append(blocking("stage9d-real-hotplug-success-unsafe", "realHotplugSucceeded=true requires provider call, addContainer success, second container start, and clean cleanup."))
        }
        if (record.hotplug.realHotplugSucceeded || record.hotplug.postCreateAddContainerSucceeded)
            && !isKnownRealAttachedFilesystem(record.rootfs) {
            diagnostics.append(blocking("stage9d-fake-attached-filesystem", "Stage 9D must not claim addContainer or hotplug success without a known real attached filesystem source."))
        }
        if record.interpretation.productHotplugAvailable
            && (record.hotplug.providerInstalledButAttachUnsupported
                || record.hotplug.publicBlockHotplugAPIMissing
                || !record.hotplug.secondContainerStarted
                || !record.hotplug.realHotplugSucceeded) {
            diagnostics.append(blocking("stage9d-product-availability-unsafe", "productHotplugAvailable=true requires real second-container hotplug and no attach blockers."))
        }
        if record.interpretation.productShouldDependOnHotplug
            && (!record.interpretation.productHotplugAvailable
                || !record.hotplug.realHotplugSucceeded) {
            diagnostics.append(blocking("stage9d-product-dependency-unsafe", "The product path must not depend on hotplug unless real hotplug is available."))
        }
        if !isClean(record.cleanup) {
            diagnostics.append(blocking("stage9d-cleanup-leftovers", "Stage 9D evidence must prove zero adapter-owned runtime leftovers."))
        }
        if record.hostPortTTFBSeconds == nil && record.hostPortProbeStatus != "notMeasured" {
            diagnostics.append(blocking("stage9d-host-port-not-measured-missing", "Missing Stage 9D host-port timing must be marked notMeasured."))
        }
        if record.loadWindowSeconds == nil && record.loadWindowStatus != "notMeasured" {
            diagnostics.append(blocking("stage9d-load-window-not-measured-missing", "Missing Stage 9D load-window timing must be marked notMeasured."))
        }
    }

    private func isClean(_ cleanup: Stage9DCleanupEvidence) -> Bool {
        cleanup.cleanupResult == "clean"
            && !cleanup.cleanupStateDirectoryExistsAfterCleanup
            && cleanup.leftoverPathsCount == 0
            && cleanup.zeroAdapterOwnedLeftovers
    }

    private func isKnownRealAttachedFilesystem(_ rootfs: Stage9DRootfsEvidence) -> Bool {
        guard rootfs.attachedFilesystemSourceKnown,
              rootfs.attachedFilesystemSource?.isEmpty == false else {
            return false
        }
        switch rootfs.rootfsAttachStrategy {
        case .vzUSBMassStorage, .publicVZStorageAttach:
            return true
        case .none, .virtiofsOnly, .unsupported, .notImplemented, .unknown:
            return false
        }
    }
}

public enum Stage10ARootfsMaterializationProbeSchema {
    public static let version = "container-compose-adapter/linuxpod-stage10a-rootfs-materialization-probe/v1"
    public static let recordType = "stage10aRootfsMaterializationProbe"
}

public enum Stage10ARootfsMaterializationStatus: String, Codable, Equatable, Sendable {
    case measured
    case failed
    case unsupported
}

public enum RootfsCloneVerificationStrength: String, Codable, Equatable, Sendable {
    case strong
    case weak
    case unknown
    case notApplicable
}

public enum RootfsMaterializationPhase: String, Codable, Equatable, Sendable {
    case baseRootfsUnpack
    case cachedBaseToProjectRootfs
    case projectRootfsToContainerRootfs
}

public enum RootfsMaterializationNextRecommendedPath: String, Codable, Equatable, Sendable {
    case useAPFSCloneForRootfs
    case useClonefileForRootfs
    case useCopyfileCloneForRootfs
    case investigateWritableLayer
    case keepFullCopy
    case upstreamContainerizationLayerReuse
    case unknown
}

public struct RootfsMaterializationEnvironment: Codable, Equatable, Sendable {
    public let containerizationVersion: String
    public let containerizationRevision: String?
    public let macOSVersion: String
    public let hostArchitecture: String
    public let filesystemType: String?
    public let adapterOwnedStateRoot: String
    public let runtimePath: String
    public let runtimePathRedacted: Bool

    public init(
        containerizationVersion: String,
        containerizationRevision: String?,
        macOSVersion: String,
        hostArchitecture: String,
        filesystemType: String?,
        adapterOwnedStateRoot: String,
        runtimePath: String,
        runtimePathRedacted: Bool
    ) {
        self.containerizationVersion = containerizationVersion
        self.containerizationRevision = containerizationRevision
        self.macOSVersion = macOSVersion
        self.hostArchitecture = hostArchitecture
        self.filesystemType = filesystemType
        self.adapterOwnedStateRoot = adapterOwnedStateRoot
        self.runtimePath = runtimePath
        self.runtimePathRedacted = runtimePathRedacted
    }
}

public struct RootfsMaterializationDiagnostics: Codable, Equatable, Sendable {
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

    public init(
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
        rootfsWorkAvoided: EvidenceTruthValue
    ) {
        self.requestedStrategy = requestedStrategy
        self.actualStrategy = actualStrategy
        self.fallbackStrategy = fallbackStrategy
        self.fallbackReason = fallbackReason
        self.cloneSupported = cloneSupported
        self.cloneAttempted = cloneAttempted
        self.cloneReturnedSuccess = cloneReturnedSuccess
        self.cloneVerified = cloneVerified
        self.cloneVerificationStrength = cloneVerificationStrength
        self.cloneSucceeded = cloneSucceeded
        self.copyAttempted = copyAttempted
        self.copySucceeded = copySucceeded
        self.publicCloneAPIMissing = publicCloneAPIMissing
        self.byteForByteCopyAvoided = byteForByteCopyAvoided
        self.rootfsWorkAvoided = rootfsWorkAvoided
    }
}

public struct RootfsMaterializationPaths: Codable, Equatable, Sendable {
    public let sourceRootfsPath: String?
    public let projectRootfsPath: String?
    public let containerRootfsPath: String?
    public let sourceAndDestinationSameVolume: Bool?

    public init(
        sourceRootfsPath: String?,
        projectRootfsPath: String?,
        containerRootfsPath: String?,
        sourceAndDestinationSameVolume: Bool?
    ) {
        self.sourceRootfsPath = sourceRootfsPath
        self.projectRootfsPath = projectRootfsPath
        self.containerRootfsPath = containerRootfsPath
        self.sourceAndDestinationSameVolume = sourceAndDestinationSameVolume
    }
}

public struct RootfsMaterializationDurations: Codable, Equatable, Sendable {
    public let imageReferenceLookup: Double?
    public let imageStoreLookup: Double?
    public let baseRootfsCacheLookup: Double?
    public let baseRootfsUnpack: Double?
    public let projectRootfsMaterialize: Double?
    public let containerRootfsMaterialize: Double?
    public let mountPrepare: Double?
    public let cleanup: Double?
    public let totalRootfsPrep: Double?

    public init(
        imageReferenceLookup: Double?,
        imageStoreLookup: Double?,
        baseRootfsCacheLookup: Double?,
        baseRootfsUnpack: Double?,
        projectRootfsMaterialize: Double?,
        containerRootfsMaterialize: Double?,
        mountPrepare: Double?,
        cleanup: Double?,
        totalRootfsPrep: Double?
    ) {
        self.imageReferenceLookup = imageReferenceLookup
        self.imageStoreLookup = imageStoreLookup
        self.baseRootfsCacheLookup = baseRootfsCacheLookup
        self.baseRootfsUnpack = baseRootfsUnpack
        self.projectRootfsMaterialize = projectRootfsMaterialize
        self.containerRootfsMaterialize = containerRootfsMaterialize
        self.mountPrepare = mountPrepare
        self.cleanup = cleanup
        self.totalRootfsPrep = totalRootfsPrep
    }
}

public struct RootfsMaterializationSizes: Codable, Equatable, Sendable {
    public let sourceRootfs: UInt64?
    public let projectRootfs: UInt64?
    public let containerRootfs: UInt64?
    public let apparentSize: UInt64?
    public let allocatedSize: UInt64?
    public let bytesCopiedIfKnown: UInt64?

    public init(
        sourceRootfs: UInt64?,
        projectRootfs: UInt64?,
        containerRootfs: UInt64?,
        apparentSize: UInt64?,
        allocatedSize: UInt64?,
        bytesCopiedIfKnown: UInt64?
    ) {
        self.sourceRootfs = sourceRootfs
        self.projectRootfs = projectRootfs
        self.containerRootfs = containerRootfs
        self.apparentSize = apparentSize
        self.allocatedSize = allocatedSize
        self.bytesCopiedIfKnown = bytesCopiedIfKnown
    }
}

public struct RootfsMaterializationIOEvidence: Codable, Equatable, Sendable {
    public let blockReadBytesWholeRun: UInt64?
    public let blockWriteBytesWholeRun: UInt64?
    public let phaseBlockIOAttribution: String

    public init(
        blockReadBytesWholeRun: UInt64?,
        blockWriteBytesWholeRun: UInt64?,
        phaseBlockIOAttribution: String
    ) {
        self.blockReadBytesWholeRun = blockReadBytesWholeRun
        self.blockWriteBytesWholeRun = blockWriteBytesWholeRun
        self.phaseBlockIOAttribution = phaseBlockIOAttribution
    }
}

public struct RootfsMaterializationCorrectnessEvidence: Codable, Equatable, Sendable {
    public let projectRootfsExists: Bool
    public let containerRootfsExists: Bool
    public let containerRootfsReadable: Bool
    public let ext4ImageLooksValid: Bool?
    public let noMutationOfBaseRootfs: Bool
    public let baseRootfsChecksumBefore: String?
    public let baseRootfsChecksumAfter: String?
    public let baseRootfsUnchanged: EvidenceTruthValue

    public init(
        projectRootfsExists: Bool,
        containerRootfsExists: Bool,
        containerRootfsReadable: Bool,
        ext4ImageLooksValid: Bool?,
        noMutationOfBaseRootfs: Bool,
        baseRootfsChecksumBefore: String?,
        baseRootfsChecksumAfter: String?,
        baseRootfsUnchanged: EvidenceTruthValue
    ) {
        self.projectRootfsExists = projectRootfsExists
        self.containerRootfsExists = containerRootfsExists
        self.containerRootfsReadable = containerRootfsReadable
        self.ext4ImageLooksValid = ext4ImageLooksValid
        self.noMutationOfBaseRootfs = noMutationOfBaseRootfs
        self.baseRootfsChecksumBefore = baseRootfsChecksumBefore
        self.baseRootfsChecksumAfter = baseRootfsChecksumAfter
        self.baseRootfsUnchanged = baseRootfsUnchanged
    }
}

public struct RootfsMaterializationCleanupEvidence: Codable, Equatable, Sendable {
    public let cleanupResult: String
    public let cleanupStateDirectoryExistsAfterCleanup: Bool
    public let leftoverPathsCount: Int
    public let zeroAdapterOwnedLeftovers: Bool

    public init(
        cleanupResult: String,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        leftoverPathsCount: Int,
        zeroAdapterOwnedLeftovers: Bool
    ) {
        self.cleanupResult = cleanupResult
        self.cleanupStateDirectoryExistsAfterCleanup = cleanupStateDirectoryExistsAfterCleanup
        self.leftoverPathsCount = leftoverPathsCount
        self.zeroAdapterOwnedLeftovers = zeroAdapterOwnedLeftovers
    }
}

public struct RootfsMaterializationInterpretation: Codable, Equatable, Sendable {
    public let materializationImproved: Bool
    public let productReady: Bool
    public let nextRecommendedPath: RootfsMaterializationNextRecommendedPath

    public init(
        materializationImproved: Bool,
        productReady: Bool,
        nextRecommendedPath: RootfsMaterializationNextRecommendedPath
    ) {
        self.materializationImproved = materializationImproved
        self.productReady = productReady
        self.nextRecommendedPath = nextRecommendedPath
    }
}

public struct RootfsMaterializationProbeRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let status: Stage10ARootfsMaterializationStatus
    public let environment: RootfsMaterializationEnvironment
    public let strategy: RootfsMaterializationDiagnostics
    public let paths: RootfsMaterializationPaths
    public let durationsSeconds: RootfsMaterializationDurations
    public let sizesBytes: RootfsMaterializationSizes
    public let io: RootfsMaterializationIOEvidence
    public let correctness: RootfsMaterializationCorrectnessEvidence
    public let cleanup: RootfsMaterializationCleanupEvidence
    public let interpretation: RootfsMaterializationInterpretation

    public init(
        timestamp: String,
        status: Stage10ARootfsMaterializationStatus,
        environment: RootfsMaterializationEnvironment,
        strategy: RootfsMaterializationDiagnostics,
        paths: RootfsMaterializationPaths,
        durationsSeconds: RootfsMaterializationDurations,
        sizesBytes: RootfsMaterializationSizes,
        io: RootfsMaterializationIOEvidence,
        correctness: RootfsMaterializationCorrectnessEvidence,
        cleanup: RootfsMaterializationCleanupEvidence,
        interpretation: RootfsMaterializationInterpretation
    ) {
        self.schemaVersion = Stage10ARootfsMaterializationProbeSchema.version
        self.recordType = Stage10ARootfsMaterializationProbeSchema.recordType
        self.timestamp = timestamp
        self.status = status
        self.environment = environment
        self.strategy = strategy
        self.paths = paths
        self.durationsSeconds = durationsSeconds
        self.sizesBytes = sizesBytes
        self.io = io
        self.correctness = correctness
        self.cleanup = cleanup
        self.interpretation = interpretation
    }
}

public struct Stage10ARootfsMaterializationProbeEvidenceValidator: Sendable {
    public init() {}

    public func validate(records: [RootfsMaterializationProbeRecord]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        if records.isEmpty {
            diagnostics.append(blocking("stage10a-evidence-empty", "Stage 10A rootfs materialization evidence must include a probe record."))
        }
        for record in records {
            validate(record, diagnostics: &diagnostics)
        }
        return diagnostics
    }

    public func validate(evidenceURL: URL) throws -> [Diagnostic] {
        let records: [RootfsMaterializationProbeRecord] = try readStage10ARootfsMaterializationProbeRecords(evidenceURL)
        return validate(records: records)
    }

    private func validate(
        _ record: RootfsMaterializationProbeRecord,
        diagnostics: inout [Diagnostic]
    ) {
        let clean = isClean(record.cleanup)
        if !record.environment.runtimePathRedacted || containsLocalPath(record.environment.runtimePath) {
            diagnostics.append(blocking("stage10a-runtime-path-not-redacted", "Stage 10A evidence must redact local runtime paths."))
        }
        if containsLocalPath(record.environment.adapterOwnedStateRoot)
            || containsLocalPath(record.paths.sourceRootfsPath)
            || containsLocalPath(record.paths.projectRootfsPath)
            || containsLocalPath(record.paths.containerRootfsPath) {
            diagnostics.append(blocking("stage10a-path-leak", "Stage 10A evidence paths must be redacted before check-in."))
        }
        if record.strategy.cloneSucceeded {
            if !record.strategy.cloneAttempted || !record.strategy.cloneReturnedSuccess {
                diagnostics.append(blocking("stage10a-clone-success-unproven", "cloneSucceeded=true requires cloneAttempted and cloneReturnedSuccess."))
            }
        }
        if record.strategy.cloneReturnedSuccess && !record.strategy.cloneSucceeded {
            diagnostics.append(blocking("stage10a-clone-return-not-classified", "A successful clone API return must be classified as cloneSucceeded or explained before validation."))
        }
        if record.strategy.actualStrategy.isCloneStrategy
            && record.strategy.cloneSucceeded
            && record.strategy.byteForByteCopyAvoided == .false {
            diagnostics.append(blocking("stage10a-clone-copy-avoidance-contradiction", "Clone strategy success cannot also record byteForByteCopyAvoided=false."))
        }
        if record.status == .unsupported && !record.strategy.publicCloneAPIMissing && record.strategy.actualStrategy != .unsupported {
            diagnostics.append(blocking("stage10a-unsupported-record-unclear", "Unsupported Stage 10A records must identify the unsupported strategy or missing public clone API."))
        }
        if record.io.phaseBlockIOAttribution != "phaseMeasured"
            && record.io.phaseBlockIOAttribution != "wholeRunOnly"
            && record.io.phaseBlockIOAttribution != "notMeasured" {
            diagnostics.append(blocking("stage10a-block-io-attribution-invalid", "Stage 10A block I/O attribution must be phaseMeasured, wholeRunOnly, or notMeasured."))
        }
        if record.interpretation.productReady {
            if !clean {
                diagnostics.append(blocking("stage10a-product-ready-cleanup-unsafe", "productReady=true requires clean zero-leftover cleanup."))
            }
            if record.strategy.rootfsWorkAvoided != .true && record.strategy.byteForByteCopyAvoided != .true {
                diagnostics.append(blocking("stage10a-product-ready-work-not-avoided", "productReady=true requires rootfsWorkAvoided=true or byteForByteCopyAvoided=true."))
            }
            if record.strategy.cloneSucceeded
                && (record.strategy.cloneVerificationStrength == .unknown
                    || record.strategy.cloneVerificationStrength == .notApplicable
                    || !record.strategy.cloneVerified) {
                diagnostics.append(blocking("stage10a-product-ready-clone-verification-unknown", "productReady=true cannot rely on unverified clone success."))
            }
            if !record.correctness.noMutationOfBaseRootfs || record.correctness.baseRootfsUnchanged != .true {
                diagnostics.append(blocking("stage10a-product-ready-base-rootfs-unverified", "productReady=true requires proof that the cached base rootfs was not mutated."))
            }
            if !record.correctness.projectRootfsExists
                || !record.correctness.containerRootfsExists
                || !record.correctness.containerRootfsReadable {
                diagnostics.append(blocking("stage10a-product-ready-rootfs-unusable", "productReady=true requires readable project and container rootfs artifacts during the probe."))
            }
        }
    }

    private func isClean(_ cleanup: RootfsMaterializationCleanupEvidence) -> Bool {
        cleanup.cleanupResult == "clean"
            && !cleanup.cleanupStateDirectoryExistsAfterCleanup
            && cleanup.leftoverPathsCount == 0
            && cleanup.zeroAdapterOwnedLeftovers
    }

    private func containsLocalPath(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        return path.contains("/Users/")
            || path.contains("marlonjd")
            || path.contains("/private/")
    }
}

public struct BenchmarkRunMetadata: Codable, Equatable, Sendable {
    public let runtime: RuntimeKind
    public let targetName: String
    public let coldOrWarm: String
    public let runtimeVersion: String
    public let containerizationVersion: String?
    public let appleContainerCLIVersion: String?
    public let macOSVersion: String
    public let hostArchitecture: String
    public let lifecycle: BenchmarkLifecycle
    public let lifecycleMode: String
    public let lifecycleModeID: String
    public let seedImageStoreRequested: Bool
    public let seedImageStoreCopied: Bool
    public let seedImageStoreValidated: Bool
    public let seedImageStorePath: String?
    public let projectRuntimeExistedBeforeRun: Bool
    public let projectRuntimeDirectoryExistedBeforeSeed: Bool
    public let projectRuntimeDirectoryExistedBeforeRun: Bool
    public let podExistedBeforeRun: Bool
    public let podReuseVerificationStatus: String?
    public let imageCacheStatus: BenchmarkCacheStatus
    public let rootfsCacheStatus: BenchmarkCacheStatus
    public let initfsCacheStatus: BenchmarkCacheStatus
    public let volumeExistedBeforeRun: Bool
    public let hostPortPublished: Bool?
    public let hostPortTTFBSeconds: Double?
    public let hostPortProbeStatus: String
    public let hostPortPublishingNotImplemented: Bool
    public let loadWindowSeconds: Double?
    public let loadWindowStatus: String
    public let completedRequests: Int?
    public let requestFailureCount: Int?

    private enum CodingKeys: String, CodingKey {
        case runtime
        case targetName = "target_name"
        case coldOrWarm = "cold_or_warm"
        case runtimeVersion
        case containerizationVersion
        case appleContainerCLIVersion
        case macOSVersion
        case hostArchitecture
        case lifecycle
        case lifecycleMode
        case lifecycleModeID
        case seedImageStoreRequested
        case seedImageStoreCopied
        case seedImageStoreValidated
        case seedImageStorePath
        case projectRuntimeExistedBeforeRun
        case projectRuntimeDirectoryExistedBeforeSeed
        case projectRuntimeDirectoryExistedBeforeRun
        case podExistedBeforeRun
        case podReuseVerificationStatus
        case imageCacheStatus
        case rootfsCacheStatus
        case initfsCacheStatus
        case volumeExistedBeforeRun
        case hostPortPublished
        case hostPortTTFBSeconds
        case hostPortProbeStatus
        case hostPortPublishingNotImplemented
        case loadWindowSeconds
        case loadWindowStatus
        case completedRequests
        case requestFailureCount
    }

    public init(
        runtime: RuntimeKind,
        targetName: String? = nil,
        runtimeVersion: String,
        containerizationVersion: String? = nil,
        appleContainerCLIVersion: String? = nil,
        macOSVersion: String,
        hostArchitecture: String,
        lifecycle: BenchmarkLifecycle,
        lifecycleMode: BenchmarkLifecycleMode? = nil,
        seedImageStoreRequested: Bool = false,
        seedImageStoreCopied: Bool = false,
        seedImageStoreValidated: Bool = false,
        seedImageStorePath: String? = nil,
        projectRuntimeExistedBeforeRun: Bool? = nil,
        projectRuntimeDirectoryExistedBeforeSeed: Bool = false,
        projectRuntimeDirectoryExistedBeforeRun: Bool? = nil,
        podExistedBeforeRun: Bool = false,
        podReuseVerificationStatus: String? = nil,
        imageCacheStatus: BenchmarkCacheStatus,
        rootfsCacheStatus: BenchmarkCacheStatus,
        initfsCacheStatus: BenchmarkCacheStatus,
        volumeExistedBeforeRun: Bool,
        hostPortPublished: Bool? = nil,
        hostPortTTFBSeconds: Double? = nil,
        hostPortProbeStatus: String = "notMeasured",
        hostPortPublishingNotImplemented: Bool = false,
        loadWindowSeconds: Double? = nil,
        loadWindowStatus: String = "notMeasured",
        completedRequests: Int? = nil,
        requestFailureCount: Int? = nil
    ) {
        self.runtime = runtime
        self.targetName = targetName ?? runtime.rawValue
        self.coldOrWarm = lifecycle.rawValue
        self.runtimeVersion = runtimeVersion
        self.containerizationVersion = containerizationVersion
        self.appleContainerCLIVersion = appleContainerCLIVersion
        self.macOSVersion = macOSVersion
        self.hostArchitecture = hostArchitecture
        self.lifecycle = lifecycle
        let resolvedMode = lifecycleMode ?? BenchmarkLifecycleMode.classify(
            lifecycle: lifecycle,
            seedImageStoreCopied: seedImageStoreCopied,
            rootfsCacheStatus: rootfsCacheStatus,
            initfsCacheStatus: initfsCacheStatus,
            volumeExistedBeforeRun: volumeExistedBeforeRun,
            podExistedBeforeRun: podExistedBeforeRun
        )
        self.lifecycleMode = resolvedMode.rawValue
        self.lifecycleModeID = resolvedMode.id
        self.seedImageStoreRequested = seedImageStoreRequested
        self.seedImageStoreCopied = seedImageStoreCopied
        self.seedImageStoreValidated = seedImageStoreValidated
        self.seedImageStorePath = seedImageStorePath
        let directoryBeforeRun = projectRuntimeDirectoryExistedBeforeRun
            ?? projectRuntimeExistedBeforeRun
            ?? false
        self.projectRuntimeExistedBeforeRun = projectRuntimeExistedBeforeRun ?? directoryBeforeRun
        self.projectRuntimeDirectoryExistedBeforeSeed = projectRuntimeDirectoryExistedBeforeSeed
        self.projectRuntimeDirectoryExistedBeforeRun = directoryBeforeRun
        self.podExistedBeforeRun = podExistedBeforeRun
        self.podReuseVerificationStatus = podReuseVerificationStatus ?? (podExistedBeforeRun ? "liveExecutorState" : "notApplicable")
        self.imageCacheStatus = imageCacheStatus
        self.rootfsCacheStatus = rootfsCacheStatus
        self.initfsCacheStatus = initfsCacheStatus
        self.volumeExistedBeforeRun = volumeExistedBeforeRun
        self.hostPortPublished = hostPortPublished
        self.hostPortTTFBSeconds = hostPortTTFBSeconds
        self.hostPortProbeStatus = hostPortProbeStatus
        self.hostPortPublishingNotImplemented = hostPortPublishingNotImplemented
        self.loadWindowSeconds = loadWindowSeconds
        self.loadWindowStatus = loadWindowStatus
        self.completedRequests = completedRequests
        self.requestFailureCount = requestFailureCount
    }
}

public enum Phase6BenchmarkIterationStatus: String, Codable, Equatable, Sendable {
    case measured
    case failed
}

public enum Phase6HostPhysicalMemoryStatus: String, Codable, Equatable, Sendable {
    case blocked
}

public struct Phase6BenchmarkDurations: Codable, Equatable, Sendable {
    public let up: Double?
    public let status: Double?
    public let logs: Double?
    public let cleanup: Double?
    public let rootfsPrep: Double?
    public let initfsPrep: Double?
    public let volumeCreateOrReuse: Double?
    public let podCreateOrReuse: Double?
    public let containerStart: Double?
    public let healthcheck: Double?

    public init(
        up: Double?,
        status: Double?,
        logs: Double?,
        cleanup: Double?,
        rootfsPrep: Double? = nil,
        initfsPrep: Double? = nil,
        volumeCreateOrReuse: Double? = nil,
        podCreateOrReuse: Double? = nil,
        containerStart: Double? = nil,
        healthcheck: Double? = nil
    ) {
        self.up = up
        self.status = status
        self.logs = logs
        self.cleanup = cleanup
        self.rootfsPrep = rootfsPrep
        self.initfsPrep = initfsPrep
        self.volumeCreateOrReuse = volumeCreateOrReuse
        self.podCreateOrReuse = podCreateOrReuse
        self.containerStart = containerStart
        self.healthcheck = healthcheck
    }
}

public struct Phase6BenchmarkIterationRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let project: String
    public let runLabel: String
    public let iteration: Int
    public let environment: BenchmarkRunMetadata?
    public let status: Phase6BenchmarkIterationStatus
    public let durationsSeconds: Phase6BenchmarkDurations
    public let guest: HostFootprintGuestStats?
    public let hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus
    public let actionCount: Int
    public let cleanupStateDirectoryExistsAfterCleanup: Bool
    public let healthcheckAttempts: Int?
    public let dataFootprintBytes: UInt64?
    public let cleanupResult: String
    public let failure: String?
    public let rootfsPreparation: [RootfsPreparationBreakdown]?
    public let hotplugDiagnostics: HotplugLifecycleDiagnostics?
    public let warmServiceRecreate: WarmServiceRecreateMetadata?
    public let blockIOAttribution: String?
    public let rootfsBlockIOAttribution: String?

    public init(
        timestamp: String,
        project: String,
        runLabel: String,
        iteration: Int,
        environment: BenchmarkRunMetadata? = nil,
        status: Phase6BenchmarkIterationStatus,
        durationsSeconds: Phase6BenchmarkDurations,
        guest: HostFootprintGuestStats?,
        hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus,
        actionCount: Int,
        cleanupStateDirectoryExistsAfterCleanup: Bool,
        healthcheckAttempts: Int? = nil,
        dataFootprintBytes: UInt64? = nil,
        cleanupResult: String? = nil,
        failure: String?,
        rootfsPreparation: [RootfsPreparationBreakdown]? = nil,
        hotplugDiagnostics: HotplugLifecycleDiagnostics? = nil,
        warmServiceRecreate: WarmServiceRecreateMetadata? = nil,
        blockIOAttribution: String? = nil,
        rootfsBlockIOAttribution: String? = nil
    ) {
        self.schemaVersion = Phase6BenchmarkSchema.version
        self.recordType = Phase6BenchmarkSchema.iterationRecordType
        self.timestamp = timestamp
        self.project = project
        self.runLabel = runLabel
        self.iteration = iteration
        self.environment = environment
        self.status = status
        self.durationsSeconds = durationsSeconds
        self.guest = guest
        self.hostPhysicalMemoryStatus = hostPhysicalMemoryStatus
        self.actionCount = actionCount
        self.cleanupStateDirectoryExistsAfterCleanup = cleanupStateDirectoryExistsAfterCleanup
        self.healthcheckAttempts = healthcheckAttempts
        self.dataFootprintBytes = dataFootprintBytes
        self.cleanupResult = cleanupResult ?? (cleanupStateDirectoryExistsAfterCleanup ? "leftovers" : "clean")
        self.failure = failure
        self.rootfsPreparation = rootfsPreparation
        self.hotplugDiagnostics = hotplugDiagnostics
        self.warmServiceRecreate = warmServiceRecreate
        self.blockIOAttribution = blockIOAttribution
        self.rootfsBlockIOAttribution = rootfsBlockIOAttribution
    }
}

public struct Phase6BenchmarkSummaryRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let recordType: String
    public let timestamp: String
    public let projectPrefix: String
    public let runLabel: String
    public let environment: BenchmarkRunMetadata?
    public let requestedIterations: Int
    public let measuredIterations: Int
    public let failureCount: Int
    public let hostPhysicalMemoryStatus: Phase6HostPhysicalMemoryStatus
    public let guestCgroupMemoryCurrentP50Bytes: UInt64?
    public let guestCgroupMemoryLimitBytes: UInt64?
    public let processCountP50: UInt64?
    public let cpuUsageUsecP50: UInt64?
    public let blockReadP50Bytes: UInt64?
    public let blockWriteP50Bytes: UInt64?
    public let upDurationP50Seconds: Double?
    public let statusDurationP50Seconds: Double?
    public let logsDurationP50Seconds: Double?
    public let cleanupDurationP50Seconds: Double?
    public let rootfsPrepDurationP50Seconds: Double?
    public let initfsPrepDurationP50Seconds: Double?
    public let volumeCreateOrReuseDurationP50Seconds: Double?
    public let podCreateOrReuseDurationP50Seconds: Double?
    public let containerStartDurationP50Seconds: Double?
    public let healthcheckDurationP50Seconds: Double?
    public let healthcheckAttemptsP50: Int?
    public let lifecycleMode: String?
    public let lifecycleModeID: String?
    public let statusTimingMeaning: String
    public let logsTimingMeaning: String
    public let hostPortPublished: Bool?
    public let hostPortTTFBSeconds: Double?
    public let hostPortProbeStatus: String
    public let loadWindowSeconds: Double?
    public let loadWindowStatus: String
    public let completedRequests: Int?
    public let requestFailureCount: Int?
    public let processRSSP50Bytes: UInt64?
    public let dataFootprintP50Bytes: UInt64?
    public let cleanupResult: String?

    public init(
        timestamp: String,
        projectPrefix: String,
        runLabel: String,
        requestedIterations: Int,
        records: [Phase6BenchmarkIterationRecord]
    ) {
        let measured = records.filter { $0.status == .measured }
        self.schemaVersion = Phase6BenchmarkSchema.version
        self.recordType = Phase6BenchmarkSchema.summaryRecordType
        self.timestamp = timestamp
        self.projectPrefix = projectPrefix
        self.runLabel = runLabel
        self.environment = records.compactMap(\.environment).first
        self.requestedIterations = requestedIterations
        self.measuredIterations = measured.count
        self.failureCount = records.filter { $0.status == .failed }.count
        self.hostPhysicalMemoryStatus = .blocked
        self.guestCgroupMemoryCurrentP50Bytes = p50(measured.compactMap { $0.guest?.cgroupMemoryCurrentBytes })
        self.guestCgroupMemoryLimitBytes = p50(measured.compactMap { $0.guest?.cgroupMemoryLimitBytes })
        self.processCountP50 = p50(measured.compactMap { $0.guest?.processCount })
        self.cpuUsageUsecP50 = p50(measured.compactMap { $0.guest?.cpuUsageUsec })
        self.blockReadP50Bytes = p50(measured.compactMap { $0.guest?.blockReadBytes })
        self.blockWriteP50Bytes = p50(measured.compactMap { $0.guest?.blockWriteBytes })
        self.upDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.up))
        self.statusDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.status))
        self.logsDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.logs))
        self.cleanupDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.cleanup))
        self.rootfsPrepDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.rootfsPrep))
        self.initfsPrepDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.initfsPrep))
        self.volumeCreateOrReuseDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.volumeCreateOrReuse))
        self.podCreateOrReuseDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.podCreateOrReuse))
        self.containerStartDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.containerStart))
        self.healthcheckDurationP50Seconds = p50(measured.compactMap(\.durationsSeconds.healthcheck))
        self.healthcheckAttemptsP50 = p50(measured.compactMap(\.healthcheckAttempts))
        self.lifecycleMode = self.environment?.lifecycleMode
        self.lifecycleModeID = self.environment?.lifecycleModeID
        self.statusTimingMeaning = "control-plane-local-state"
        self.logsTimingMeaning = "control-plane-no-op"
        self.hostPortPublished = self.environment?.hostPortPublished
        self.hostPortTTFBSeconds = self.environment?.hostPortTTFBSeconds
        self.hostPortProbeStatus = self.environment?.hostPortProbeStatus ?? "notMeasured"
        self.loadWindowSeconds = self.environment?.loadWindowSeconds
        self.loadWindowStatus = self.environment?.loadWindowStatus ?? "notMeasured"
        self.completedRequests = self.environment?.completedRequests
        self.requestFailureCount = self.environment?.requestFailureCount
        self.processRSSP50Bytes = p50(measured.compactMap { $0.guest?.processRSSBytes })
        self.dataFootprintP50Bytes = p50(measured.compactMap(\.dataFootprintBytes))
        self.cleanupResult = measured.first?.cleanupResult
    }
}

public struct Stage8BenchmarkEvidenceValidator: Sendable {
    public init() {}

    public func validate(records: [Phase6BenchmarkIterationRecord]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        if records.isEmpty {
            diagnostics.append(blocking("stage8-evidence-empty", "Stage 8 benchmark evidence must include iteration records."))
        }
        for record in records {
            validate(record, diagnostics: &diagnostics)
        }
        if records.contains(where: Self.isWarmReusePreservedCleanup)
            && !records.contains(where: Self.isCleanFinalCleanup) {
            diagnostics.append(blocking("stage8-final-cleanup-missing", "Stage 8 warm-reuse evidence must include a final clean cleanup proof."))
        }
        return diagnostics
    }

    public func validate(evidenceURL: URL) throws -> [Diagnostic] {
        let records: [Phase6BenchmarkIterationRecord] = try readStage8IterationRecords(evidenceURL)
        return validate(records: records)
    }

    private func validate(
        _ record: Phase6BenchmarkIterationRecord,
        diagnostics: inout [Diagnostic]
    ) {
        guard let environment = record.environment else {
            diagnostics.append(blocking("stage8-environment-missing", "Stage 8 records must include runtime metadata."))
            return
        }

        if environment.lifecycleModeID.isEmpty || !Self.validLifecycleModeIDs.contains(environment.lifecycleModeID) {
            diagnostics.append(blocking("stage8-lifecycle-mode-id-missing", "Stage 8 records must include an A/B/C/D/E/F/G lifecycle mode id."))
        }
        guard let mode = BenchmarkLifecycleMode(rawValue: environment.lifecycleMode) else {
            diagnostics.append(blocking("stage8-lifecycle-mode-missing", "Stage 8 records must include a recognized lifecycle mode."))
            return
        }
        if environment.lifecycleModeID != mode.id {
            diagnostics.append(blocking("stage8-lifecycle-mode-id-mismatch", "Stage 8 lifecycle mode id must match the lifecycle mode."))
        }
        let classified = BenchmarkLifecycleMode.classify(
            lifecycle: environment.lifecycle,
            seedImageStoreCopied: environment.seedImageStoreCopied,
            rootfsCacheStatus: environment.rootfsCacheStatus,
            initfsCacheStatus: environment.initfsCacheStatus,
            volumeExistedBeforeRun: environment.volumeExistedBeforeRun,
            podExistedBeforeRun: environment.podExistedBeforeRun
        )
        if classified != mode {
            diagnostics.append(blocking("stage8-lifecycle-mode-cache-mismatch", "Stage 8 lifecycle mode does not match cache/reuse metadata."))
        }
        if Self.requiresLivePodReuse(mode),
           environment.podReuseVerificationStatus != "liveExecutorState" {
            diagnostics.append(blocking("stage8-pod-reuse-unverified", "Stage 8 pod warm-reuse evidence must be verified from live executor state, not marker files alone."))
        }
        validateHotplugDiagnostics(record, mode: mode, diagnostics: &diagnostics)
        validateWarmServiceRecreate(record, mode: mode, diagnostics: &diagnostics)
        if environment.hostPortTTFBSeconds == nil && environment.hostPortProbeStatus != "notMeasured" {
            diagnostics.append(blocking("stage8-host-port-not-measured-missing", "Missing host-port TTFB must be marked notMeasured."))
        }
        if environment.loadWindowSeconds == nil
            && environment.completedRequests == nil
            && environment.requestFailureCount == nil
            && environment.loadWindowStatus != "notMeasured" {
            diagnostics.append(blocking("stage8-load-window-not-measured-missing", "Missing load-window metrics must be marked notMeasured."))
        }

        if Self.isStructuredKnownHotplugBlocker(record, mode: mode) {
            return
        }

        validateMetrics(record, diagnostics: &diagnostics)
    }

    private func validateMetrics(
        _ record: Phase6BenchmarkIterationRecord,
        diagnostics: inout [Diagnostic]
    ) {
        if record.durationsSeconds.up == nil {
            diagnostics.append(blocking("stage8-startup-duration-missing", "Stage 8 records must preserve startup/readiness duration."))
        }
        if record.durationsSeconds.rootfsPrep == nil {
            diagnostics.append(blocking("stage8-rootfs-prep-duration-missing", "Stage 8 records must preserve rootfs prep duration."))
        }
        validateStage9MeasuredDiagnostics(record, diagnostics: &diagnostics)
        if record.durationsSeconds.initfsPrep == nil {
            diagnostics.append(blocking("stage8-initfs-prep-duration-missing", "Stage 8 records must preserve initfs prep duration."))
        }
        if record.durationsSeconds.volumeCreateOrReuse == nil {
            diagnostics.append(blocking("stage8-volume-duration-missing", "Stage 8 records must preserve volume create/reuse duration."))
        }
        if record.durationsSeconds.podCreateOrReuse == nil {
            diagnostics.append(blocking("stage8-pod-duration-missing", "Stage 8 records must preserve pod create/reuse duration."))
        }
        if record.durationsSeconds.containerStart == nil {
            diagnostics.append(blocking("stage8-container-start-duration-missing", "Stage 8 records must preserve container start duration."))
        }
        if record.durationsSeconds.healthcheck == nil {
            diagnostics.append(blocking("stage8-healthcheck-duration-missing", "Stage 8 records must preserve healthcheck duration."))
        }
        if record.healthcheckAttempts == nil {
            diagnostics.append(blocking("stage8-healthcheck-attempts-missing", "Stage 8 records must preserve healthcheck attempts."))
        }
        if let guest = record.guest {
            if guest.processRSSBytes == nil {
                diagnostics.append(blocking("stage8-process-rss-missing", "Stage 8 records must preserve process RSS when measured."))
            }
        } else {
            diagnostics.append(blocking("stage8-guest-metrics-missing", "Stage 8 records must preserve cgroup and block I/O metrics."))
            diagnostics.append(blocking("stage8-process-rss-missing", "Stage 8 records must preserve process RSS when measured."))
        }
        if record.dataFootprintBytes == nil {
            diagnostics.append(blocking("stage8-data-footprint-missing", "Stage 8 records must preserve data footprint."))
        }
        if Self.isWarmReusePreservedCleanup(record) {
            return
        }
        if record.cleanupResult != "clean" || record.cleanupStateDirectoryExistsAfterCleanup {
            diagnostics.append(blocking("stage8-cleanup-leftovers", "Stage 8 cleanup proof must show no adapter-owned project runtime leftovers."))
        }
    }

    private func validateStage9MeasuredDiagnostics(
        _ record: Phase6BenchmarkIterationRecord,
        diagnostics: inout [Diagnostic]
    ) {
        guard record.status == .measured else {
            return
        }
        if record.rootfsPreparation?.isEmpty != false {
            diagnostics.append(blocking("stage9-rootfs-breakdown-missing", "Measured Stage 9A records must include rootfs preparation phase breakdown metadata."))
        }
        if record.blockIOAttribution != "wholeRunOnly"
            || record.rootfsBlockIOAttribution != "notMeasured" {
            diagnostics.append(blocking("stage9-block-io-attribution-missing", "Stage 9A records must label block I/O as wholeRunOnly and rootfs block I/O as notMeasured when phase-level I/O is unavailable."))
        }
    }

    private func validateHotplugDiagnostics(
        _ record: Phase6BenchmarkIterationRecord,
        mode: BenchmarkLifecycleMode,
        diagnostics: inout [Diagnostic]
    ) {
        guard Self.requiresLivePodReuse(mode) else {
            return
        }
        guard let hotplug = record.hotplugDiagnostics else {
            if mode == .persistentPodHotplug || mode == .allWarmProjectRuntime {
                diagnostics.append(blocking("stage9-hotplug-diagnostics-missing", "Stage 9A pod reuse and hotplug records must include structured lifecycle diagnostics."))
            }
            return
        }
        if hotplug.podReuseClaim == .markerOnly {
            diagnostics.append(blocking("stage9-marker-only-pod-reuse", "Marker files alone must not be accepted as persistent pod reuse evidence."))
        }
        if mode == .persistentPodHotplug,
           record.status == .failed,
           !Self.isStructuredKnownHotplugBlocker(record, mode: mode) {
            diagnostics.append(blocking("stage9-hotplug-failure-metadata-missing", "Failed F hotplug evidence must include addContainer failure phase, error metadata, mutation state, and clean cleanup."))
        }
    }

    private func validateWarmServiceRecreate(
        _ record: Phase6BenchmarkIterationRecord,
        mode: BenchmarkLifecycleMode,
        diagnostics: inout [Diagnostic]
    ) {
        guard mode == .allWarmProjectRuntime else {
            return
        }
        guard let recreate = record.warmServiceRecreate else {
            diagnostics.append(blocking("stage9-warm-service-recreate-missing", "G all-warm evidence must include forced service recreate metadata or explicitly mark no-op warm reconcile as not product viability evidence."))
            return
        }
        if !recreate.forcedServiceRecreateRequested {
            let explicitlyNoOp = recreate.noOpWarmReconcile
                && recreate.notProductViabilityEvidence
                && recreate.recreateStrategy == .noOp
                && recreate.hostPortStatus == "notMeasured"
                && recreate.loadWindowStatus == "notMeasured"
            if !explicitlyNoOp {
                diagnostics.append(blocking("stage9-all-warm-viability-claim-unsafe", "G all-warm no-op evidence must be marked noOpWarmReconcile and notProductViabilityEvidence."))
            }
        }
    }

    private static let validLifecycleModeIDs = Set(BenchmarkLifecycleMode.allCases.map(\.id))

    private static func requiresLivePodReuse(_ mode: BenchmarkLifecycleMode) -> Bool {
        switch mode {
        case .persistentPodHotplug, .allWarmProjectRuntime:
            return true
        case .coldRuntime,
             .imageStoreSeededFreshRuntime,
             .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime,
             .warmPreservedVolume:
            return false
        }
    }

    private static func isStructuredKnownHotplugBlocker(
        _ record: Phase6BenchmarkIterationRecord,
        mode: BenchmarkLifecycleMode
    ) -> Bool {
        guard mode == .persistentPodHotplug,
              record.status == .failed,
              record.cleanupResult == "clean",
              !record.cleanupStateDirectoryExistsAfterCleanup,
              let hotplug = record.hotplugDiagnostics else {
            return false
        }
        return hotplug.podReuseClaim != .markerOnly
            && hotplug.addContainerAttempted
            && hotplug.addContainerPhase == .afterPodCreate
            && hotplug.hotplugAttempted
            && !hotplug.hotplugSucceeded
            && hotplug.failurePhase?.isEmpty == false
            && hotplug.failureErrorMessage?.isEmpty == false
            && hotplug.mutationBeforeFailure != .unknown
            && record.blockIOAttribution == "wholeRunOnly"
            && record.rootfsBlockIOAttribution == "notMeasured"
    }

    private static func isWarmReusePreservedCleanup(_ record: Phase6BenchmarkIterationRecord) -> Bool {
        guard record.cleanupResult == "preserved-volume-for-warm-reuse"
            || record.cleanupResult == "preserved-project-runtime-for-warm-reuse",
            record.cleanupStateDirectoryExistsAfterCleanup,
            let lifecycleMode = record.environment?.lifecycleMode,
            let mode = BenchmarkLifecycleMode(rawValue: lifecycleMode) else {
            return false
        }
        switch mode {
        case .warmPreservedVolume, .persistentPodHotplug, .allWarmProjectRuntime:
            return true
        case .coldRuntime,
             .imageStoreSeededFreshRuntime,
             .rootfsCacheHitRuntime,
             .initfsCacheHitRuntime:
            return false
        }
    }

    private static func isCleanFinalCleanup(_ record: Phase6BenchmarkIterationRecord) -> Bool {
        record.cleanupResult == "clean" && !record.cleanupStateDirectoryExistsAfterCleanup
    }
}

private func blocking(_ code: String, _ message: String) -> Diagnostic {
    Diagnostic(severity: .blocking, code: code, message: message)
}

private func readStage8IterationRecords(_ url: URL) throws -> [Phase6BenchmarkIterationRecord] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    var records: [Phase6BenchmarkIterationRecord] = []
    for line in contents.split(separator: "\n") {
        let data = Data(line.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["recordType"] as? String == Phase6BenchmarkSchema.iterationRecordType else {
            continue
        }
        records.append(try decoder.decode(Phase6BenchmarkIterationRecord.self, from: data))
    }
    return records
}

private func readStage9BHotplugProbeRecords(_ url: URL) throws -> [Stage9BHotplugProbeRecord] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    var records: [Stage9BHotplugProbeRecord] = []
    for line in contents.split(separator: "\n") {
        let data = Data(line.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["recordType"] as? String == Stage9BHotplugProbeSchema.caseRecordType else {
            continue
        }
        records.append(try decoder.decode(Stage9BHotplugProbeRecord.self, from: data))
    }
    return records
}

private func readStage9DHotplugProviderProbeRecords(_ url: URL) throws -> [Stage9DHotplugProviderProbeRecord] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    var records: [Stage9DHotplugProviderProbeRecord] = []
    for line in contents.split(separator: "\n") {
        let data = Data(line.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["recordType"] as? String == Stage9DHotplugProviderProbeSchema.recordType else {
            continue
        }
        records.append(try decoder.decode(Stage9DHotplugProviderProbeRecord.self, from: data))
    }
    return records
}

private func readStage10ARootfsMaterializationProbeRecords(_ url: URL) throws -> [RootfsMaterializationProbeRecord] {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    var records: [RootfsMaterializationProbeRecord] = []
    for line in contents.split(separator: "\n") {
        let data = Data(line.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["recordType"] as? String == Stage10ARootfsMaterializationProbeSchema.recordType else {
            continue
        }
        records.append(try decoder.decode(RootfsMaterializationProbeRecord.self, from: data))
    }
    return records
}

private func p50<T: Comparable>(_ values: [T]) -> T? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}
