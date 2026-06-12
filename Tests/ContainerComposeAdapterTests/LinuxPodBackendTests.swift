// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest
@testable import ContainerComposeAdapter

final class LinuxPodBackendTests: XCTestCase {
    func testDryRunUsesAdapterOwnedLinuxPodNamesAndState() throws {
        let backend = LinuxPodBackend(
            stateStore: LinuxPodStateStore(root: URL(fileURLWithPath: "/tmp/cca-test-state", isDirectory: true))
        )
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Smoke Test"))

        let result = try backend.renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        XCTAssertEqual(result.project, "cca-linuxpod-smoke-test")
        XCTAssertTrue(result.approvalRequired)
        XCTAssertTrue(result.actions.contains { $0.kind == .createProjectRuntime && $0.resourceName == "cca-linuxpod-smoke-test" })
        XCTAssertTrue(result.actions.contains { $0.kind == .prepareImageRootfs && $0.metadata["cache"] == "miss" })
        XCTAssertTrue(result.renderText().contains("SESSION_TOKEN=<redacted>"))
    }

    func testLinuxPodExecutionRequiresExplicitApproval() async throws {
        let backend = LinuxPodBackend()
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Needs Approval"))

        do {
            _ = try await backend.execute(
                command: .up,
                plan: plan,
                options: RuntimeOptions(),
                approval: RuntimeApproval()
            )
            XCTFail("Expected runtime mutation approval gate.")
        } catch let error as RuntimeBackendError {
            XCTAssertEqual(
                error,
                .runtimeMutationRequiresApproval(
                    "LinuxPod runtime mutation requires explicit current-task approval and token \(LinuxPodBackend.runtimeApprovalToken)."
                )
            )
        }
    }

    func testApprovedUpExecutesProjectLifecycleThroughRuntimeExecutor() async throws {
        let executor = RecordingLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(
            stateStore: LinuxPodStateStore(root: URL(fileURLWithPath: "/tmp/cca-test-state", isDirectory: true)),
            runtimeExecutor: executor
        )
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Phase3 Public Smoke"))

        let result = try await backend.execute(
            command: .up,
            plan: plan,
            options: RuntimeOptions(),
            approval: RuntimeApproval(
                approved: true,
                token: LinuxPodBackend.runtimeApprovalToken
            )
        )

        XCTAssertEqual(result.status, "executed")
        XCTAssertEqual(
            executor.events.map(\.kind),
            [
                .createProjectRuntime,
                .prepareImageRootfs,
                .createNamedVolume,
                .validateBindMount,
                .addContainer,
                .startContainer,
                .waitForReadiness
            ]
        )
        XCTAssertTrue(executor.events.allSatisfy { event in
            event.project == "cca-linuxpod-phase3-public-smoke"
        })
        XCTAssertEqual(executor.events.first?.resourceName, "cca-linuxpod-phase3-public-smoke")
        XCTAssertFalse(executor.events.contains { $0.description.contains("dry-run-token") })
    }

    func testApprovedDownOnlyDeletesNamedVolumesWhenRequested() async throws {
        let executor = RecordingLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Phase3 Cleanup"))

        _ = try await backend.execute(
            command: .down,
            plan: plan,
            options: RuntimeOptions(includeVolumes: false),
            approval: RuntimeApproval(
                approved: true,
                token: LinuxPodBackend.runtimeApprovalToken
            )
        )

        XCTAssertEqual(
            executor.events.map(\.kind),
            [.stopProjectRuntime, .deleteProjectRuntime]
        )

        executor.events.removeAll()

        _ = try await backend.execute(
            command: .down,
            plan: plan,
            options: RuntimeOptions(includeVolumes: true),
            approval: RuntimeApproval(
                approved: true,
                token: LinuxPodBackend.runtimeApprovalToken
            )
        )

        XCTAssertEqual(
            executor.events.map(\.kind),
            [.stopProjectRuntime, .deleteProjectRuntime, .cleanupNamedVolume]
        )
    }

    func testBackendShapedUpDryRunOrdersJobsAndPublishesServiceHosts() throws {
        let backend = LinuxPodBackend(
            stateStore: LinuxPodStateStore(root: URL(fileURLWithPath: "/tmp/cca-test-state", isDirectory: true))
        )
        let plan = SamplePlans.publicBackendShaped(project: ProjectName("Phase4 Backend"))

        let result = try backend.renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        let createRuntime = try XCTUnwrap(result.actions.first { $0.kind == .createProjectRuntime })
        XCTAssertEqual(createRuntime.metadata["hosts"], "127.0.0.1 db migrate seed api")

        let phase4Kinds: Set<PlannedActionKind> = [.addContainer, .startContainer, .runJob, .waitForReadiness]
        let serviceActions = result.actions
            .filter { phase4Kinds.contains($0.kind) }
            .map { "\($0.kind.rawValue):\($0.resourceName ?? "")" }
        // LinuxPod only accepts container registration before the pod VM is
        // created, so all addContainer actions precede the first start.
        XCTAssertEqual(
            serviceActions,
            [
                "addContainer:cca-linuxpod-phase4-backend-db",
                "addContainer:cca-linuxpod-phase4-backend-migrate",
                "addContainer:cca-linuxpod-phase4-backend-seed",
                "addContainer:cca-linuxpod-phase4-backend-api",
                "startContainer:cca-linuxpod-phase4-backend-db",
                "waitForReadiness:db",
                "runJob:cca-linuxpod-phase4-backend-migrate",
                "waitForReadiness:migrate",
                "runJob:cca-linuxpod-phase4-backend-seed",
                "waitForReadiness:seed",
                "startContainer:cca-linuxpod-phase4-backend-api",
                "waitForReadiness:api"
            ]
        )

        let migrate = try XCTUnwrap(result.actions.first { $0.resourceName == "cca-linuxpod-phase4-backend-migrate" && $0.kind == .addContainer })
        XCTAssertEqual(migrate.metadata["dependsOn"], "db:service_healthy")
        XCTAssertEqual(migrate.metadata["hosts"], "127.0.0.1 db migrate seed api")
        let db = try XCTUnwrap(result.actions.first { $0.resourceName == "cca-linuxpod-phase4-backend-db" && $0.kind == .addContainer })
        XCTAssertEqual(db.metadata["process"], "image-defaults")
        XCTAssertEqual(
            db.metadata["imageDefaults"],
            "Entrypoint+Cmd+Env+WorkingDir+DeclaredVolumes resolved during prepareImageRootfs"
        )
        XCTAssertEqual(db.metadata["ports"], "15432:5432/tcp")
        let dbReady = try XCTUnwrap(result.actions.first { $0.kind == .waitForReadiness && $0.resourceName == "db" })
        XCTAssertEqual(dbReady.metadata["condition"], "service_healthy")
        XCTAssertEqual(dbReady.metadata["command"], "pg_isready -U app -d app")
        XCTAssertEqual(dbReady.metadata["readinessWaitBudgetSeconds"], dbReady.metadata["timeoutSeconds"])
        XCTAssertTrue(dbReady.description.contains("readiness wait budget"))
    }

    func testBackendShapedLogsStatusAndRunDryRunsExposePhase4Subset() throws {
        let backend = LinuxPodBackend()
        let plan = SamplePlans.publicBackendShaped(project: ProjectName("Phase4 Backend"))

        let logs = try backend.renderDryRun(command: .logs, plan: plan, options: RuntimeOptions())
        XCTAssertFalse(logs.approvalRequired)
        XCTAssertEqual(logs.actions.filter { $0.kind == .collectLogs }.count, 4)

        let status = try backend.renderDryRun(command: .status, plan: plan, options: RuntimeOptions())
        XCTAssertFalse(status.approvalRequired)
        XCTAssertEqual(status.actions.map(\.kind), [PlannedActionKind.inspectStatus])
        XCTAssertEqual(status.actions.first?.metadata["services"], "db,migrate,seed,api")

        let run = try backend.renderDryRun(command: .run, plan: plan, options: RuntimeOptions())
        XCTAssertTrue(run.approvalRequired)
        XCTAssertEqual(
            run.actions.map { "\($0.kind.rawValue):\($0.resourceName ?? "")" },
            [
                "createProjectRuntime:cca-linuxpod-phase4-backend",
                "prepareImageRootfs:mirror.gcr.io/library/postgres:16-alpine",
                "createNamedVolume:db-data",
                "addContainer:cca-linuxpod-phase4-backend-db",
                "addContainer:cca-linuxpod-phase4-backend-migrate",
                "addContainer:cca-linuxpod-phase4-backend-seed",
                "startContainer:cca-linuxpod-phase4-backend-db",
                "waitForReadiness:db",
                "runJob:cca-linuxpod-phase4-backend-migrate",
                "waitForReadiness:migrate",
                "runJob:cca-linuxpod-phase4-backend-seed",
                "waitForReadiness:seed"
            ]
        )
        XCTAssertFalse(run.actions.contains { $0.resourceName == "cca-linuxpod-phase4-backend-api" })
    }

    func testApprovedBackendShapedRunExecutesDependencyAndJobLifecycle() async throws {
        let executor = RecordingLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        let plan = SamplePlans.publicBackendShaped(project: ProjectName("Phase4 Backend"))

        let result = try await backend.execute(
            command: .run,
            plan: plan,
            options: RuntimeOptions(),
            approval: RuntimeApproval(
                approved: true,
                token: LinuxPodBackend.runtimeApprovalToken
            )
        )

        XCTAssertEqual(
            executor.events.map { "\($0.kind.rawValue):\($0.resourceName ?? "")" },
            [
                "createProjectRuntime:cca-linuxpod-phase4-backend",
                "prepareImageRootfs:mirror.gcr.io/library/postgres:16-alpine",
                "createNamedVolume:db-data",
                "addContainer:cca-linuxpod-phase4-backend-db",
                "addContainer:cca-linuxpod-phase4-backend-migrate",
                "addContainer:cca-linuxpod-phase4-backend-seed",
                "startContainer:cca-linuxpod-phase4-backend-db",
                "waitForReadiness:db",
                "runJob:cca-linuxpod-phase4-backend-migrate",
                "waitForReadiness:migrate",
                "runJob:cca-linuxpod-phase4-backend-seed",
                "waitForReadiness:seed"
            ]
        )
        XCTAssertFalse(executor.events.contains { $0.resourceName == "cca-linuxpod-phase4-backend-api" })
        XCTAssertEqual(result.actionResults.filter { $0.kind == .runJob }.count, 2)
    }

    func testApprovedBackendShapedUpCarriesJobExitStatusAndLogCaptureEvidence() async throws {
        let executor = RecordingLinuxPodRuntimeExecutor()
        let backend = LinuxPodBackend(runtimeExecutor: executor)
        let plan = SamplePlans.publicBackendShaped(project: ProjectName("Phase4 Backend"))

        let result = try await backend.execute(
            command: .up,
            plan: plan,
            options: RuntimeOptions(),
            approval: RuntimeApproval(
                approved: true,
                token: LinuxPodBackend.runtimeApprovalToken
            )
        )

        let jobResults = result.actionResults.filter { $0.kind == .runJob }
        XCTAssertEqual(jobResults.map(\.resourceName), [
            "cca-linuxpod-phase4-backend-migrate",
            "cca-linuxpod-phase4-backend-seed"
        ])
        XCTAssertEqual(jobResults.map { $0.metadata["exitCode"] }, ["0", "0"])
        XCTAssertEqual(jobResults.map { $0.metadata["logs"] }, ["captured", "captured"])
    }

    func testNonPublicImageBlocksLinuxPodPath() throws {
        let plan = RuntimePlan(
            project: ProjectName("Private Image"),
            services: [
                ServicePlan(name: "db", image: "registry.internal.example/team/postgres:16")
            ]
        )

        let result = try LinuxPodBackend().renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        XCTAssertTrue(result.diagnostics.contains { $0.code == "non-public-image-reference" && $0.severity == .blocking })
    }

    func testDownVolumesRendersExplicitNamedVolumeCleanup() throws {
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Cleanup"))

        let result = try LinuxPodBackend().renderDryRun(
            command: .down,
            plan: plan,
            options: RuntimeOptions(includeVolumes: true)
        )

        XCTAssertTrue(result.actions.contains { $0.kind == .cleanupNamedVolume && $0.resourceName == "web-cache" && $0.mutatesRuntime })
    }

    func testDownWithoutVolumesPreservesNamedVolumeState() throws {
        let backend = LinuxPodBackend(
            stateStore: LinuxPodStateStore(root: URL(fileURLWithPath: "/tmp/cca-test-state", isDirectory: true))
        )
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Cleanup"))

        let result = try backend.renderDryRun(
            command: .down,
            plan: plan,
            options: RuntimeOptions(includeVolumes: false)
        )
        let stopRuntime = try XCTUnwrap(result.actions.first { $0.kind == .stopProjectRuntime })
        let deleteRuntime = try XCTUnwrap(result.actions.first { $0.kind == .deleteProjectRuntime })

        XCTAssertFalse(result.actions.contains { $0.kind == .cleanupNamedVolume })
        XCTAssertEqual(
            stopRuntime.metadata["state"],
            "/tmp/cca-test-state/cca-linuxpod-cleanup/runtime"
        )
        XCTAssertEqual(
            deleteRuntime.metadata["state"],
            "/tmp/cca-test-state/cca-linuxpod-cleanup/runtime"
        )
    }

    func testStateStoreRemovesEmptyProjectDirectoriesAfterVolumeCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cca-state-test-\(UUID().uuidString)", isDirectory: true)
        let stateStore = LinuxPodStateStore(root: root)
        let projectDirectory = stateStore.projectDirectory(for: ProjectName("Cleanup"))
        let volumesDirectory = projectDirectory.appendingPathComponent("volumes", isDirectory: true)
        try FileManager.default.createDirectory(at: volumesDirectory, withIntermediateDirectories: true)

        try stateStore.removeEmptyProjectDirectories(project: ProjectName("Cleanup"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testStateStoreRemovesEmptyProjectDirectoriesAfterRuntimeCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cca-state-test-\(UUID().uuidString)", isDirectory: true)
        let stateStore = LinuxPodStateStore(root: root)
        let projectDirectory = stateStore.projectDirectory(for: ProjectName("Cleanup"))
        let runtimeDirectory = stateStore.runtimeDirectory(for: ProjectName("Cleanup"))
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: runtimeDirectory)

        try stateStore.removeEmptyProjectDirectories(projectDirectory: projectDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try? FileManager.default.removeItem(at: root)
    }

    func testStateStoreRejectsNonAdapterOwnedProjectDirectoryCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cca-state-test-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-cca-owned-\(UUID().uuidString)", isDirectory: true)
        let stateStore = LinuxPodStateStore(root: root)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        XCTAssertThrowsError(try stateStore.removeEmptyProjectDirectories(projectDirectory: outside)) { error in
            XCTAssertEqual(
                "\(error)",
                "Refusing to remove non-adapter-owned project directory \(outside.path)."
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    func testDryRunEvidenceRecordsCacheAndNoRuntimeCleanupProof() throws {
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Evidence"))
        let result = try LinuxPodBackend().renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        let evidence = DryRunEvidenceRecord(timestamp: "2026-06-12T00:00:00.000Z", dryRun: result)

        XCTAssertEqual(evidence.status, "planned-dry-run-no-runtime-mutation")
        XCTAssertEqual(evidence.cleanupProof.runtimeMutation, "not-run")
        XCTAssertEqual(evidence.cleanupProof.ownedPrefix, "cca-linuxpod-")
        XCTAssertEqual(evidence.cacheEvents.first?.cache, "miss")
        XCTAssertEqual(evidence.cacheEvents.first?.image, "mirror.gcr.io/library/nginx:alpine")
    }

    func testRuntimeExecutionEvidenceRecordsExecutedCleanupProof() throws {
        let plan = SamplePlans.publicImageSmoke(project: ProjectName("Evidence Cleanup"))
        let dryRun = try LinuxPodBackend().renderDryRun(
            command: .down,
            plan: plan,
            options: RuntimeOptions(includeVolumes: true)
        )
        let result = ExecutionResult(
            backend: .linuxpod,
            command: .down,
            status: "executed"
        )

        let evidence = RuntimeExecutionEvidenceRecord(
            timestamp: "2026-06-12T00:00:00.000Z",
            dryRun: dryRun,
            execution: result
        )

        XCTAssertEqual(evidence.schemaVersion, "container-compose-adapter/linuxpod-runtime-execution/v1")
        XCTAssertEqual(evidence.recordType, "linuxpod-runtime-smoke")
        XCTAssertEqual(evidence.status, "executed")
        XCTAssertEqual(evidence.project, "cca-linuxpod-evidence-cleanup")
        XCTAssertEqual(evidence.cleanupProof.runtimeMutation, "executed")
        XCTAssertEqual(evidence.cleanupProof.globalCleanup, "not-run")
        XCTAssertEqual(evidence.cleanupProof.volumeCleanup, "executed")
        XCTAssertTrue(evidence.dryRun.actions.contains { $0.kind == .cleanupNamedVolume })
    }

    func testBindMountSafetyDiagnosticsCoverBroadAndCredentialPaths() throws {
        let plan = RuntimePlan(
            project: ProjectName("Mounts"),
            services: [
                ServicePlan(
                    name: "api",
                    image: "nginx:alpine",
                    mounts: [
                        MountPlan(kind: .bind, source: "/", target: "/host", readOnly: true),
                        MountPlan(kind: .bind, source: "~/.ssh", target: "/keys", readOnly: true)
                    ]
                )
            ]
        )

        let result = try LinuxPodBackend().renderDryRun(command: .up, plan: plan, options: RuntimeOptions())

        XCTAssertTrue(result.diagnostics.contains { $0.code == "broad-bind-mount" })
        XCTAssertTrue(result.diagnostics.contains { $0.code == "credential-bind-mount" })
    }
}

private final class RecordingLinuxPodRuntimeExecutor: LinuxPodRuntimeExecuting, @unchecked Sendable {
    var events: [LinuxPodRuntimeEvent] = []

    func execute(_ event: LinuxPodRuntimeEvent) async throws -> RuntimeActionResult {
        events.append(event)
        var metadata: [String: String] = [:]
        if event.kind == .runJob {
            metadata["exitCode"] = "0"
            metadata["logs"] = "captured"
        }
        return RuntimeActionResult(
            order: event.order,
            kind: event.kind,
            resourceName: event.resourceName,
            status: "executed",
            metadata: metadata
        )
    }
}
