# Efficiency And Shared Runtime Pilot Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this pilot task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-06-11
**Owner subtree:** `tools/apple-container-compose-adapter`
**Goal:** Decide whether Container Compose Adapter is worth pursuing as an OrbStackless daily development path by measuring Apple `container` native runtime efficiency and investigating whether a shared-runtime equivalent is feasible without rebuilding OrbStack/Docker Desktop.
**Architecture:** Treat this as a decision pilot before full adapter implementation. Keep benchmark harnesses, runtime capability discovery, and feasibility notes separate from production adapter code so the project can stop, pivot, or proceed based on evidence.
**Tech stack proposal:** Swift Package Manager or shell-free Swift CLI harness once the package exists, Markdown evidence reports, Apple `container` no-side-effect capability discovery, optional controlled runtime smoke commands, and comparison against the existing OrbStack/Docker Compose flow when available.

---

## Objective

Create a small, evidence-driven pilot that answers three questions before the project invests in a full Compose adapter:

1. Does Apple `container` native runtime provide a meaningful daily-development benefit compared with the current OrbStack/Docker Compose path?
2. Can a shared-runtime model similar to the current Docker host be built on top of official Apple `container` or `containerization` primitives?
3. If shared runtime is not feasible without building a new Docker/OrbStack-like runtime, is the per-container Apple model still valuable enough to continue?

## Background

Apple's documented runtime model is intentionally different from Docker Desktop or OrbStack-style shared Docker hosts. The Apple `container` technical overview says it runs a lightweight VM for each container, and the lower-level `apple/containerization` package says each Linux container executes inside its own lightweight virtual machine.

That means a direct "same Docker host, many containers" equivalent is probably not available through the public Apple `container` CLI today. The pilot must verify this from current docs, local capability discovery, and small experiments instead of assuming either direction.

## Scope

- Build or document a no-side-effect benchmark and feasibility harness.
- Compare the current OrbStack/Docker Compose shape against an Apple `container` native path using equivalent backend-shaped workloads.
- Investigate three runtime architecture options:
  - Apple native per-container VM orchestration.
  - Shared-runtime support through official Apple `container` or `containerization` APIs, if such primitives exist.
  - A custom shared Linux VM with containerd/Docker-like orchestration, treated as a high-risk alternative rather than the default path.
- Produce a written recommendation: proceed, proceed with narrower scope, pause, or pivot.
- Update the main implementation plan based on the pilot result.

## Non-goals / Out Of Scope

- Building the full Compose adapter.
- Replacing Docker, Docker Compose, Docker Desktop, or OrbStack during the pilot.
- Claiming Apple `container` is faster or lighter without measurements.
- Claiming shared runtime is impossible without checking current docs, local CLI/API capability, and practical prototype options.
- Building a production shared VM/containerd runtime as part of this pilot.
- Mutating private EMSI backend data or relying on private registries.
- Editing parent EMSI monorepo files except for a requested submodule pointer update after this repository has its own commit.
- Creating, switching, renaming, deleting, or otherwise changing branches.

## Assumptions

- The pilot should use public, minimal fixtures first, then optionally use an EMSI-shaped fixture when safe.
- Apple `container` may not be installed in every environment; the pilot must still produce no-runtime findings from docs and capability discovery code.
- Docker/OrbStack measurements are useful as a baseline but must be clearly labeled with machine, macOS version, OrbStack version, Apple `container` version, and workload details.
- Shared-runtime feasibility should be judged by product fit, maintenance burden, security model, and performance, not only by whether it is theoretically possible.

## Pilot Architecture Options

### Option A: Apple Native Per-container Runtime

Use Apple `container` as designed:

- One lightweight VM per service container.
- Adapter owns Compose-like orchestration: build, network, service-name connectivity, health gates, logs, status, and cleanup.
- Expected benefit: native macOS integration, clearer isolation, no Docker/OrbStack dependency for supported stacks.
- Main risk: multi-service stacks may use more memory or have more coordination overhead than a shared Docker host.

### Option B: Official Apple Shared Runtime Primitive

Investigate whether Apple exposes a public way to run multiple OCI containers or containerized processes inside one shared Linux VM while preserving Compose-like lifecycle boundaries.

Evidence to collect:

- `container --help` and subcommand help for pod/group/shared-machine concepts.
- Apple `container` docs for multi-container shared VM primitives.
- `apple/containerization` APIs for spawning multiple containerized processes inside one Linux VM with separate OCI roots, networking, logs, and lifecycle.
- Existing examples in Apple repos that look like pod/shared-runtime behavior.

Decision rule:

- If a supported primitive exists, create a follow-up design for a shared-runtime adapter mode.
- If no supported primitive exists, do not fake the claim. Move to Option C only as a high-risk alternative.

### Option C: Custom Shared VM Runtime

Run one Linux VM and manage several services inside it through containerd, Docker, or custom process supervision.

Expected benefit:

- Closer to OrbStack/Docker host efficiency for many service containers.

Risks:

- This starts becoming a new OrbStack/Docker Desktop competitor rather than a Compose adapter for Apple `container`.
- Higher maintenance burden: kernel, image store, networking, DNS, volume mounts, logging, lifecycle, upgrades, security, and cleanup.
- It may lose the main Apple `container` value: per-container VM isolation and native runtime simplicity.

Decision rule:

- Do not pursue Option C unless Option A is measurably worse and the project owner explicitly accepts the scope expansion.

## Metrics

Measure the same workload across comparable paths whenever possible.

### Core Metrics

- Cold start time to HTTP readiness.
- Warm start time to HTTP readiness.
- Rebuild time after a small source change.
- Idle memory after services become ready.
- Peak memory during startup.
- Idle CPU after readiness.
- Peak CPU during startup.
- Disk usage for images, writable state, and named volumes.
- Teardown time for `down`.
- Repeated `up` idempotency time and resource count.
- API-to-database connection success and basic latency.
- Host-to-API `localhost` readiness latency.
- Logs/status responsiveness.

### Safety And Correctness Metrics

- Cleanup removes only adapter-owned resources.
- Named volumes persist across `down` and are removed only by explicit volume cleanup.
- Secret-looking env values are redacted in reports.
- No private host credential directories are mounted.
- The harness can run without Docker/OrbStack for Apple-native measurements.

## Workloads

### Workload 1: Simple Public Web

Purpose: smoke test baseline runtime overhead.

- One public HTTP image.
- One published high host port.
- No volumes.
- No private data.

### Workload 2: Backend-shaped Public Fixture

Purpose: approximate the EMSI backend structure without private data.

- Database service with named volume and health check.
- Migrate job that exits successfully after database health.
- Seed job that exits successfully after migration.
- API-like service that exposes `localhost` HTTP readiness.
- Service-name connectivity from API to database.
- `up --build --wait`, `status`, `logs`, `run`, `down`, repeated `up`, and `down --volumes`.

### Workload 3: EMSI Backend Optional Validation

Purpose: validate real-world relevance only after public fixtures are safe.

- Use `backend/go-api` only if the user explicitly asks for EMSI validation.
- Do not change EMSI source files from this repository.
- Capture commands, versions, timings, and whether Docker/OrbStack was stopped or unavailable.

## Phased Pilot Plan

### Phase 0: Baseline Context And Capability Discovery

- [ ] Read `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/plans/index.md`, this plan, and the main implementation plan.
- [ ] Capture macOS version, CPU architecture, available memory, and shell environment relevant to runtime measurements.
- [ ] Capture current Docker context and OrbStack availability without mutating resources.
- [ ] Capture Apple `container` availability using no-side-effect commands.
- [ ] Capture Apple `container` help output for build, run, network, volume, exec, logs, status/list, and system commands when available.
- [ ] Search official Apple `container` and `containerization` docs for shared-runtime, pod, machine, and multi-process-in-one-VM primitives.
- [ ] Update `docs/plans/index.md` next todo after this phase.

### Phase 1: Measurement Harness Design

- [ ] Define a stable evidence schema for benchmark runs.
- [ ] Define command wrappers that record start time, end time, exit code, stdout/stderr summary, and resource snapshots.
- [ ] Define resource snapshot strategy for memory, CPU, disk, and runtime resource count.
- [ ] Define redaction rules for env values and command output.
- [ ] Document how to mark evidence as `measured`, `skipped-runtime-unavailable`, or `blocked`.
- [ ] Add dry-run-only harness behavior before any mutating runtime measurement.

### Phase 2: OrbStack/Docker Compose Baseline

- [ ] Build a public simple-web Compose fixture.
- [ ] Build a public backend-shaped Compose fixture.
- [ ] Run the baseline only when Docker/OrbStack is available and execution is approved.
- [ ] Measure cold start, warm start, rebuild, idle memory, peak memory, CPU, disk, teardown, and repeated `up`.
- [ ] Record resource cleanup behavior and named volume persistence.
- [ ] Save evidence under `docs/plans/notes/` or `docs/evidence/` if that folder exists by then.

### Phase 3: Apple Native Per-container Pilot

- [ ] Map the simple-web fixture manually or through a minimal pilot harness to Apple `container` commands.
- [ ] Map the backend-shaped fixture to Apple `container` commands as far as current runtime capabilities allow.
- [ ] Measure the same metrics as the OrbStack baseline when Apple `container` is available and execution is approved.
- [ ] Record missing features as blocking diagnostics rather than papering over them.
- [ ] Identify whether per-container overhead is acceptable for daily development.

### Phase 4: Shared Runtime Feasibility Spike

- [ ] Verify whether official Apple `container` CLI exposes any shared-runtime or pod-like primitive.
- [ ] Verify whether `apple/containerization` public APIs can run multiple isolated OCI roots/processes inside one VM while preserving service lifecycle, logs, networking, and cleanup.
- [ ] If official support exists, sketch the smallest shared-runtime adapter mode and required tests.
- [ ] If official support does not exist, document why a custom shared VM/containerd approach would be a separate runtime product.
- [ ] Decide whether shared runtime remains in scope, becomes a future research track, or is explicitly out of scope.

### Phase 5: Decision Report And Plan Updates

- [ ] Write a pilot report with measured data, skipped evidence, blockers, and recommendation.
- [ ] Compare Apple native per-container results against OrbStack/Docker Compose baseline.
- [ ] State whether the project should proceed because it is more efficient, proceed for non-performance reasons, narrow scope, pause, or pivot.
- [ ] Update the main implementation plan with the decision.
- [ ] Update `docs/plans/index.md` with the next concrete todo.
- [ ] If the pilot is complete, move this plan to `docs/plans/completed/` and update `docs/plans/completed/index.md`.

## Go / No-go Criteria

### Go: Proceed Toward Full Adapter

Proceed if at least one of these is true:

- Apple native per-container runtime is materially better for the target workflow, such as lower idle memory, faster readiness, faster rebuild loop, or lower operational friction.
- Apple native runtime is performance-neutral but removes enough dependency weight that the product remains valuable.
- A supported shared-runtime primitive exists and can be used without building a new Docker/OrbStack-like runtime.

### Narrow Scope

Proceed with a narrower scope if:

- Simple or small stacks benefit, but backend-shaped stacks are not competitive yet.
- Apple runtime is promising but missing build, network, health, or volume primitives that require staged implementation.

### Pause Or Pivot

Pause or pivot if:

- Apple native per-container runtime is consistently worse for the target workflow and offers no compensating simplicity, isolation, or maintenance benefit.
- Shared runtime requires building a full Docker/OrbStack-like runtime and the owner does not want that scope.
- Required Apple runtime features are unavailable or too unstable for daily development.

## Verification Gates

- `git diff --check` passes for all pilot docs.
- No mutating runtime command runs without explicit approval.
- Each evidence file records versions, machine context, commands, expected behavior, actual behavior, and whether Docker/OrbStack was running.
- Apple-native measurements are not compared against OrbStack unless both were run on the same machine under comparable conditions.
- Shared-runtime feasibility conclusions cite official docs, local CLI/API discovery, or direct prototype evidence.

## Risks And Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Apple runtime is not installed | No runtime measurements | Produce docs/capability findings and mark runtime evidence as skipped |
| Measurements are noisy | Bad decision | Repeat runs, separate cold/warm runs, record machine state |
| Shared runtime becomes a new Docker clone | Scope explosion | Treat custom shared VM/containerd as a separate product decision |
| Pilot mutates local state | Data loss or developer friction | Use public fixtures, high ports, adapter-owned names, dry-run first |
| Performance is neutral | Ambiguous value | Include operational friction, dependency count, security/isolation, and maintenance as decision factors |
| Private EMSI data leaks into evidence | Security issue | Use public fixtures by default; redact outputs; require explicit EMSI validation request |

## Dependencies

- Apple official docs:
  - `apple/container` technical overview.
  - `apple/containerization` README/API docs.
- Local runtime tools when available:
  - Apple `container`.
  - Docker/OrbStack for baseline comparison.
- Public fixture images and generated local-only test data.
- Repository docs:
  - `AGENTS.md`
  - `CLAUDE.md`
  - `docs/plans/index.md`
  - `docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md`

## Ownership Boundaries

- This repository owns pilot fixtures, benchmark harnesses, docs, and evidence.
- Parent EMSI monorepo integration is out of scope unless explicitly requested.
- Apple `container` and `containerization` own runtime internals; this project owns measurement, orchestration decisions, and adapter scope.
- OrbStack/Docker Compose are baseline tools, not dependencies of the Apple-native path.

## Open Questions

- What threshold counts as "more efficient enough" for this project: 10 percent, 20 percent, or a qualitative reduction in daily friction?
- Should the first public release be Apple-native per-container only, even if it is not faster than OrbStack for large stacks?
- Is a custom shared VM/containerd runtime philosophically acceptable for this project, or should the project stay strictly on Apple `container`?
- Which exact machine should be the benchmark reference?
- Should EMSI backend validation be a later private follow-up rather than part of this public AGPL project?

## Completion Criteria

The pilot is complete when:

- A pilot report exists with measured or explicitly skipped evidence.
- The report compares Apple native per-container runtime with OrbStack/Docker Compose for at least the simple-web workload.
- The backend-shaped workload is measured or blocked with clear runtime capability reasons.
- Shared-runtime feasibility is classified as supported, unsupported, possible but out of scope, or requiring a separate runtime product.
- The main implementation plan is updated based on the pilot result.
- `docs/plans/index.md` accurately reflects the next todo or completed state.

## Execution Prompt

```text
Implement the pilot in docs/plans/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md for the Container Compose Adapter repository.

Before changing files, read AGENTS.md, CLAUDE.md, README.md, docs/plans/index.md, docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md, and this pilot plan. Use google-eng-practices for evidence-based planning and review, and use superpowers:executing-plans or superpowers:subagent-driven-development when available. Do not create, switch, rename, delete, or otherwise change branches. Do not edit the parent EMSI monorepo or update any submodule pointer unless explicitly asked.

Start with Phase 0. Use no-side-effect commands first: capture local Docker/OrbStack context, Apple container availability, Apple container help/capability surfaces, and official documentation evidence for per-container VM versus any shared-runtime primitive. Do not run mutating runtime commands until the dry-run/evidence harness is in place and execution is explicitly approved.

The decision standard is not "can we make Compose syntax work?" It is "does Apple container native runtime provide enough efficiency or operational value to justify replacing OrbStack for supported daily development, and is a shared-runtime equivalent possible without building a new Docker/OrbStack-like runtime?" Record measured data, skipped evidence, blockers, and a clear proceed/narrow/pause/pivot recommendation. Update docs/plans/index.md after each phase so it contains only the next concrete todo for active plans.
```
