# LinuxPod Phase 6B Root-Cause Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Goal:** Isolate why LinuxPod Phase 6 is slow and block-read heavy without changing the product direction or reviving LinuxPod as the default replacement path.
**Architecture:** Add a narrow Phase 6B research harness that records operation-level timings, cache-hit state, lifecycle strategy, guest metrics, and cleanup proof for the same public backend-shaped fixture. Keep Docker/OrbStack as the product reference and compare open source Docker-compatible VM runtimes as alternatives, while leaving the Phase 6 `linuxpod-not-promising` decision intact.
**Tech Stack:** Swift Package Manager, XCTest, `apple/containerization` LinuxPod APIs, adapter-owned runtime state, JSONL evidence, Docker Compose-compatible benchmark commands, optional locally installed Colima/Lima/Finch probes.

---

## Objective

Open a small Phase 6B root-cause slice that answers these questions with
evidence:

- If the same LinuxPod project/state is preserved, how much faster does the
  backend-shaped fixture become?
- Does `prepareImageRootfs` really hit the rootfs cache, and which image or
  rootfs step still performs expensive work?
- How much time is spent in `pod.create`, `EXT4Unpacker.unpack`, APFS
  per-container rootfs cloning, named-volume formatting, container registration,
  container start, readiness probes, and cleanup?
- Is the high block-read signal caused mostly by rootfs unpack/clone, pod boot,
  Postgres named-volume behavior, readiness/jobs, or repeated cold cleanup?
- How does the same public fixture behave on Docker/OrbStack and, when locally
  installed, Colima, Lima, and Finch?

The output is a root-cause decision note and JSONL evidence. It is not a
runtime optimization phase, not Phase 7, and not a product-direction change.

## Product Direction Guardrail

Do not change the product direction in this plan.

The current product recommendation remains:

- Docker/OrbStack stays the recommended backend runtime.
- LinuxPod stays optional research only.
- The existing Phase 6 decision `linuxpod-not-promising` remains valid unless
  Phase 6B produces new, reviewed evidence and a separate explicit decision.
- No README, release note, or product-facing copy may claim LinuxPod is a
  Docker/OrbStack replacement as part of this plan.

Phase 6B may identify a later optimization hypothesis, but it must end with one
of these research decisions:

- `linuxpod-cache-not-enough`
- `linuxpod-cache-promising-research-only`
- `linuxpod-upstream-bottleneck`
- `switch-open-source-docker-compatible-vm-for-runtime-research`

None of those decisions changes product direction by itself.

## Scope

In scope:

- Add or extend a Phase 6B benchmark data model.
- Add operation-level timing spans around the current LinuxPod executor path.
- Add a harness mode that can run:
  - cold cleanup-per-iteration baseline;
  - same project with preserved rootfs/image state;
  - same project with preserved named volume where safe and explicitly labeled;
  - same project with stop-only cleanup where the API allows it;
  - dry-run-only cache-state proof.
- Preserve no-side-effect dry-run evidence before runtime mutation.
- Compare against Docker/OrbStack using the existing public backend-shaped
  fixture and current benchmark script.
- Add optional local probes for Colima, Lima, and Finch only when installed.
- Write evidence under `docs/evidence/linuxpod-phase6b-root-cause/`.
- Write a durable decision note under `docs/plans/notes/`.
- Update `docs/plans/index.md` and `docs/plans/notes/index.md` to match the
  final state.

Out of scope:

- Phase 7 optimization.
- Changing the default runtime.
- Claiming host RAM savings.
- Adding a new production runtime backend for Colima, Lima, Finch, or Podman.
- Installing Colima, Lima, Finch, Podman, or Rancher Desktop automatically.
- Mutating Docker Hub, Apple `container` registries, Keychain credentials,
  global DNS, or host networking.
- Running private EMSI workloads.
- Updating the parent EMSI monorepo gitlink.
- Branch creation, switching, deletion, or renaming.

## Assumptions And Open Questions

Assumptions:

- Existing Phase 5 host-memory conclusion remains true: per-process host
  physical memory is blocked and must not be used for replacement claims.
- Existing Phase 6 numbers remain the baseline: backend guest cgroup current
  p50 `188.2MiB`, up duration p50 `64.83s`, block read p50 `104.5MiB`.
- Docker/OrbStack baseline remains: backend DB+API cgroup about `86.4MiB`,
  start-to-wait p50 `12.859s`, DB+API block read about `4.86MiB`.
- Runtime mutation requires the existing signed binary flow and explicit
  approval token.
- Open source alternatives may not be installed locally; their checks must be
  skipped and recorded as `not-installed`, not treated as failures.

Open questions:

- Can the current `LinuxPod` instance be reused after stopping service
  containers, or does the API require constructing a fresh pod for each full
  backend fixture iteration?
- Does `ImageStore.get(reference:pull:)` perform remote or local validation on
  every call even when rootfs exists?
- Does APFS `copyItem` preserve clone semantics reliably for large ext4 files
  in this environment, or does it sometimes materialize data?
- Is the `blockReadBytes` signal cumulative per pod lifetime, per device, or
  per sampled process group in a way that needs delta-based reporting?
- Does preserving named volume state make the fixture non-equivalent to Docker
  fresh-volume baseline, and if so, should it be a separate warm-persistence
  mode only?

## Affected Files

Likely create:

- `Sources/ContainerComposeAdapter/Phase6BRootCause.swift`
- `Sources/ContainerComposeAdapterPhase6BRootCause/main.swift`
- `docs/evidence/linuxpod-phase6b-root-cause/.gitkeep` if needed
- `docs/plans/notes/2026-06-12-linuxpod-phase-6b-root-cause-evidence.md`

Likely modify:

- `Package.swift`
- `Sources/ContainerComposeAdapterLinuxPod/ContainerizationLinuxPodRuntimeExecutor.swift`
- `Sources/ContainerComposeAdapter/LinuxPodBackend.swift`
- `Tests/ContainerComposeAdapterTests/RuntimeContractTests.swift`
- `README.md` only if a new developer-only harness command must be documented
- `docs/plans/index.md`
- `docs/plans/notes/index.md`

Do not modify:

- EMSI parent monorepo files
- Product direction copy that recommends LinuxPod as default
- Completed evidence files from Phase 5 or Phase 6

## Implementation Phases

### Phase 0: Baseline Protection

- [ ] Confirm current `git status --short` and identify unrelated dirty files.
- [ ] Re-read:
  - `AGENTS.md`
  - `docs/plans/notes/2026-06-12-linuxpod-phase-6-benchmark-decision.md`
  - `docs/plans/notes/2026-06-12-linuxpod-phase-5-host-footprint-evidence.md`
  - `Sources/ContainerComposeAdapterLinuxPod/ContainerizationLinuxPodRuntimeExecutor.swift`
  - `Sources/ContainerComposeAdapter/Phase6Benchmark.swift`
- [ ] Run `swift test` before implementation if the sandbox allows it; if it
  fails due sandbox cache restrictions, rerun with approved escalation.
- [ ] Do not run runtime mutation in Phase 0.

### Phase 1: Phase 6B Evidence Schema

- [ ] Add a `Phase6BRootCause` model with:
  - schema version;
  - run mode;
  - iteration status;
  - span records;
  - cache state records;
  - guest metric deltas;
  - optional external runtime comparison records;
  - summary record.
- [ ] Include span names at minimum:
  - `createProjectRuntime`
  - `getInitImage`
  - `initBlock`
  - `prepareImageRootfs`
  - `imageStoreGet`
  - `imageConfig`
  - `declaredVolumes`
  - `ext4Unpack`
  - `containerRootfsClone`
  - `createNamedVolume`
  - `addContainer`
  - `podCreate`
  - `startContainer`
  - `runJob`
  - `waitForReadiness`
  - `guestStatistics`
  - `stopProjectRuntime`
  - `deleteProjectRuntime`
  - `cleanupNamedVolume`
- [ ] Add tests proving summary p50 calculations, cache-hit counts, and
  `not-installed` external runtime records.

### Phase 2: Low-Noise Instrumentation

- [ ] Add a narrow instrumentation surface to the LinuxPod executor, preferably
  injectable and disabled by default.
- [ ] Record monotonic duration and metadata for each span without logging
  secrets or full local paths.
- [ ] Metadata should include only safe values:
  - image reference;
  - cache hit/miss;
  - file exists before/after;
  - file size in bytes;
  - service name;
  - action kind;
  - run mode.
- [ ] Redact or omit environment values, registry tokens, host absolute paths,
  and local user names.
- [ ] Keep production behavior unchanged when no recorder is attached.

### Phase 3: LinuxPod Root-Cause Harness

- [ ] Add executable target `container-compose-phase6b-root-cause`.
- [ ] Support these modes:
  - `cold-clean`: current Phase 6 behavior, full `down --volumes` after each
    iteration.
  - `warm-rootfs`: preserve project runtime rootfs/image state between
    iterations but still delete containers/volumes where the API supports safe
    equivalence.
  - `warm-volume`: preserve rootfs and named volume, explicitly labeled as
    non-fresh-volume and used only to isolate I/O cost.
  - `stop-only`: stop runtime without deleting state, if API behavior allows;
    otherwise emit `unsupported`.
  - `dry-cache`: dry-run cache-state proof without runtime mutation.
- [ ] Every mutating run must:
  - require the runtime approval token;
  - use the signed debug binary, not plain `swift run`;
  - write JSONL evidence;
  - attempt best-effort cleanup on failure.
- [ ] Every mode must report:
  - action count;
  - success/failure;
  - span timings;
  - guest cgroup current;
  - process count;
  - block read/write;
  - cleanup state;
  - whether comparison to Docker fresh-volume baseline is valid.

### Phase 4: Docker And Open Source Runtime Comparison

- [ ] Reuse the existing public backend-shaped fixture and benchmark script for
  Docker/OrbStack.
- [ ] Add optional detection commands:
  - `docker context ls`
  - `colima status`
  - `limactl list`
  - `finch vm status`
- [ ] If a runtime is not installed or not running, record `not-installed` or
  `not-running` in evidence and continue.
- [ ] Do not install or start third-party runtimes automatically.
- [ ] For installed/running alternatives, run the same fixture shape only when
  it can be done without private data and with explicit user approval for
  runtime mutation.
- [ ] Label each comparison by runtime and backend:
  - Docker/OrbStack
  - Colima Docker
  - Lima Docker
  - Lima containerd/nerdctl
  - Finch containerd/nerdctl

### Phase 5: Decision Note

- [ ] Write `docs/plans/notes/2026-06-12-linuxpod-phase-6b-root-cause-evidence.md`.
- [ ] Include:
  - exact commands run;
  - runtime mutation approval status;
  - signed-binary proof;
  - dry-run evidence path;
  - LinuxPod mode table;
  - span timing table;
  - cache hit/miss table;
  - block read/write deltas;
  - Docker/OrbStack and optional open source alternative comparison;
  - final Phase 6B decision.
- [ ] The note must explicitly state that product direction did not change.
- [ ] Update `docs/plans/notes/index.md`.
- [ ] Update this plan and `docs/plans/index.md`:
  - keep this plan active if runtime evidence is incomplete;
  - mark `ready-for-verification` only when all required evidence exists;
  - move to completed only after verification passes and indexes are updated.

## Verification Gates

Required before claiming Phase 6B implementation complete:

- `swift test`
- `git diff --check`
- No-side-effect dry-cache run writes JSONL evidence.
- Signed runtime smoke for at least one LinuxPod mode writes JSONL evidence.
- At least one root-cause run includes successful cleanup proof.
- Evidence JSONL validates with `jq` or an equivalent parser.
- Decision note and both plan indexes match actual final state.

Runtime evidence minimum:

- `cold-clean`: at least `2` iterations.
- `warm-rootfs`: at least `2` iterations, unless unsupported by API and
  documented.
- `warm-volume`: at least `2` iterations, explicitly marked non-equivalent to
  fresh-volume baseline.
- Docker/OrbStack comparison: reuse existing baseline or rerun only with
  explicit approval.
- Colima/Lima/Finch: record detection result; runtime benchmark is optional and
  must not block if the tool is not installed.

Do not run `10` or `20+` Phase 6B iterations until Phase 6B identifies a
specific promising bottleneck.

## Risks And Mitigations

Risk: instrumentation changes runtime behavior.
Mitigation: keep recorder injectable, disabled by default, and covered by tests.

Risk: warm-rootfs or stop-only mode is not equivalent to Docker fresh-volume
baseline.
Mitigation: label mode equivalence explicitly and use it only for root-cause
isolation.

Risk: cleanup failure leaves adapter-owned state.
Mitigation: use adapter-owned prefixes, best-effort cleanup, and final external
state checks.

Risk: optional alternative runtime probing mutates user environments.
Mitigation: detection only by default; benchmark only with explicit approval.

Risk: block I/O counters are cumulative and misread as per-iteration values.
Mitigation: record before/after deltas where possible and state counter
semantics in the evidence note.

Risk: Phase 6B is interpreted as reviving LinuxPod product direction.
Mitigation: keep the guardrail in the plan, index, and decision note.

## Dependencies And Ownership Boundaries

- Owner: `tools/apple-container-compose-adapter`.
- Runtime target: `apple/containerization` LinuxPod APIs already used in this
  repository.
- Compatibility reference: Docker Compose behavior.
- Product reference: Docker/OrbStack backend developer workflow.
- Optional comparison targets: Colima, Lima, Finch only when already installed
  and explicitly approved for runtime mutation.
- No parent monorepo integration or submodule pointer update is part of this
  plan.

## Rollback And Recovery

- Remove the Phase 6B executable target and schema files if the harness creates
  too much maintenance cost.
- Revert only Phase 6B instrumentation if it touches production code paths.
- Keep Phase 5 and Phase 6 evidence files intact.
- If a runtime run fails, execute the adapter-owned cleanup command for the same
  project name and record cleanup status in the evidence note.
- If optional third-party runtime checks are unavailable, leave them recorded as
  `not-installed`, `not-running`, or `not-approved`.

## Execution Prompt

```text
Implement the plan at docs/plans/2026-06-12-linuxpod-phase-6b-root-cause-plan.md in the Container Compose Adapter repository.

Use the repository root /Users/marlonjd/Developer/monorepos/emsi_monorepo/tools/apple-container-compose-adapter. Follow AGENTS.md. Do not create, switch, rename, or delete branches. Do not update the parent EMSI monorepo gitlink. Keep Docker/OrbStack as the recommended backend runtime and do not change product direction.

Use these skills before acting: emsi-workflows:emsi-task-router, emsi-workflows:emsi-plan-artifact, emsi-workflows:emsi-verification-gate, and superpowers:executing-plans. Read AGENTS.md, docs/plans/2026-06-12-linuxpod-phase-6b-root-cause-plan.md, docs/plans/notes/2026-06-12-linuxpod-phase-6-benchmark-decision.md, docs/plans/notes/2026-06-12-linuxpod-phase-5-host-footprint-evidence.md, Sources/ContainerComposeAdapterLinuxPod/ContainerizationLinuxPodRuntimeExecutor.swift, and Sources/ContainerComposeAdapter/Phase6Benchmark.swift.

Implement Phase 6B only: add operation-level LinuxPod timing/cache instrumentation, a container-compose-phase6b-root-cause harness, tests for the evidence model, JSONL evidence output under docs/evidence/linuxpod-phase6b-root-cause/, optional detection-only records for Colima/Lima/Finch, and a decision note under docs/plans/notes/. Runtime mutation requires explicit approval and the signed binary flow; do not run long 10/20+ iteration benchmarks.

Verification required before claiming completion: swift test, git diff --check, dry-cache JSONL evidence, at least one signed LinuxPod runtime smoke/root-cause evidence file if approved, JSONL validation, and matching updates to docs/plans/index.md and docs/plans/notes/index.md.
```
