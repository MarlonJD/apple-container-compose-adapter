# LinuxPod Phase 5 Host Footprint Evidence

**Date:** 2026-06-12
**Linked plan:** [LinuxPod Compose Runtime Backend Implementation Plan](../2026-06-12-linuxpod-compose-runtime-backend-plan.md)
**Linked design:** [LinuxPod Phase 5 Host Footprint Design](2026-06-12-linuxpod-phase-5-host-footprint-design.md)
**Decision:** `no-reliable-per-process-host-source`
**Runtime mutation:** Approved measurement scenarios executed; cleanup verified per run.

## Decision

No candidate per-process host-side memory source tracks LinuxPod guest memory
on this host (`Mac14,7` Apple M2, Darwin 25.5.0). In the scale test the guest
cgroup grew by `504 MiB` while `task_info` phys footprint, the `footprint`
tool, `vmmap -summary`, and `ps` RSS all stayed flat (deltas of about `0`),
so all four were recorded `rejected-not-scaling` under the design criteria.
`vm_stat` deltas remain `blocked` for attribution because they are
system-wide. Virtualization.framework guest memory is evidently not charged
to the hosting process's per-process ledgers on this configuration.

Consequences:

- Project documentation must continue to avoid claiming lower host memory
  overhead than Docker/OrbStack; no reliable per-process proof exists.
- Docker and OrbStack also run their VMs on Virtualization.framework, so
  per-process host memory comparisons are equally blind for every runtime on
  macOS; this is a methodology gap, not a LinuxPod-specific defect.
- Phase 6 benchmarks must rely on guest cgroup metrics, block I/O, CPU, and
  timing — all proven samplable — and must label host physical memory
  comparison as `blocked` unless a controlled system-wide protocol (quiesced
  host, `vm_stat`/memory-pressure deltas across runtimes) is designed and
  approved separately.

## Harness

`container-compose-footprint-harness` (new executable target) drives the
LinuxPod backend in one signed process per scenario: `up` for the scenario
plan, in-process sampling of guest statistics (`pod.statistics`) and the five
host sources, optional bulk load, then `down --volumes` cleanup. The binary
is signed by `scripts/sign-debug-runtime.sh <path>` and all runs executed
escalated outside the sandboxed shell with the runtime approval token. The
executor gained three harness methods: `ensurePodCreated` (idle-pod VM),
`guestStatistics`, and `execInService` (bulk load). Verdict logic lives in
`HostFootprintCriteria` with contract-test coverage.

## Commands

```bash
swift build && swift test
scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-footprint-harness
.build/arm64-apple-macosx/debug/container-compose-footprint-harness --scenario idle-pod --samples 3 --evidence-jsonl docs/evidence/linuxpod-host-footprint/20260612T043100-phase5-footprint-idle-pod.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
.build/arm64-apple-macosx/debug/container-compose-footprint-harness --scenario db-only --samples 3 --evidence-jsonl docs/evidence/linuxpod-host-footprint/20260612T043300-phase5-footprint-db-only.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
.build/arm64-apple-macosx/debug/container-compose-footprint-harness --scenario full-stack --samples 3 --evidence-jsonl docs/evidence/linuxpod-host-footprint/20260612T043600-phase5-footprint-full-stack.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
.build/arm64-apple-macosx/debug/container-compose-footprint-harness --scenario scale-test --samples 3 --load-rows 600000 --evidence-jsonl docs/evidence/linuxpod-host-footprint/20260612T043900-phase5-footprint-scale-test.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
```

## Evidence

- Dry probes (no VM): [20260612T042400-phase5-host-source-dry-probes](../../evidence/linuxpod-host-footprint/20260612T042400-phase5-host-source-dry-probes.jsonl)
- Idle pod: [20260612T043100-phase5-footprint-idle-pod](../../evidence/linuxpod-host-footprint/20260612T043100-phase5-footprint-idle-pod.jsonl)
- DB only: [20260612T043300-phase5-footprint-db-only](../../evidence/linuxpod-host-footprint/20260612T043300-phase5-footprint-db-only.jsonl)
- Full stack: [20260612T043600-phase5-footprint-full-stack](../../evidence/linuxpod-host-footprint/20260612T043600-phase5-footprint-full-stack.jsonl)
- Scale test with per-source decisions: [20260612T043900-phase5-footprint-scale-test](../../evidence/linuxpod-host-footprint/20260612T043900-phase5-footprint-scale-test.jsonl)

## Results

| Scenario | Guest cgroup | task_info phys | footprint tool | vmmap | ps RSS |
| --- | --- | --- | --- | --- | --- |
| idle-pod | 0 (no containers) | ~23 MiB | ~22 MiB | ~23 MiB | ~53 MiB |
| db-only | ~133 MiB | ~43 MiB | ~43 MiB | ~42 MiB | ~72 MiB |
| full-stack | ~188 MiB | ~71 MiB | ~71 MiB | ~71 MiB | ~97 MiB |
| scale-test before | ~133 MiB | ~42 MiB | ~43 MiB | ~42 MiB | ~72 MiB |
| scale-test after | ~637 MiB | ~42 MiB | ~43 MiB | ~42 MiB | ~72 MiB |

Decisions from the scale test (`guestDeltaBytes` ~529 MB):

- `task-info-phys-footprint`: `rejected-not-scaling`
- `footprint-tool`: `rejected-not-scaling`
- `vmmap-summary`: `rejected-not-scaling`
- `ps-rss-tree`: `rejected-not-scaling` (re-confirms the spike rejection)
- `vm-stat-delta`: `blocked` (system-wide attribution)

Observations:

- Per-process ledgers do grow modestly with workload (idle ~23 MiB ->
  db-only ~43 MiB -> full-stack ~71 MiB), so they capture some VM-related
  host cost, but they do not track guest page growth and therefore cannot
  bound host physical memory for a loaded workload.
- The dry probes confirmed every external tool works without sudo on
  same-user processes, both sandboxed and unsandboxed; tool availability was
  not the limiting factor — ledger attribution was.

## Cleanup

Each scenario run executed `down --volumes` in-process (best-effort cleanup
also guards the failure path), wrote a cleanup record with
`stateDirectoryExistsAfterCleanup=false`, and an external check after the
final run found no `.container-compose-adapter` directory and no
`container-compose-adapter`, `container-compose-footprint-harness`, `vmexec`,
or `vminit` processes. No private EMSI workload, registry login, prune,
global cleanup, credential change, Keychain change, host DNS mutation,
branch operation, or parent monorepo pointer update was performed.

## Verification

- `swift build` and `swift test` (`25` tests) passed after the harness,
  executor methods, and verdict logic were added.
- `jq -e` validated all five evidence JSONL files; the scale-test file holds
  `6` samples, `5` decisions, and `1` cleanup record.
- `git diff --check` and trailing-whitespace scans passed on changed files.
