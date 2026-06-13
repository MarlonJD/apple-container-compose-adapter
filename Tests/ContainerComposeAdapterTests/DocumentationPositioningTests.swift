// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import XCTest

final class DocumentationPositioningTests: XCTestCase {
    func testContainerizationRuntimeDependencyTracksLatestHotplugTag() throws {
        let package = try readText("Package.swift")
        let executor = try readText("Sources/ContainerComposeAdapterLinuxPod/ContainerizationLinuxPodRuntimeExecutor.swift")

        XCTAssertTrue(package.contains(#"exact: "0.33.4""#))
        XCTAssertTrue(executor.contains(#"containerizationVersion = "0.33.4""#))
        XCTAssertTrue(executor.contains(#"ghcr.io/apple/containerization/vminit:0.33.4"#))
    }

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

        XCTAssertTrue(activeIndex.contains("Stage 9A/9B signed runtime evidence covers `apple/containerization` `0.33.4`"))
        XCTAssertTrue(activeIndex.contains("keeps post-create hotplug unsupported"))
        XCTAssertTrue(activeIndex.contains("Productization is paused"))
        XCTAssertTrue(activeIndex.contains("run Stage 10C repeated warm benchmarks"))
        XCTAssertTrue(activeIndex.contains("unless a new hypothesis is explicitly approved"))
        XCTAssertTrue(activeIndex.contains("LinuxPod still misses the Docker/OrbStack viability gate"))
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

    func testStage9DHotplugProviderFeasibilityStaysDiagnosticOnly() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-13-stage-9d-hotplug-provider-feasibility.md")
        let issueDraft = try readText("docs/plans/notes/2026-06-13-apple-containerization-hotplug-provider-upstream-issue-draft.md")

        XCTAssertTrue(activeIndex.contains("Stage 9D"))
        XCTAssertTrue(activeIndex.contains("Stage 9D closed without product hotplug"))
        XCTAssertTrue(activeIndex.contains("unsupportedRootfsBlockHotplug"))
        XCTAssertTrue(notesIndex.contains("2026-06-13-stage-9d-hotplug-provider-feasibility.md"))
        XCTAssertTrue(notesIndex.contains("note-closed | [Stage 9D Hotplug Provider Feasibility]"))
        XCTAssertTrue(notesIndex.contains("2026-06-13-apple-containerization-hotplug-provider-upstream-issue-draft.md"))

        XCTAssertTrue(note.contains("**Status:** `note-closed`"))
        XCTAssertTrue(note.contains("Stage 9D exists because Stage 9B showed"))
        XCTAssertTrue(note.contains("0.33.4"))
        XCTAssertTrue(note.contains("hotplugProviderInstalled=false"))
        XCTAssertTrue(note.contains("PR #740 added interfaces"))
        XCTAssertTrue(note.contains("without forking"))
        XCTAssertTrue(note.contains("must not be treated as product behavior unless the second container actually starts"))
        XCTAssertTrue(note.contains("fast pod recreate + rootfs copy avoidance"))
        XCTAssertTrue(note.contains("provider.hotplugProviderInstalled=true"))
        XCTAssertTrue(note.contains("hotplug.postCreateAddContainerReachedProvider=true"))
        XCTAssertTrue(note.contains("unsupportedRootfsBlockHotplug"))
        XCTAssertTrue(note.contains("productHotplugAvailable=false"))
        XCTAssertTrue(note.contains("No fork decision"))
        XCTAssertTrue(note.contains("No host memory savings claim"))
        XCTAssertTrue(note.contains("No Docker/OrbStack viability claim"))
        XCTAssertFalse(note.contains("productHotplugAvailable=true"))
        XCTAssertFalse(note.contains("Docker/OrbStack gate passed"))
        XCTAssertFalse(note.contains("host memory savings achieved"))

        XCTAssertTrue(issueDraft.contains("Do not post this issue from Codex"))
        XCTAssertTrue(issueDraft.contains("0.33.4 active"))
        XCTAssertTrue(issueDraft.contains("vmConfigExtensionCount=0"))
        XCTAssertTrue(issueDraft.contains("hotplugProviderInstalled=false"))
        XCTAssertTrue(issueDraft.contains(#""hotplug not supported""#))
        XCTAssertTrue(issueDraft.contains("public extension/provider"))
        XCTAssertTrue(issueDraft.contains("block/ext4 rootfs hotplug"))
        XCTAssertTrue(issueDraft.contains("providerHotplugCalled=true"))
        XCTAssertTrue(issueDraft.contains("unsupportedRootfsBlockHotplug"))
    }

    func testStage10ARootfsMaterializationFeasibilityStaysDiagnosticOnly() throws {
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-13-stage-10a-rootfs-materialization-feasibility.md")

        XCTAssertTrue(activeIndex.contains("Stage 10A closed as positive diagnostic feasibility"))
        XCTAssertTrue(activeIndex.contains("Rootfs Materialization Feasibility"))
        XCTAssertTrue(activeIndex.contains("normal runtime copy behavior remains default"))
        XCTAssertTrue(notesIndex.contains("2026-06-13-stage-10a-rootfs-materialization-feasibility.md"))

        XCTAssertTrue(note.contains("Stage 10A follows Stage 9D"))
        XCTAssertTrue(note.contains("unsupportedRootfsBlockHotplug"))
        XCTAssertTrue(note.contains("fast pod recreate as the main product path"))
        XCTAssertTrue(note.contains("dominant controllable cost is still rootfs materialization"))
        XCTAssertTrue(note.contains("APFS clone/COW"))
        XCTAssertTrue(note.contains("clonefile"))
        XCTAssertTrue(note.contains("copyfileClone"))
        XCTAssertTrue(note.contains("normal runtime default remains the\nexisting copy behavior"))
        XCTAssertTrue(note.contains("Stage 10A is diagnostic feasibility, not product rewrite"))
        XCTAssertTrue(note.contains("Hotplug remains an upstream/research track"))
        XCTAssertTrue(note.contains("No host memory savings claim"))
        XCTAssertTrue(note.contains("No Docker/OrbStack viability claim"))
        XCTAssertTrue(note.contains("Do not claim Docker/OrbStack gate passed"))
        XCTAssertTrue(note.contains("redacted adapter-owned paths only"))
        XCTAssertTrue(note.contains("cleanup proof with zero adapter-owned leftovers"))
        XCTAssertFalse(note.contains("Stage 10A proves Docker/OrbStack viability"))
        XCTAssertFalse(note.contains("host memory savings achieved"))
        XCTAssertFalse(note.contains("productReady=true"))
    }

    func testResearchCheckpointPausesProductizationWithoutOverclaiming() throws {
        let readme = try readText("README.md")
        let activeIndex = try readText("docs/plans/index.md")
        let notesIndex = try readText("docs/plans/notes/index.md")
        let note = try readText("docs/plans/notes/2026-06-13-apple-native-runtime-research-checkpoint.md")

        XCTAssertTrue(readme.contains("## Research Status"))
        XCTAssertTrue(readme.contains("productization is paused"))
        XCTAssertTrue(readme.contains("`apple/containerization` package version `0.33.4`"))
        XCTAssertTrue(readme.contains("LinuxPod hotplug is not a product path"))
        XCTAssertTrue(readme.contains("`clonefile` is not the default"))
        XCTAssertTrue(readme.contains("productReady=false"))
        XCTAssertTrue(readme.contains("Stage 10B was attempted as a guarded final decision experiment"))
        XCTAssertTrue(readme.contains("before any valid Stage 10B JSONL comparison evidence was\nproduced"))
        XCTAssertTrue(readme.contains("Do not recommend Stage 10C repeated warm benchmarking"))
        XCTAssertTrue(readme.contains("no Docker/OrbStack parity"))
        XCTAssertTrue(readme.contains("host RAM, or energy savings claim is made"))

        XCTAssertTrue(activeIndex.contains("| paused | [Apple-native Orchestrator Roadmap]"))
        XCTAssertTrue(activeIndex.contains("Productization is paused"))
        XCTAssertTrue(activeIndex.contains("Do not continue hotplug implementation, make clonefile default, run Stage 10C"))
        XCTAssertTrue(activeIndex.contains("Apple-native Runtime Research Checkpoint"))
        XCTAssertTrue(activeIndex.contains("Stage 10B closed"))
        XCTAssertTrue(activeIndex.contains("stalled before valid JSONL evidence"))
        XCTAssertTrue(activeIndex.contains("host memory/energy savings remain unclaimed"))

        XCTAssertTrue(notesIndex.contains("note-closed | [Apple-native Runtime Research Checkpoint]"))
        XCTAssertTrue(notesIndex.contains("the guarded backend-shaped runtime comparison stalled in the fullCopy leg"))
        XCTAssertTrue(notesIndex.contains("Stage 10C is not recommended"))

        XCTAssertTrue(note.contains("Apple-native local-dev orchestrator"))
        XCTAssertTrue(note.contains("**Status:** `note-closed`"))
        XCTAssertTrue(note.contains("Existing tools such as `container-compose` primarily map Compose YAML"))
        XCTAssertTrue(note.contains("direct\n`apple/containerization` `LinuxPod` runtime primitives"))
        XCTAssertTrue(note.contains("Cold/fresh `LinuxPod` runtime remains slow"))
        XCTAssertTrue(note.contains("Image-store seeding improves"))
        XCTAssertTrue(note.contains("Rootfs cache alone is insufficient"))
        XCTAssertTrue(note.contains("Warm ext4 named volumes reduce block writes"))
        XCTAssertTrue(note.contains("Hotplug is not product-ready"))
        XCTAssertTrue(note.contains("public ext4/block rootfs hotplug does not complete"))
        XCTAssertTrue(note.contains("the second container does not start"))
        XCTAssertTrue(note.contains("`productReady=false`"))
        XCTAssertTrue(note.contains("Pause productization"))
        XCTAssertTrue(note.contains("Stage 10B was approved only as a guarded final decision experiment"))
        XCTAssertTrue(note.contains("It did not\nchange runtime defaults"))
        XCTAssertTrue(note.contains("`fullCopy` backend-shaped `LinuxPod` runtime baseline"))
        XCTAssertTrue(note.contains("`auto`/`clonefile` backend-shaped `LinuxPod` runtime candidate"))
        XCTAssertTrue(note.contains("explicit `notMeasured` host-port/load-window fields"))
        XCTAssertTrue(note.contains("stalled during the\n`fullCopy` `up` leg"))
        XCTAssertTrue(note.contains("comparison record was therefore not produced"))
        XCTAssertTrue(note.contains("no partial evidence file is being treated as proof"))
        XCTAssertTrue(note.contains("Docker/OrbStack gate pass cannot be\nrecorded unless it was directly measured"))
        XCTAssertTrue(note.contains("These required continuation conditions\nremain unproven"))
        XCTAssertTrue(note.contains("block I/O improves or the remaining block I/O is explained by measured data"))
        XCTAssertTrue(note.contains("no Docker/OrbStack gate or parity claim is made unless directly measured"))
        XCTAssertTrue(note.contains("do not recommend Stage\n10C repeated warm benchmarking"))
        XCTAssertTrue(note.contains("Stage 10B did not justify resuming that path"))
        XCTAssertTrue(note.contains("Product reliance on `LinuxPod` hotplug"))
        XCTAssertTrue(note.contains("Host RAM or energy savings claims without reliable measurements"))
        XCTAssertFalse(note.contains("productReady=true"))
        XCTAssertFalse(note.contains("Stage 10C repeated warm benchmark recommended"))
        XCTAssertFalse(note.contains("Docker/OrbStack gate passed"))
        XCTAssertFalse(note.contains("host memory savings achieved"))
        XCTAssertFalse(note.contains("host RAM savings achieved"))
    }

    private func readText(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
