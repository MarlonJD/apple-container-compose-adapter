# Evidence Index

This file explains the most important local files included in the research
package.

## Benchmark evidence

- `evidence/20260611T185918Z-combined-runtime-efficiency-report.md`
  - Combined Docker/OrbStack vs Apple `container` report.
  - Main baseline for simple-web, Postgres-only, and backend-shaped workloads.
- `evidence/20260611T185918Z-combined-runtime-efficiency-summary.json`
  - Machine-readable summary for the combined benchmark.
- `evidence/20260611T185918Z-combined-runtime-efficiency-raw.jsonl`
  - Combined raw iteration records.
- `evidence/20260611T181254Z-runtime-efficiency-raw.jsonl`
  - Docker/OrbStack raw benchmark source.
- `evidence/20260611T184900Z-runtime-efficiency-raw.jsonl`
  - Apple `container` raw benchmark source.

## LinuxPod evidence

- `plans/2026-06-12-linuxpod-compose-runtime-backend-plan.md`
  - Full LinuxPod backend runtime plan and phase history.
- `plans/2026-06-12-linuxpod-phase-6-benchmark-decision.md`
  - Final Phase 6 gate result and decision.
- `evidence/20260612T045331Z-phase6-warm-5.jsonl`
  - Five-iteration LinuxPod backend-shaped benchmark.
- `evidence/20260612T045149Z-phase6-smoke.jsonl`
  - One LinuxPod runtime smoke iteration.
- `evidence/20260612T045048Z-phase6-backend-shaped-dry-run.jsonl`
  - No-side-effect dry-run evidence for the Phase 6 backend-shaped plan.
- `plans/2026-06-12-linuxpod-phase-5-host-footprint-evidence.md`
  - Host memory attribution result: blocked.
- `evidence/20260612T043600-phase5-footprint-full-stack.jsonl`
  - Full-stack host-footprint run showing guest growth while host sources were
    not attributable.
- `plans/2026-06-11-linuxpod-base-overhead-spike-evidence.md`
  - Earlier LinuxPod base-overhead spike that motivated the shared-VM research
    direction.

## Upstream communication package

- `plans/2026-06-11-apple-upstream-benchmark-issue-package.md`
  - The focused upstream package for Apple `container` issue #1698 and the
    related performance benchmark discussion.

## Source code included

- `source/ContainerizationLinuxPodRuntimeExecutor.swift`
  - Concrete LinuxPod executor using `apple/containerization`.
- `source/LinuxPodBackend.swift`
  - Runtime backend action planning for `up`, `down`, `logs`, `status`, and
    `run`.
- `source/HostFootprint.swift`
  - Host footprint evidence schema and blocked-source handling.
- `source/Phase6Benchmark.swift`
  - Phase 6 benchmark data model.
- `source/SamplePlans.swift`
  - Public sample workloads used by the adapter.
- `source/ContainerComposeAdapterFootprintHarness/main.swift`
  - Phase 5 host-footprint harness.
- `source/ContainerComposeAdapterPhase6Benchmark/main.swift`
  - Phase 6 backend-shaped benchmark harness.

## Fixtures

- `fixtures/simple-web/compose.yaml`
- `fixtures/backend-shaped/compose.yaml`

These are public, minimal Compose-style workloads used to probe runtime
compatibility and performance. They are not private EMSI application data.
