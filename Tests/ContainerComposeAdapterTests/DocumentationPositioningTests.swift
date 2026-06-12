// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest

final class DocumentationPositioningTests: XCTestCase {
    func testREADMEPositionsProjectBelowExistingContainerComposeWrappers() throws {
        let readme = try readText("README.md")

        XCTAssertTrue(readme.contains("not intended to duplicate existing Apple Container Compose wrappers"))
        XCTAssertTrue(readme.contains("Mcrich23/Container-Compose"))
        XCTAssertTrue(readme.contains("persistent LinuxPod project runtime"))
        XCTAssertTrue(readme.contains("Docker Compose files are the primary input"))
        XCTAssertTrue(readme.contains("Kubernetes is a future local-development input subset"))
        XCTAssertTrue(readme.contains("Microsoft WSL container is an optimization reference only"))
        XCTAssertTrue(readme.contains("does not claim host RAM savings"))
    }

    func testCompetitiveContextDocumentsContainerComposeAsReferenceOnly() throws {
        let doc = try readText("docs/competitive-context/container-compose.md")

        XCTAssertTrue(doc.contains("Mcrich23/Container-Compose"))
        XCTAssertTrue(doc.contains("not intended to duplicate"))
        XCTAssertTrue(doc.contains("external benchmark and compatibility reference"))
        XCTAssertTrue(doc.contains("not an implementation backend"))
        XCTAssertTrue(doc.contains("If this differentiation cannot be made real"))
    }

    func testWSLReferenceRejectsBackendTargetAndDockerdCopying() throws {
        let doc = try readText("docs/optimization-references/wsl-container.md")

        XCTAssertTrue(doc.contains("wslc.exe"))
        XCTAssertTrue(doc.contains("WSL container API"))
        XCTAssertTrue(doc.contains("not a backend target"))
        XCTAssertTrue(doc.contains("Do not add dockerd or containerd"))
        XCTAssertTrue(doc.contains("persistent session/storage/event/recovery"))
        XCTAssertTrue(doc.contains("ProjectSessionManager"))
        XCTAssertTrue(doc.contains("cca-agent"))
    }

    func testKubernetesDocsStayFutureInputSubsetNotFullKubernetes() throws {
        let doc = try readText("docs/kubernetes-input-subset.md")

        XCTAssertTrue(doc.contains("future input/frontend"))
        XCTAssertTrue(doc.contains("not a full Kubernetes distribution"))
        XCTAssertTrue(doc.contains("CRDs"))
        XCTAssertTrue(doc.contains("kubectl-compatible API server"))
        XCTAssertTrue(doc.contains("production Kubernetes conformance"))
    }

    func testStage4CloseoutAdvancesRoadmapAndDocumentsRuntimeEvidenceGap() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-12-stage-4-microbenchmark-closeout.md")

        XCTAssertTrue(activeIndex.contains("Stage 5 Backend-shaped Product Smoke"))
        XCTAssertFalse(activeIndex.contains("Stop before implementing or running a concrete Stage 4"))
        XCTAssertTrue(notesIndex.contains("2026-06-12-stage-4-microbenchmark-closeout.md"))

        XCTAssertTrue(note.contains("## Completion Criteria"))
        XCTAssertTrue(note.contains("rootfs"))
        XCTAssertTrue(note.contains("named volume"))
        XCTAssertTrue(note.contains("healthcheck"))
        XCTAssertTrue(note.contains("dry-run/evidence schema"))
        XCTAssertTrue(note.contains("cleanup proof"))
        XCTAssertTrue(note.contains("## Runtime Evidence Gap"))
        XCTAssertTrue(note.contains("No signed runtime microbenchmark was run"))
    }

    func testStage5DryRunEvidenceKeepsRuntimeSmokeAsNextTodo() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-12-stage-5-backend-smoke-evidence.md")

        XCTAssertTrue(activeIndex.contains("Stage 5 runtime smoke: request explicit runtime approval"))
        XCTAssertTrue(activeIndex.contains("20260612T093000Z-stage5-backend-smoke-dry-run.jsonl"))
        XCTAssertTrue(notesIndex.contains("2026-06-12-stage-5-backend-smoke-evidence.md"))

        XCTAssertTrue(note.contains("## Dry-run Evidence"))
        XCTAssertTrue(note.contains("Postgres"))
        XCTAssertTrue(note.contains("db-data"))
        XCTAssertTrue(note.contains("migrate"))
        XCTAssertTrue(note.contains("seed"))
        XCTAssertTrue(note.contains("API service"))
        XCTAssertTrue(note.contains("logs/status/run"))
        XCTAssertTrue(note.contains("service DNS/managed hosts"))
        XCTAssertTrue(note.contains("## Runtime Evidence Gap"))
        XCTAssertTrue(note.contains("No signed Stage 5 runtime smoke was run"))
    }

    private func readText(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
