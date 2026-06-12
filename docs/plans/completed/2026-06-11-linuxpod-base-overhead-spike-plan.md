# LinuxPod Base Overhead Spike Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-06-11
**Owner subtree:** `tools/apple-container-compose-adapter`
**Goal:** Determine quickly whether `apple/containerization` `LinuxPod` can reduce the Apple runtime memory overhead observed in DB/backend benchmarks before building a shared-runtime Compose backend.
**Architecture:** Build a disposable SwiftPM spike that uses the official `containerization` package directly, outside the public `container` CLI, and measures idle pod, Postgres-only pod, and Postgres-plus-API pod memory/I/O. The first decision gate is a fast smoke measurement, not a long benchmark suite. Keep the spike separate from the main adapter implementation and treat it as decision evidence, not product code.
**Tech stack:** Swift Package Manager, `apple/containerization`, public `postgres:16-alpine` and lightweight API fixtures, existing Python benchmark summarization patterns, Markdown evidence under `docs/evidence/` and durable notes under `docs/plans/notes/`.

---

## Objective

Answer one specific question with the shortest useful measured evidence:

> If Apple `container` CLI per-container VM overhead is the reason Postgres reports about `187-188MiB` cgroup/runtime memory, does a lower-level `containerization` `LinuxPod` shared-VM path reduce the base overhead enough to justify a future shared-runtime Compose backend?

The spike must produce enough evidence to classify LinuxPod as one of:

- `promising`: lower base/marginal memory enough to justify a separate backend plan;
- `not-promising`: same or worse memory/I/O than the public Apple `container` CLI path;
- `blocked`: cannot be measured safely or reproducibly in the local environment;
- `needs-upstream`: API/runtime behavior blocks a fair measurement and should be taken upstream.

The default target is one valid smoke measurement per scenario. Repeated measurements
and p50/p95/p99 summaries are optional follow-up work only when the first result is
ambiguous, unexpectedly noisy, or promising enough that publication-grade evidence is
worth the extra runtime.

## Scope

This plan covers only a small proof-of-measurement spike:

- Inspect official `containerization` `LinuxPod` API and examples already downloaded or fetched from upstream.
- Create an isolated experiment under `experiments/linuxpod-base-overhead/`.
- Build a small Swift runner capable of:
  - creating an idle LinuxPod with one minimal process;
  - creating a Postgres-only LinuxPod;
  - creating a Postgres-plus-API LinuxPod;
  - collecting process RSS, cgroup memory, data footprint, block I/O, startup/readiness, and cleanup timings where the API exposes enough information.
- Reuse existing Docker/OrbStack and Apple `container` CLI benchmark evidence as comparison baselines.
- Prefer a fast first-pass comparison over a long benchmark run. One valid idle pod,
  Postgres-only, and Postgres-plus-API measurement is enough to reject or continue
  the idea when the memory/I/O gap is large.
- Run real LinuxPod runtime commands only after explicit user approval.
- Write a decision report and update `docs/plans/index.md` to the next concrete todo.

## Out Of Scope

- Building a production shared-runtime backend.
- Parsing Docker Compose YAML.
- Implementing service-name DNS beyond the smallest probe needed for Postgres-plus-API.
- Replacing the public Apple `container` CLI path in the main implementation plan.
- Forking `apple/container` or `apple/containerization`.
- Updating the parent EMSI monorepo or submodule pointers.
- Committing or pushing without explicit user approval.
- Running private EMSI workloads, registry login, image prune, global cleanup, or destructive host changes.

## Assumptions And Open Questions

- `containerization` `LinuxPod` is the only currently identified Apple lower-level API that may run multiple container root filesystems/processes in one pod VM.
- The public `container` CLI does not expose `LinuxPod` as a Compose/pod command.
- The local Apple `container` CLI benchmark showed Postgres process RSS around `26.6MiB` but Apple runtime/cgroup memory around `187-188MiB`.
- A fair LinuxPod spike needs at least idle pod and Postgres-only pod measurements. Postgres-plus-API is needed to estimate marginal cost of adding a second service.
- It is not yet known whether `containerization` exposes enough stable public API for image pull/unpack, pod stats, process exec, port publishing, and cleanup without reusing internal `container` code.
- It is not yet known whether the local environment has all entitlements, helper tools, and runtime services needed for direct `containerization` LinuxPod use.

## Dependencies And Ownership Boundaries

- Primary source references:
  - `apple/containerization` `Sources/Containerization/LinuxPod.swift`
  - `apple/containerization` `Sources/Integration/PodTests.swift`
  - `apple/containerization` examples such as `examples/ctr-example`
  - Existing note: [Pilot Phase 4 Shared Runtime Feasibility](notes/2026-06-11-pilot-phase-4-shared-runtime-feasibility.md)
  - Existing note: [Runtime Efficiency Benchmark Evidence](notes/2026-06-11-runtime-efficiency-benchmark-evidence.md)
- This repository owns only the spike code, benchmark harness, and evidence docs.
- Apple upstream owns `containerization` API behavior, VM/runtime memory behavior, and lower-level storage/network implementation.
- Docker/OrbStack remains the compatibility reference for measured comparison, not a target to modify.

## Affected Files

Expected new files:

- `experiments/linuxpod-base-overhead/Package.swift`
- `experiments/linuxpod-base-overhead/Sources/LinuxPodBaseOverheadSpike/main.swift`
- `experiments/linuxpod-base-overhead/README.md`
- `scripts/summarize_linuxpod_base_overhead.py`
- `docs/evidence/linuxpod-base-overhead/<timestamp>-linuxpod-base-overhead-raw.jsonl`
- `docs/evidence/linuxpod-base-overhead/<timestamp>-linuxpod-base-overhead-summary.json`
- `docs/evidence/linuxpod-base-overhead/<timestamp>-linuxpod-base-overhead-report.md`
- `docs/plans/notes/2026-06-11-linuxpod-base-overhead-spike-evidence.md`

Expected modified files:

- `docs/plans/index.md`
- `docs/plans/notes/index.md`
- optionally `docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md` if the decision changes the main runtime strategy.

## Phases

### Phase 0: No-Side-Effect API Feasibility

- [ ] Read `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/plans/index.md`, this plan, [Pilot Phase 4 Shared Runtime Feasibility](notes/2026-06-11-pilot-phase-4-shared-runtime-feasibility.md), and [Runtime Efficiency Benchmark Evidence](notes/2026-06-11-runtime-efficiency-benchmark-evidence.md).
- [ ] Inspect `apple/containerization` `LinuxPod.swift`, `PodTests.swift`, and examples without running runtime-mutating commands.
- [ ] Record whether direct `LinuxPod` use appears possible through public APIs, local path dependency, or SwiftPM remote dependency.
- [ ] If direct use is blocked before runtime, stop and write a `blocked` evidence note. Do not mutate runtime state.
- [ ] Run `git diff --check`.
- [ ] Update `docs/plans/index.md` so this plan's next todo is the first unresolved concrete step.

### Phase 1: Build A Disposable Spike Runner

- [ ] Create `experiments/linuxpod-base-overhead/` as an isolated SwiftPM package.
- [ ] Pin or record the exact `apple/containerization` source used through `Package.resolved` or a local-path note in the README.
- [ ] Implement a CLI with these modes:
  - `--mode idle-pod`
  - `--mode postgres-only`
  - `--mode postgres-api`
  - `--iterations <n>`
  - `--dry-run`
  - `--output <path>`
- [ ] Ensure `--dry-run` prints planned actions without creating pods, rootfs, networks, volumes, or runtime state.
- [ ] Add redaction for passwords and generated credentials.
- [ ] Run `swift build` for compile verification only.
- [ ] Run `swift run ... --dry-run` for each mode.
- [ ] Run `git diff --check`.
- [ ] Update `docs/plans/index.md` to the next concrete todo.

### Phase 2: Measurement Design And Safety Gate

- [ ] Define the JSONL evidence schema before running runtime commands.
- [ ] Capture these fields per iteration:
  - scenario and runtime backend;
  - source version of `containerization`;
  - timing fields for setup, create, readiness, load, stop, delete;
  - process RSS and high-water RSS where available;
  - pod/container cgroup memory current, peak, and limit where available;
  - host-side process memory if a reliable runtime process can be identified;
  - DB data footprint;
  - block read/write;
  - load completed work and errors;
  - cleanup result.
- [ ] Define statuses: `measured`, `measured-with-limitations`, `skipped-runtime-unavailable`, `blocked-api`, `blocked-runtime`, `failed-cleanup`.
- [ ] Ask for explicit approval before any command that creates, starts, stops, or deletes LinuxPod/runtime resources.
- [ ] Run `git diff --check`.
- [ ] Update `docs/plans/index.md` to the next concrete todo.

### Phase 3: Runtime Smoke And Calibration

Requires explicit user approval before runtime mutation.

- [ ] Run one `idle-pod` smoke iteration.
- [ ] Verify cleanup leaves no spike-owned runtime state.
- [ ] Run one `postgres-only` smoke iteration.
- [ ] Verify Postgres readiness and cleanup.
- [ ] Run one `postgres-api` smoke iteration.
- [ ] Verify API can reach Postgres inside the pod and cleanup succeeds.
- [ ] If any smoke fails, record the failed command, stderr/stdout, cleanup status, and blocker classification.
- [ ] Run `git diff --check`.
- [ ] Update `docs/plans/index.md` to the next concrete todo.

### Phase 4: Optional Targeted Repeat Run

Requires explicit user approval before runtime mutation.

- [ ] Decide whether repeated measurement is needed based on Phase 3:
  - skip if the first valid results are clearly worse than Docker/OrbStack and similar to Apple CLI overhead;
  - run 3 focused repeats for a scenario if the result is close to the decision threshold or unexpectedly noisy;
  - run 10+ iterations and summarize p50/p95/p99 only if LinuxPod looks promising enough to justify publication-grade benchmark evidence.
- [ ] If repeated measurement is skipped, record the reason in the decision report.
- [ ] If repeated measurement runs, summarize the selected iteration count, median or p50, min, max, and failure counts. Include p95/p99 only when there are enough iterations for those percentiles to be meaningful.
- [ ] Compute:
  - idle pod base memory;
  - Postgres-only total memory;
  - Postgres process RSS;
  - Postgres-plus-API total memory;
  - marginal API cost;
  - DB block read/write;
  - DB data footprint.
- [ ] Compare against existing evidence from `20260611T185918Z-combined-runtime-efficiency-report.md`.
- [ ] Run `git diff --check`.
- [ ] Update `docs/plans/index.md` to the next concrete todo.

### Phase 5: Decision Report

- [ ] Write `docs/plans/notes/2026-06-11-linuxpod-base-overhead-spike-evidence.md`.
- [ ] Update `docs/plans/notes/index.md`.
- [ ] If LinuxPod is `promising`, update the main implementation plan to keep the CLI backend as Phase 0 path and add a separate future LinuxPod backend plan as a prerequisite before backend replacement claims.
- [ ] If LinuxPod is `not-promising`, update the main implementation plan to keep LinuxPod out of scope and continue only with CLI adapter/dry-run/simple-web execution.
- [ ] If blocked, record the exact blocker and upstream follow-up needed.
- [ ] Update `docs/plans/index.md` so active plans contain only the next concrete todo.
- [ ] Run `swift build` for the spike package if it exists.
- [ ] Run dry-run commands for all spike modes.
- [ ] Run `git diff --check`.

## Measurement Decision Gates

Use these gates for the final recommendation:

| Finding | Threshold | Decision |
| --- | --- | --- |
| Idle LinuxPod base memory | first valid measurement less than Apple CLI DB cgroup memory by at least 30 percent | Continue LinuxPod research |
| Postgres-only LinuxPod memory | first valid measurement near Docker cgroup memory, or clearly below Apple CLI DB cgroup memory | Promising for DB workloads |
| Marginal API cost | Adding API increases total memory by API/process-sized amount instead of another full VM-sized amount | Promising for shared runtime |
| DB block reads | first valid measurement materially below Apple CLI DB block-read baseline | Promising for storage behavior |
| Runtime stability | All smoke runs clean up owned resources | Safe enough for deeper prototype |

If only the marginal API cost improves but Postgres-only stays high, classify LinuxPod as `promising-for-multi-service-only`. That would support a future backend for larger Compose stacks, but not a Docker replacement claim for single DB containers.

If a first-pass result is within roughly 15 percent of a decision threshold, rerun
that scenario three times before classifying. If a first-pass result is far from the
threshold, do not spend time on p50/p95/p99.

## Verification Gates

- `swift build` succeeds for the spike package.
- `swift run ... --dry-run --mode idle-pod`, `postgres-only`, and `postgres-api` succeed without runtime mutation.
- Runtime smoke runs are performed only after explicit approval.
- Every runtime smoke run has cleanup evidence.
- First-pass smoke output is saved under `docs/evidence/linuxpod-base-overhead/`.
- Repeated benchmark output is saved only when Phase 4 is needed.
- Final decision note is tracked in `docs/plans/notes/index.md`.
- `git diff --check` passes after each phase.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| `LinuxPod` API requires internals not suitable for third-party use | Stop after Phase 0 or Phase 1 and classify as `blocked-api`; do not build a fragile fork. |
| Runtime commands leave pods, networks, filesystems, or helper processes behind | Use spike-owned names and cleanup verification; stop immediately if cleanup cannot be proven. |
| Metrics are not directly comparable to Docker/Apple CLI evidence | Record exact measurement source and classify unsupported fields as limitations, not assumptions. |
| Rootfs/image setup dominates the signal | Separate setup/cold costs from steady-state memory and warm-run timings. |
| Benchmark code grows into product code | Keep it under `experiments/` and do not import it into the main adapter without a follow-up plan. |
| Apple upstream answers `container#1698` while the spike runs | Incorporate the response in the decision note before changing main implementation strategy. |

## Rollback And Cleanup

- The spike must create only files under this repository and generated runtime artifacts with a `cca-linuxpod-spike-*` prefix.
- If runtime cleanup fails, stop the plan and write a blocker note with exact cleanup commands that need owner approval.
- Do not remove global Apple `container`, Docker, OrbStack, registry, or Keychain state.
- Do not run prune commands.

## Execution Prompt

```text
Continue in /Users/marlonjd/Developer/monorepos/emsi_monorepo/tools/apple-container-compose-adapter.

Execute docs/plans/2026-06-11-linuxpod-base-overhead-spike-plan.md through the decision report.

Before changes, read AGENTS.md, CLAUDE.md, README.md, docs/plans/index.md, docs/plans/2026-06-11-linuxpod-base-overhead-spike-plan.md, docs/plans/notes/2026-06-11-pilot-phase-4-shared-runtime-feasibility.md, docs/plans/notes/2026-06-11-runtime-efficiency-benchmark-evidence.md, and docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md. Use google-eng-practices plus superpowers:executing-plans or superpowers:subagent-driven-development when available.

Do not create/switch/rename/delete branches. Do not edit the parent EMSI monorepo or update submodule pointers. Do not commit or push unless explicitly requested.

Goal: test whether apple/containerization LinuxPod has a lower base runtime overhead than the public Apple container CLI path without building the full Compose adapter.

Work in phases:
1. Phase 0: non-mutating LinuxPod API/source feasibility only. Inspect official containerization LinuxPod source/tests/examples and record whether a direct SwiftPM spike is viable. Run git diff --check and update docs/plans/index.md to the next concrete todo.
2. Phase 1: create an isolated SwiftPM spike under experiments/linuxpod-base-overhead with dry-run modes for idle-pod, postgres-only, and postgres-api. Build and run dry-run only. Run git diff --check and update docs/plans/index.md.
3. Phase 2: define JSONL measurement schema, redaction, statuses, cleanup rules, and approval gates before any runtime mutation. Run git diff --check and update docs/plans/index.md.
4. Phase 3: request explicit approval before any command that creates, starts, stops, or deletes LinuxPod/runtime resources. If approved, run one smoke iteration per mode and verify cleanup. If not approved or blocked, record skipped/blocked evidence.
5. Phase 4: after explicit approval, decide whether repeated LinuxPod benchmarks are necessary. Skip repeats if the Phase 3 smoke results are clearly decisive. If a scenario is near a decision threshold or noisy, run 3 focused repeats. Run 10+ iterations and p50/p95/p99 only if LinuxPod looks promising enough to justify publication-grade evidence. Always capture RAM, CPU, disk footprint, block I/O, startup/readiness, cleanup, and failure counts for any run that is performed.
6. Phase 5: write docs/plans/notes/2026-06-11-linuxpod-base-overhead-spike-evidence.md with a decision: promising, promising-for-multi-service-only, not-promising, blocked, or needs-upstream. Update docs/plans/notes/index.md, docs/plans/index.md, and the main implementation plan only if the decision changes the next runtime strategy.

Use existing Docker/OrbStack and Apple container CLI evidence from docs/evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-report.md as comparison baseline. Do not run private EMSI workloads, registry login, prune, global cleanup, or destructive host changes. Save evidence under docs/evidence/linuxpod-base-overhead/. Final response must summarize measured/skipped evidence, whether LinuxPod reduces base VM/runtime overhead, recommendation for the main adapter, commands not run/why, cleanup status, and verification.
```
