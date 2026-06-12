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
        XCTAssertTrue(readme.contains("Kubernetes is a local-development input subset"))
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

    func testKubernetesDocsStayInputSubsetNotFullKubernetes() throws {
        let doc = try readText("docs/kubernetes-input-subset.md")

        XCTAssertTrue(doc.contains("an input/frontend feature"))
        XCTAssertTrue(doc.contains("not a full Kubernetes distribution"))
        XCTAssertTrue(doc.contains("CRDs"))
        XCTAssertTrue(doc.contains("kubectl-compatible API server"))
        XCTAssertTrue(doc.contains("production Kubernetes conformance"))
        XCTAssertTrue(doc.contains("cca.local/depends-on"))
        XCTAssertTrue(doc.contains("--k8s-file"))
    }

    func testStage4CloseoutAdvancesRoadmapAndDocumentsRuntimeEvidenceGap() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-12-stage-4-microbenchmark-closeout.md")

        XCTAssertTrue(activeIndex.contains("Stage 4 Microbenchmark Closeout"))
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

    func testStage5RuntimeSmokeStaysRecordedAfterStage6Closure() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-12-stage-5-backend-smoke-evidence.md")

        XCTAssertTrue(activeIndex.contains("Stage 5 is complete"))
        XCTAssertTrue(activeIndex.contains("Stage 6 cold/image-store-seeded evidence is closed"))
        XCTAssertTrue(activeIndex.contains("20260612T093000Z-stage5-backend-smoke-dry-run.jsonl"))
        XCTAssertTrue(activeIndex.contains("20260612T110105Z-stage5-backend-smoke-runtime-up.jsonl"))
        XCTAssertTrue(activeIndex.contains("20260612T110105Z-stage5-backend-smoke-runtime-down-cleanup.jsonl"))
        XCTAssertTrue(notesIndex.contains("2026-06-12-stage-5-backend-smoke-evidence.md"))
        XCTAssertTrue(notesIndex.contains("Stage 5 closed"))

        XCTAssertTrue(note.contains("**Status:** `note-closed`"))
        XCTAssertTrue(note.contains("## Dry-run Evidence"))
        XCTAssertTrue(note.contains("Postgres"))
        XCTAssertTrue(note.contains("db-data"))
        XCTAssertTrue(note.contains("migrate"))
        XCTAssertTrue(note.contains("seed"))
        XCTAssertTrue(note.contains("API service"))
        XCTAssertTrue(note.contains("logs/status/run"))
        XCTAssertTrue(note.contains("service DNS/managed hosts"))
        XCTAssertTrue(note.contains("## Runtime Smoke Evidence"))
        XCTAssertTrue(note.contains("exactly\none signed backend-shaped fixture runtime smoke"))
        XCTAssertTrue(note.contains("CREATE TABLE"))
        XCTAssertTrue(note.contains("INSERT 0 1"))
        XCTAssertTrue(note.contains("zero-leftover proof"))
        XCTAssertTrue(note.contains("does not justify replacement or performance claims"))
    }

    func testStage6ColdWarmBenchmarkDecisionClosesWarmGate() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-12-stage-6-cold-warm-benchmark-decision.md")

        XCTAssertTrue(activeIndex.contains("Stage 8B rootfs-cache + initfs-cache optimization code is complete"))
        XCTAssertTrue(activeIndex.contains("persistent project LinuxPod + rootfs/initfs/volume cache + service hotplug/reuse"))
        XCTAssertTrue(notesIndex.contains("note-closed | [Stage 6 Cold/Warm Comparative Benchmark Decision]"))
        XCTAssertTrue(notesIndex.contains("image-store-seeded fresh runtime `5/5` run"))

        XCTAssertTrue(note.contains("**Status:** `note-closed`"))
        XCTAssertTrue(note.contains("**Decision:** `stage6-image-store-only-warming-insufficient`"))
        XCTAssertTrue(note.contains("20260612T125100Z-stage6-warm-5-escalated-readiness.jsonl"))
        XCTAssertTrue(note.contains("measuredIterations=5"))
        XCTAssertTrue(note.contains("failureCount=0"))
        XCTAssertTrue(note.contains("image-store-seeded fresh runtime"))
        XCTAssertTrue(note.contains("image-store-only warming did not make LinuxPod Compose-level competitive"))
        XCTAssertTrue(note.contains("`linux/arm64`"))
        XCTAssertTrue(note.contains("Stage 6 solved Docker Hub rate-limit exposure for measurement"))
        XCTAssertTrue(note.contains("persistent project LinuxPod + rootfs/initfs/volume cache + service hotplug/reuse"))
        XCTAssertFalse(note.contains("persistent warm LinuxPod failed"))
        XCTAssertFalse(note.contains("before any runtime mutation"))
        XCTAssertFalse(note.contains("host RAM savings"))
    }

    private func readText(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
