// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest
@testable import ContainerComposeAdapter

final class Stage5BackendSmokeTests: XCTestCase {
    func testStage5BackendSmokeEvidenceIsFixtureDerivedAndCoversDryRunSurfaces() throws {
        let record = try Stage5BackendSmokeHarness(
            stateStore: LinuxPodStateStore(root: URL(fileURLWithPath: "/tmp/cca-stage5-test-state", isDirectory: true))
        ).buildDryRunEvidence(
            composeFile: fixtureURL("backend-shaped/compose.yaml"),
            projectName: "backend-shaped",
            timestamp: "2026-06-12T09:30:00.000Z"
        )

        XCTAssertEqual(record.schemaVersion, Stage5BackendSmokeSchema.version)
        XCTAssertEqual(record.recordType, Stage5BackendSmokeSchema.dryRunRecordType)
        XCTAssertEqual(record.status, "planned-dry-run-no-runtime-mutation")
        XCTAssertEqual(record.runtimeEvidenceStatus, "not-run-runtime-approval-unavailable")
        XCTAssertTrue(record.sourceFiles.first?.hasSuffix("docs/evidence/fixtures/backend-shaped/compose.yaml") ?? false)
        XCTAssertEqual(record.projectID, "backend-shaped")
        XCTAssertEqual(record.runtimeResourceName, "cca-linuxpod-backend-shaped")
        XCTAssertEqual(
            record.coveredCapabilities,
            [
                "postgres-service",
                "db-data-named-volume",
                "migrate-job",
                "seed-job",
                "api-service",
                "service-readiness-healthchecks",
                "logs-surface",
                "status-surface",
                "run-surface",
                "deterministic-host-port",
                "service-dns-managed-hosts",
                "cleanup-proof"
            ]
        )
        XCTAssertEqual(record.dryRuns.map(\.command), [.up, .logs, .status, .run, .down])

        let up = try XCTUnwrap(record.dryRuns.first { $0.command == .up })
        XCTAssertTrue(up.approvalRequired)
        XCTAssertEqual(up.dryRun.actions.first { $0.kind == .createProjectRuntime }?.metadata["hosts"], "127.0.0.1 db migrate seed api")
        XCTAssertEqual(
            up.dryRun.actions
                .filter { [.addContainer, .startContainer, .runJob, .waitForReadiness].contains($0.kind) }
                .map { "\($0.kind.rawValue):\($0.resourceName ?? "")" },
            [
                "addContainer:cca-linuxpod-backend-shaped-db",
                "addContainer:cca-linuxpod-backend-shaped-migrate",
                "addContainer:cca-linuxpod-backend-shaped-seed",
                "addContainer:cca-linuxpod-backend-shaped-api",
                "startContainer:cca-linuxpod-backend-shaped-db",
                "waitForReadiness:db",
                "runJob:cca-linuxpod-backend-shaped-migrate",
                "waitForReadiness:migrate",
                "runJob:cca-linuxpod-backend-shaped-seed",
                "waitForReadiness:seed",
                "startContainer:cca-linuxpod-backend-shaped-api",
                "waitForReadiness:api"
            ]
        )
        let db = try XCTUnwrap(up.dryRun.actions.first {
            $0.kind == .addContainer && $0.resourceName == "cca-linuxpod-backend-shaped-db"
        })
        XCTAssertEqual(db.metadata["image"], "docker.io/library/postgres:16-alpine")
        XCTAssertEqual(db.metadata["ports"], "15432:5432/tcp")
        XCTAssertEqual(db.metadata["process"], "image-defaults")
        XCTAssertEqual(db.metadata["environment"], "POSTGRES_DB=app,POSTGRES_PASSWORD=<redacted>,POSTGRES_USER=app")
        let api = try XCTUnwrap(up.dryRun.actions.first {
            $0.kind == .addContainer && $0.resourceName == "cca-linuxpod-backend-shaped-api"
        })
        XCTAssertEqual(api.metadata["ports"], "18081:8080/tcp")
        XCTAssertEqual(api.metadata["dependsOn"], "db:service_healthy,seed:service_completed_successfully")
        XCTAssertFalse(up.dryRun.renderText().contains("dev_password"))

        let logs = try XCTUnwrap(record.dryRuns.first { $0.command == .logs })
        XCTAssertFalse(logs.approvalRequired)
        XCTAssertEqual(logs.dryRun.actions.filter { $0.kind == .collectLogs }.count, 4)

        let status = try XCTUnwrap(record.dryRuns.first { $0.command == .status })
        XCTAssertFalse(status.approvalRequired)
        XCTAssertEqual(status.dryRun.actions.first?.metadata["services"], "db,migrate,seed,api")

        let run = try XCTUnwrap(record.dryRuns.first { $0.command == .run })
        XCTAssertTrue(run.approvalRequired)
        XCTAssertFalse(run.dryRun.actions.contains { $0.resourceName == "cca-linuxpod-backend-shaped-api" })
        XCTAssertTrue(run.dryRun.actions.contains { $0.kind == .runJob && $0.resourceName == "cca-linuxpod-backend-shaped-migrate" })
        XCTAssertTrue(run.dryRun.actions.contains { $0.kind == .runJob && $0.resourceName == "cca-linuxpod-backend-shaped-seed" })

        let cleanup = try XCTUnwrap(record.dryRuns.first { $0.command == .down })
        XCTAssertTrue(cleanup.approvalRequired)
        XCTAssertEqual(cleanup.cleanupProof.runtimeMutation, "not-run")
        XCTAssertEqual(cleanup.cleanupProof.runtimeCleanup, "planned-only")
        XCTAssertEqual(cleanup.cleanupProof.volumeCleanup, "planned-only")
        XCTAssertEqual(cleanup.cleanupProof.portCleanup, "planned-release")
        XCTAssertTrue(cleanup.dryRun.actions.contains { $0.kind == .cleanupNamedVolume && $0.resourceName == "db-data" })

        XCTAssertEqual(Stage5BackendSmokeEvidenceValidator().validate(record), [])
    }

    func testStage5BackendSmokeCommandWritesAndValidatesDryRunEvidenceOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cca-stage5-command-\(UUID().uuidString)", isDirectory: true)
        let evidenceURL = root.appendingPathComponent("stage5.jsonl")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let result = try Stage5BackendSmokeCommandRunner().run(
            options: Stage5BackendSmokeCommandOptions(
                composeFile: .init(fixtureURL("backend-shaped/compose.yaml").path),
                projectName: "backend-shaped",
                timestamp: "2026-06-12T09:30:00.000Z",
                evidenceJSONL: .init(evidenceURL.path),
                validateEvidence: true,
                storeRoot: .init(root.appendingPathComponent("state", isDirectory: true).path)
            )
        )

        XCTAssertEqual(result.record.dryRuns.map(\.command), [.up, .logs, .status, .run, .down])
        XCTAssertEqual(result.validationDiagnostics, [])

        let lines = try String(contentsOf: evidenceURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines.count, 1)
        let decoded = try JSONDecoder().decode(Stage5BackendSmokeEvidenceRecord.self, from: Data(lines[0].utf8))
        XCTAssertEqual(decoded, result.record)
    }

    func testStage5BackendSmokeCommandRejectsRuntimeApprovalTokens() {
        XCTAssertThrowsError(
            try Stage5BackendSmokeCommandOptions.parse([
                "--compose-file", "docs/evidence/fixtures/backend-shaped/compose.yaml",
                "--project-name", "backend-shaped",
                "--evidence-jsonl", "/tmp/stage5.jsonl",
                "--approval-token", LinuxPodBackend.runtimeApprovalToken
            ])
        ) { error in
            XCTAssertEqual(error as? Stage5BackendSmokeCommandError, .runtimeApprovalNotAccepted)
        }
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/evidence/fixtures")
            .appendingPathComponent(name)
    }
}
