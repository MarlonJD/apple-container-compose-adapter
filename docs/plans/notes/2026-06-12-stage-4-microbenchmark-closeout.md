# Stage 4 Microbenchmark Closeout

**Date:** 2026-06-12
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)
**Decision:** `stage-4-scaffold-complete-runtime-evidence-gap`

## Summary

Stage 4 is complete as a no-runtime-mutation scaffold. It defines the rootfs,
named volume, and healthcheck microbenchmark probes, records dry-run plan and
operation evidence as JSONL, validates future measurement JSONL shape, and
keeps cleanup proof explicit. It does not include signed runtime measurement
evidence.

## Completion Criteria

| Criterion | Status | Evidence |
| --- | --- | --- |
| rootfs microbenchmark scaffolding/tests | Met | `Stage4MicrobenchmarkPlanner` emits rootfs unpack, rootfs copy, and APFS clone probes for each fixture image with digest-keyed cache targets. Runtime contract tests cover probe coverage, operation scope, runner translation, measurement records, and validation failures. |
| named volume microbenchmark scaffolding/tests | Met | The Stage 4 planner emits fresh and warm named volume probes for `db-data`, with project-owned volume paths and lifecycle metadata checks for future measurement evidence. |
| healthcheck microbenchmark scaffolding/tests | Met | The planner emits healthcheck exec probes for `api` and `db`, keeps the exact readiness commands in the operation records, and requires healthcheck attempt metrics in measurement validation. |
| dry-run/evidence schema | Met | `Stage4MicrobenchmarkPlanRecord`, `Stage4MicrobenchmarkOperation`, and `Stage4MicrobenchmarkMeasurementRecord` use `container-compose-adapter/linuxpod-stage4-microbenchmark/v1`; plan and operation evidence is checked in under `docs/evidence/linuxpod-stage4-microbenchmarks/`. |
| cleanup proof | Met | Plan and operation records encode non-global mutation scope and cleanup expectations; measurement validation requires structured cleanup proof, preserved reusable cache state, no global cleanup, and zero stale files, processes, and ports. |
| runtime evidence gap documented | Met | This note records that runtime mutation approval was unavailable for Stage 4 measurement execution in this task. |

## Evidence

- Plan evidence:
  [`20260612T083000Z-stage4-microbenchmark-plan.jsonl`](../../evidence/linuxpod-stage4-microbenchmarks/20260612T083000Z-stage4-microbenchmark-plan.jsonl).
- Operation evidence:
  [`20260612T083000Z-stage4-microbenchmark-operations.jsonl`](../../evidence/linuxpod-stage4-microbenchmarks/20260612T083000Z-stage4-microbenchmark-operations.jsonl).
- The no-runtime command rejects runtime approval tokens and treats
  `--measurement-evidence-jsonl` as validation-only.
- Host physical memory remains `blocked` by the Phase 5 host-footprint
  decision and must not be used for Stage 4 claims.

## Runtime Evidence Gap

No signed runtime microbenchmark was run in this task. The current task did not
provide explicit approval to mutate runtime, cache, or project state for Stage 4
measurements, so the runtime evidence gap is intentionally carried forward.

Future Stage 4 measurement evidence must use the approval-gated executor path,
write measurement JSONL for every planned probe, include initfs/kernel/vminit
runtime context, guest cgroup metrics, timing, block I/O, cache lifecycle
metadata, and structured cleanup proof, then pass
`Stage4MicrobenchmarkEvidenceValidator`.

## Next Boundary

The active roadmap can advance to Stage 5 Backend-shaped Product Smoke. Stage 5
must start with fixture-derived dry-run evidence for Postgres, named volume,
migrate job, seed job, API, service readiness, logs/status, and cleanup. Runtime
execution remains separate approval-gated work after dry-run review.

## Verification

- Focused Stage 4 runtime-contract tests cover plan coverage, operation
  evidence, measurement schema, validator failure modes, approved runner
  injection, LinuxPod operation translation, file-backed validation, and
  no-runtime CLI behavior.
- Full verification target: `swift test`, focused Stage 4 tests,
  `swift run container-compose-stage4-microbenchmarks ... --validate-evidence`,
  and `git diff --check`.
