# LinuxPod Phase 6 Benchmark Decision

**Date:** 2026-06-12
**Linked plan:** [LinuxPod Compose Runtime Backend Implementation Plan](../2026-06-12-linuxpod-compose-runtime-backend-plan.md)
**Decision:** `linuxpod-not-promising`

## Summary

Phase 6 proved that the backend-shaped public fixture can run end to end in one
LinuxPod, including DB, migrate, seed, API readiness, status, logs, and cleanup.
It did not pass the Docker/OrbStack Viability Gate.

The benchmark produced:

- Dry-run evidence:
  [`20260612T045048Z-phase6-backend-shaped-dry-run.jsonl`](../../evidence/linuxpod-compose-runtime/20260612T045048Z-phase6-backend-shaped-dry-run.jsonl).
- One runtime-approved smoke iteration:
  [`20260612T045149Z-phase6-smoke.jsonl`](../../evidence/linuxpod-phase6-benchmark/20260612T045149Z-phase6-smoke.jsonl).
- Five runtime-approved warm-image iterations:
  [`20260612T045331Z-phase6-warm-5.jsonl`](../../evidence/linuxpod-phase6-benchmark/20260612T045331Z-phase6-warm-5.jsonl).

The five-iteration run measured `5/5` successful iterations with failure count
`0`. Each iteration reported `cleanupStateDirectoryExistsAfterCleanup: false`,
and `.container-compose-adapter` was absent after the run.

Host physical memory remains `blocked` by the Phase 5 decision. The
`cgroupMemoryLimitBytes` field currently reports the LinuxPod API's effectively
unbounded sentinel value and is not used for the decision.

## Gate Result

Comparison baseline:
[`20260611T185918Z-combined-runtime-efficiency-report.md`](../../evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-report.md).

| Metric | LinuxPod Phase 6 p50 | Docker/OrbStack baseline | Gate | Result |
| --- | ---: | ---: | --- | --- |
| Backend guest cgroup current | `188.2MiB` | DB `67.33MiB` + API `19.07MiB` = `86.4MiB` | Within `50%` | Fail, `2.18x` Docker baseline |
| Host physical footprint | `blocked` | Not comparable | Reliable source and within `50%` | Blocked by Phase 5 |
| Startup/readiness | `64.83s` up duration | `12.859s` Docker Compose `start_to_wait` | Within `50%` | Fail, `5.04x` Docker baseline |
| Block read | `104.5MiB` | DB `3.09MiB` + API `1.77MiB` = `4.86MiB` | No worse than `2x` unless absolute delta is below `10MiB` | Fail, `21.5x` Docker baseline |
| Block write | `51.1MiB` | DB `55.50MiB` + API `0.00MiB` = `55.50MiB` | Same broad range | Pass |
| Failure count | `0/5` | Required `0/5` | No failures | Pass |
| Cleanup | No adapter-owned state after every iteration | Required clean state | No leftover project state | Pass |

## Interpretation

LinuxPod is functionally viable for this backend-shaped fixture, but it is not
promising as a Docker/OrbStack replacement path on the current implementation.
The replacement gate failed by a wide margin on startup/readiness, guest cgroup
memory, and block read volume. The clean failure count and cleanup behavior are
useful engineering proof, but they are not enough to justify Phase 7
optimization as a replacement effort.

Do not run `10` or `20+` Phase 6 iterations for publication-grade evidence.
Do not proceed to Phase 7 LinuxPod replacement optimization unless a new,
explicitly approved hypothesis changes the test, such as reusable warm
LinuxPod lifecycle, persistent rootfs cache strategy, or upstream
`apple/containerization` changes. Keep Docker/OrbStack as the recommended
backend runtime and treat LinuxPod as an optional research path.

## Verification

- `swift test` passed before adding the Phase 6 harness: `25` tests.
- A failing test was added first for the Phase 6 evidence summary model, then
  made green.
- `swift test` passed after adding the harness: `26` tests.
- Dry-run evidence was produced before runtime mutation.
- Runtime commands used the signed debug binary
  `.build/arm64-apple-macosx/debug/container-compose-phase6-benchmark`, not
  plain `swift run`.
- `scripts/sign-debug-runtime.sh` verified
  `com.apple.security.virtualization` on the benchmark binary.
- The Phase 6 smoke and five-iteration benchmark both wrote JSONL evidence and
  cleaned adapter-owned runtime state.
