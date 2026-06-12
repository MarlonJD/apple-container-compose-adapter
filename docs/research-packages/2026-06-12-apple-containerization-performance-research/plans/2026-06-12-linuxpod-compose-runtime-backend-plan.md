# LinuxPod Compose Runtime Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Goal:** Build a LinuxPod-first shared-runtime backend that can match or beat Docker/OrbStack-backed Docker Compose for backend-shaped local development, not merely beat the public Apple `container` CLI.
**Architecture:** Keep Compose parsing, normalization, compatibility analysis, dry-run planning, redaction, and safety diagnostics runtime-neutral. Add a backend boundary where LinuxPod is the only active efficiency target, Docker/OrbStack is the primary benchmark, and public Apple `container` CLI remains only a fallback, capability probe, or negative-control comparison.
**Tech stack proposal:** Swift Package Manager CLI, XCTest, `apple/containerization` LinuxPod APIs, adapter-owned runtime state, JSONL benchmark evidence, and public Docker/OrbStack evidence as the required comparison baseline. No new production dependency is added by this planning artifact.

---

## Objective

Build and prove a LinuxPod-first runtime backend for Container Compose Adapter.
The backend should translate the adapter's internal Compose execution plan into
one project-scoped LinuxPod VM, then run services, jobs, readiness probes, logs,
status, and cleanup inside that shared VM.

The purpose is efficiency and developer usability, not merely parity with the
public Apple `container` CLI. The public CLI path is no longer the main
optimization path for backend-shaped stacks because measured evidence shows it
adds material DB/runtime overhead versus Docker/OrbStack and does not expose a
shared-runtime command surface.

Beating the public Apple CLI is not a success criterion. It is useful only as
evidence that the lower-level LinuxPod path is better than the public CLI path.
The product target is Docker Compose behavior with Docker/OrbStack-level or
better resource use, startup/readiness, disk I/O, throughput, and reliability.

## Current Evidence And Product Thesis

The LinuxPod spike is promising, but it has not yet proved Docker/OrbStack
replacement.

Measured evidence:

- Public Apple `container` CLI `postgres-db-only` cgroup current p50:
  `187.45MiB`.
- Docker/OrbStack `postgres-db-only` cgroup current p50: `65.14MiB`.
- LinuxPod `postgres-only` smoke cgroup current: `124.75MiB` to `125.06MiB`.
- LinuxPod `postgres-api` smoke cgroup current: `137.13MiB` to `137.35MiB`.
- LinuxPod second-container marginal cgroup increase in the smoke fixture:
  about `12MiB`.
- Postgres process RSS is almost identical across runtimes: about `26MiB` to
  `28MiB`.
- Host VM footprint is still unproven because runner-process RSS did not track
  the LinuxPod VM's physical memory.

Interpretation:

- LinuxPod already beats the public Apple CLI path for the measured Postgres
  guest/cgroup memory signal, but that is only a viability signal.
- Docker/OrbStack still beats LinuxPod for a single Postgres container in the
  measured cgroup signal.
- LinuxPod's strongest product hope is shared-runtime composition: one VM per
  Compose project with process-sized marginal service cost instead of
  per-service VM-shaped overhead.
- Apple being "more efficient" is plausible for tiny or simple workloads, and
  the public CLI simple-web evidence was competitive. It is not automatic for
  database workloads because VM isolation, filesystem unpacking, page cache,
  block I/O, and per-container runtime shape can dominate the actual process
  RSS.

## Decision Position

Use LinuxPod as the primary runtime strategy for backend-shaped OrbStackless
daily development research.

The target runtime to beat is Docker/OrbStack running Docker Compose-compatible
local stacks. Public Apple `container` CLI is not a target to optimize against.
If LinuxPod cannot reach Docker/OrbStack-competitive metrics after the focused
optimization pass, the project should stop presenting LinuxPod as a replacement
path and keep it as research or an optional backend only.

Use public Apple `container` CLI only for:

- no-side-effect capability discovery;
- public CLI compatibility diagnostics;
- simple fallback experiments;
- negative-control or historical comparison benchmarks;
- a possible non-default backend if it later gains a shared-runtime surface.

Do not invest further in public CLI backend execution as the route to lower
backend memory overhead unless new upstream evidence changes the measured
runtime shape.

## Scope

This plan covers:

- Runtime-neutral adapter architecture and dry-run contract.
- A LinuxPod backend boundary that can execute a project-scoped plan.
- LinuxPod image/rootfs management using public images only.
- One LinuxPod VM per Compose project.
- Multiple services in the same LinuxPod.
- Project-scoped service identity, logs, status, readiness, and cleanup.
- Named volume persistence using adapter-owned directories or LinuxPod mounts.
- Service-name connectivity inside the project runtime.
- One-off jobs and `depends_on` readiness/job completion ordering.
- Host-memory measurement research with reliable sources, not runner-process
  RSS.
- Public benchmark fixtures that compare LinuxPod primarily against
  Docker/OrbStack, with public Apple CLI kept only as a secondary historical
  baseline.
- Documentation and plan updates that make LinuxPod the primary efficiency
  track.

## Non-goals / Out Of Scope

- Claiming full Docker Compose parity.
- Claiming LinuxPod beats Docker/OrbStack before host footprint, cgroup memory,
  startup/readiness, disk I/O, and failure-rate gates pass.
- Running private EMSI workloads in benchmark evidence.
- Registry login, credential mutation, Docker Hub account changes, Keychain
  changes, global DNS changes, runtime prune, or destructive host cleanup.
- Editing EMSI parent monorepo files or updating submodule pointers.
- Branch creation, switching, renaming, or deletion.
- Production orchestration, remote hosts, Swarm, Kubernetes, or Docker Engine
  API compatibility.
- Silently ignoring unsupported Compose fields.

## Assumptions And Open Questions

Assumptions:

- Docker Compose behavior remains the compatibility reference.
- LinuxPod is viable enough for a direct SwiftPM backend because the isolated
  spike already built and ran public-image smoke modes.
- The adapter can keep parser, planner, diagnostics, and dry-run output
  independent of the runtime backend.
- A Compose project can be represented as one owned LinuxPod VM without
  surprising developers, as long as lifecycle and cleanup are explicit.
- Public images and public fixtures are enough to prove the runtime shape before
  any private workload is considered.

Open questions:

- Which host-side source can reliably attribute LinuxPod VM physical memory?
- Can LinuxPod expose or support service-name DNS cleanly, or should the adapter
  manage `/etc/hosts` entries inside rootfs/container setup? Phase 0 source
  audit found public LinuxPod `Hosts` support, so adapter-managed hosts entries
  are the first Phase 4 design candidate, pending dry-run and runtime smoke
  proof.
- Which volume strategy best matches Compose named volumes without relying on
  public Apple CLI volume primitives?
- Can local `build.context` be supported without Docker/OrbStack, and should
  this use Apple `container build`, BuildKit inside LinuxPod, or a separate
  non-Docker builder?
- How stable is LinuxPod API behavior across `apple/containerization` releases?
- What entitlement/signing flow is acceptable for developer installation?

## Efficiency Targets

Use three decision levels so the team does not overclaim. Public Apple CLI
comparison is intentionally not a success level.

### Non-Target: Public CLI Replacement

LinuxPod beating public Apple `container` CLI means only that the lower-level
LinuxPod API is worth investigating. It does not justify a release claim,
replacement claim, or product positioning change.

### Level 1: Docker/OrbStack Viability Gate

LinuxPod is worth further optimization when all are true:

- Backend-shaped fixture runs DB, migrate, seed, API, readiness, logs, status,
  and cleanup in one LinuxPod.
- Backend-shaped LinuxPod cgroup current is within `50%` of Docker/OrbStack.
- Backend-shaped LinuxPod host physical footprint has a reliable measurement
  source and is within `50%` of Docker/OrbStack.
- Startup/readiness p50 is within `50%` of Docker/OrbStack.
- DB block read p50 is no worse than `2x` Docker/OrbStack, unless the absolute
  delta is below `10MiB`.
- Second and later services add process-sized marginal memory, with a target of
  less than `30MiB` per small service in the public fixture.
- Cleanup leaves no adapter-owned runtime state except documented named volumes.
- Failure count is `0` across at least `5` repeated warm-image iterations.

### Level 2: Docker/OrbStack Competitive

LinuxPod is competitive with Docker/OrbStack when all are true:

- Backend-shaped LinuxPod host physical footprint is within `20%` of the
  Docker/OrbStack comparable footprint.
- Backend-shaped LinuxPod cgroup current is within `20%` of Docker/OrbStack.
- Startup/readiness p50 is within `10%` of Docker/OrbStack or faster, and p95
  is not materially worse.
- Completed work per CPU-second is within `10%` of Docker/OrbStack.
- DB data footprint, block read, and block write volume are in the same broad
  range as Docker/OrbStack.
- Failure count is `0` across at least `10` warm-image iterations.

### Level 3: Docker/OrbStack Beating

LinuxPod beats Docker/OrbStack only if all are true:

- Host physical footprint p50 is at least `10%` lower than Docker/OrbStack.
- Backend-shaped cgroup current p50 is at least `10%` lower than Docker/OrbStack.
- Startup/readiness p50 is equal or faster, with p95 and p99 no worse than
  Docker/OrbStack.
- Completed work per CPU-second is at least `10%` better, or equal throughput
  is achieved with at least `10%` lower CPU.
- DB block read p50 and p95 are no worse than Docker/OrbStack. When Docker
  reports near-zero reads, LinuxPod must stay within a small absolute delta
  such as `5MiB`.
- DB block write and persistent data footprint are no worse than Docker/OrbStack
  by more than `10%`.
- Failure count is `0` across at least `20` repeated iterations.

Expected outcome before implementation:

- Public Apple CLI results are no longer decision-making success criteria.
- Matching Docker/OrbStack for multi-service warm backend stacks is plausible
  only if shared LinuxPod lifecycle, warm image/rootfs reuse, volume layout,
  and CPU scheduling reduce the current memory and block-read gaps.
- Beating Docker/OrbStack for single Postgres memory is unlikely without deeper
  LinuxPod/rootfs/kernel tuning or upstream improvements.
- Beating Docker/OrbStack overall is possible only if shared LinuxPod lifecycle,
  warm image/rootfs reuse, lower marginal service overhead, better process
  scheduling, and lower block I/O outweigh Docker/OrbStack's mature shared VM
  and cache behavior.

## Architecture

Add a runtime backend boundary under the existing adapter architecture.

```text
CLI
  -> ComposeInputResolver
  -> ComposeParser
  -> ComposeNormalizer
  -> CompatibilityAnalyzer
  -> PlanBuilder
  -> RuntimeBackend
       -> LinuxPodBackend
       -> AppleContainerCLIBackend
       -> NoopDryRunBackend
```

The backend interface should operate on adapter-owned plan actions, not raw
Compose YAML and not shell strings.

Backend responsibilities:

- report capabilities;
- render dry-run actions;
- create project runtime resources;
- start services and one-off jobs;
- wait for readiness and job completion;
- collect logs and status;
- collect metrics;
- stop and clean up only adapter-owned resources.

LinuxPod-specific responsibilities:

- create one project-scoped LinuxPod VM;
- unpack or reuse image rootfs state;
- add service containers/processes to the pod;
- apply environment, entrypoint, command, mounts, ports, and readiness probes;
- provide service-name connectivity inside the project;
- maintain state under an adapter-owned directory;
- record JSONL evidence for runtime smoke and benchmarks.

## Phases

### Phase 0: Strategy Pivot And Non-Mutating Audit

- [x] Read `AGENTS.md`, `CLAUDE.md`, `README.md`, this plan, the LinuxPod
  evidence note, the public runtime efficiency report, and the current main
  implementation plan.
- [x] Confirm the main implementation plan is marked superseded for its public
  CLI runtime target and that this plan is active in `docs/plans/index.md`.
- [x] Inspect current `apple/containerization` LinuxPod public API, examples,
  and tests without creating runtime resources.
- [x] Record exact API findings in a new note under `docs/plans/notes/` if
  they materially change this plan.
- [x] Run `git diff --check`.

### Phase 1: Runtime-Neutral Adapter Contract

- [x] Create or update the SwiftPM package foundation if it does not already
  exist.
- [x] Define runtime-neutral models for project name, services, jobs, volumes,
  ports, mounts, readiness, cleanup, and diagnostics.
- [x] Define a `RuntimeBackend` protocol that takes the internal plan model and
  returns dry-run actions or execution results.
- [x] Add a `NoopDryRunBackend` first so dry-run output and tests do not depend
  on LinuxPod.
- [x] Add XCTest coverage for dry-run rendering, secret redaction, unsupported
  feature diagnostics, and no-runtime behavior.
- [x] Run `swift test` and `git diff --check`.

### Phase 2: LinuxPod Backend Skeleton

- [x] Add `LinuxPodBackend` behind an explicit runtime flag such as
  `--runtime linuxpod`.
- [x] Require explicit confirmation for any command that creates, starts, stops,
  or deletes LinuxPod resources.
- [x] Keep the existing experiment under `experiments/linuxpod-base-overhead/`
  as evidence, not as production code.
- [x] Implement adapter-owned state paths using names prefixed with
  `cca-linuxpod-`.
- [x] Implement dry-run rendering for LinuxPod lifecycle actions before real
  execution.
- [x] Add tests that verify LinuxPod commands cannot run without approval.
- [x] Run `swift test` and `git diff --check`.

### Phase 3: Image, Rootfs, Volume, And Lifecycle Model

- [x] Implement a public-image-only image/rootfs preparation path.
- [x] Reuse unpacked image/rootfs state when safe and record cache hit/miss in
  JSONL evidence.
- [x] Map Compose named volumes to adapter-owned directories with explicit
  `down --volumes` cleanup behavior.
- [x] Map bind mounts with path validation and broad-mount diagnostics.
- [x] Implement project-scoped LinuxPod create/start/stop/delete lifecycle.
- [x] Add cleanup tests proving only adapter-owned state is removed.
- [x] Run dry-run smoke before any runtime mutation.
- [x] After explicit approval, run one public-image runtime smoke and verify
  cleanup. The first `swift run` attempt lacked
  `com.apple.security.virtualization`; after local signing, the signed runtime
  smoke and cleanup passed. See
  [LinuxPod Phase 3 Dry-run Gate Evidence](notes/2026-06-12-linuxpod-phase-3-dry-run-gate-evidence.md).

### Phase 4: Compose Service Semantics In One Pod

- [x] Implement multiple services in one LinuxPod.
- [x] Implement service-name connectivity through the simplest reliable
  mechanism discovered in Phase 0: start with adapter-managed LinuxPod `Hosts`
  entries, then prove the selected mechanism with dry-run and runtime-approved
  smoke evidence. Runtime-proven: migrate and seed ran `psql -h db` and the
  API readiness connected to `db:5432` through the pod hosts entry in the
  passing signed Phase 4 smoke.
- [x] Implement readiness polling for supported healthchecks.
- [x] Implement one-off job execution and capture exit status/logs. The backend
  preserves action-level job result metadata in `ExecutionResult`, the
  concrete LinuxPod executor reports job exit codes and captures stdout/stderr
  for all containers (in memory plus `runtime/logs/<service>.<stream>.log`),
  and the passing signed Phase 4 smoke recorded migrate/seed exit `0` with
  captured psql output in CLI-written execution JSONL.
- [x] Implement `depends_on` ordering for `service_started`,
  `service_healthy`, and `service_completed_successfully`.
- [ ] Implement `logs`, `status`, `run`, `down`, and `down --volumes` for the
  LinuxPod backend subset. Dry-run coverage exists, action-level execution
  results render through the CLI in text and JSON, `run` plans the project
  runtime, image/rootfs preparation, dependency service readiness, and one-off
  jobs without starting unrelated services, and runtime `up` plus
  `down --volumes` are now proven by the passing Phase 4 smoke and cleanup.
  Cross-invocation runtime `logs`, `status`, and standalone `run` proof still
  requires durable cross-command runtime state.
- [x] Add tests for DB -> migrate -> seed -> API ordering using mock backend
  results.
- [x] Run `swift test` and `git diff --check`.
- [x] Resolve the code-side OCI defaults blocker:
  the LinuxPod executor now resolves image `Entrypoint`, `Cmd`, default `Env`,
  `WorkingDir`, user, and declared volume metadata during
  `prepareImageRootfs`, applies image defaults when a service has no Compose
  command override, merges service environment overrides, and records runtime
  action metadata for process source, arguments, working directory, default
  environment count, and declared volumes.
- [x] Repeat the signed Phase 4 backend-shaped runtime `up` smoke after
  explicit current-task approval. The `VZErrorDomain Code=2` blocker was
  reclassified as sandbox-denied Hypervisor access (the host supports VM
  creation), service log capture exposed the postgres
  `chown: Operation not permitted` failure on the virtiofs named volume, and
  three fixes landed: guest-local ext4 block named volumes without
  `lost+found`, per-container APFS rootfs clones, and planner registration of
  all containers before pod creation. The escalated signed smoke then passed
  end to end (db healthy, migrate/seed exit `0`, api ready) and approved
  `down --volumes` cleanup was reproven. See
  [LinuxPod Phase 4 Dry-run Gate Evidence](notes/2026-06-12-linuxpod-phase-4-dry-run-gate-evidence.md).

### Phase 5: Host Footprint Measurement

- [x] Define a JSONL schema for host footprint evidence that separates
  cgroup/guest memory from host physical memory. See
  [LinuxPod Phase 5 Host Footprint Design](notes/2026-06-12-linuxpod-phase-5-host-footprint-design.md).
- [x] Test host-side sources such as `footprint`, `vmmap -summary`,
  process-tree sampling, `vm_stat` deltas, and in-process `task_info`
  phys footprint via the new `container-compose-footprint-harness` target
  across idle-pod, db-only, full-stack, and scale-test scenarios.
- [x] Reject sources that do not scale with guest workload: the scale test
  grew the guest cgroup by ~`504 MiB` while all four per-process sources
  stayed flat, so `task_info`, `footprint`, `vmmap`, and `ps` RSS were all
  recorded `rejected-not-scaling`. Virtualization.framework guest memory is
  not charged to per-process ledgers on this host.
- [x] Record skipped or blocked evidence when attribution is not reliable:
  `vm-stat-delta` is recorded `blocked` (system-wide attribution), and the
  decision note marks host physical memory comparison `blocked` for Phase 6
  unless a controlled system-wide protocol is approved. See
  [LinuxPod Phase 5 Host Footprint Evidence](notes/2026-06-12-linuxpod-phase-5-host-footprint-evidence.md).
- [x] Update documentation to avoid saying "base VM overhead is lower" unless
  a reliable host-side source proves it; the sweep found only conditional
  hypotheses and the design note encodes the documentation rule.

### Phase 6: Backend-Shaped Public Fixture Benchmark

- [x] Create or reuse a public backend-shaped fixture with DB, migrate, seed,
  API, named volume, readiness, published API port, logs, status, and cleanup.
- [x] Run LinuxPod dry-run evidence first:
  [`20260612T045048Z-phase6-backend-shaped-dry-run.jsonl`](../evidence/linuxpod-compose-runtime/20260612T045048Z-phase6-backend-shaped-dry-run.jsonl).
- [x] After explicit runtime approval, run one LinuxPod smoke iteration:
  [`20260612T045149Z-phase6-smoke.jsonl`](../evidence/linuxpod-phase6-benchmark/20260612T045149Z-phase6-smoke.jsonl).
- [x] If smoke succeeds, run `5` warm-image iterations:
  [`20260612T045331Z-phase6-warm-5.jsonl`](../evidence/linuxpod-phase6-benchmark/20260612T045331Z-phase6-warm-5.jsonl).
- [x] Stop LinuxPod replacement work and record `linuxpod-not-promising` if the
  `5` warm-image iterations miss the Docker/OrbStack Viability Gate by a wide
  margin. The five-iteration run measured `0` failures and clean cleanup, but
  missed the gate on guest cgroup memory (`188.2MiB` p50 vs Docker/OrbStack
  DB+API `86.4MiB`), startup/readiness (`64.83s` p50 vs `12.859s`), and block
  read (`104.5MiB` p50 vs `4.86MiB`). See
  [LinuxPod Phase 6 Benchmark Decision](notes/2026-06-12-linuxpod-phase-6-benchmark-decision.md).
- [x] Do not run `10` iterations because results did not pass the
  Docker/OrbStack Viability Gate and are not near the competitive thresholds.
- [x] Do not run `20` or more iterations because LinuxPod does not appear
  capable of beating Docker/OrbStack on this implementation.
- [x] Capture RAM, CPU, disk footprint, block I/O, startup/readiness, cleanup,
  host footprint, and failure counts for every performed run.
- [x] Compare against
  `docs/evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-report.md`.

### Phase 7: Optimization Pass

Phase 7 is intentionally not started after the Phase 6
`linuxpod-not-promising` decision. Reopen only if the user explicitly approves
a new hypothesis such as reusable warm LinuxPod lifecycle, persistent rootfs
cache strategy, or upstream `apple/containerization` changes.

- [ ] Optimize only after Phase 6 identifies a real bottleneck.
- [ ] Consider warm LinuxPod reuse, image/rootfs reuse, smaller init surface,
  service startup ordering, fewer redundant probes, CPU scheduling profiles,
  cgroup CPU weights/quotas, process affinity or cpuset experiments, and volume
  layout changes.
- [ ] Prioritize optimization work in this order unless evidence says
  otherwise: block-read/rootfs cache path, cgroup/host memory footprint, CPU
  scheduling and completed-work-per-CPU, startup/readiness tail latency, and
  cleanup reliability.
- [ ] Do not tune Postgres configuration in a way that breaks Compose parity
  unless the fixture clearly documents the difference.
- [ ] Re-run the smallest benchmark that proves the optimization changed the
  bottleneck.
- [ ] Keep each optimization backed by before/after evidence against
  Docker/OrbStack, not only against public Apple CLI.

### Phase 8: Decision Report And Main Plan Update

- [x] Write a decision note under `docs/plans/notes/` with one of:
  `linuxpod-primary`, `linuxpod-promising`, `linuxpod-multi-service-only`,
  `linuxpod-blocked`, or `linuxpod-not-promising`. Decision:
  [LinuxPod Phase 6 Benchmark Decision](notes/2026-06-12-linuxpod-phase-6-benchmark-decision.md).
- [x] Update `docs/plans/notes/index.md`.
- [x] Update this plan and `docs/plans/index.md` with the next concrete todo or
  completion state.
- [x] Do not update the superseded main implementation plan; this plan and the
  active index now block further LinuxPod replacement work unless explicitly
  re-approved.
- [ ] Run `swift test` when code exists and `git diff --check` for all plan/doc
  changes.

## Verification Gates

No runtime mutation is allowed before dry-run evidence and explicit user
approval.

Minimum gates:

- `git diff --check` after each documentation phase.
- `swift test` after package or source changes.
- Dry-run output for any action that would create, start, stop, or delete
  LinuxPod resources.
- Before any LinuxPod runtime smoke, run `swift build`,
  `scripts/sign-debug-runtime.sh`, and signed-binary `doctor` to confirm
  `com.apple.security.virtualization` is present. Do not use plain `swift run`
  for runtime-mutating LinuxPod commands.
- JSONL evidence for runtime smoke and benchmarks.
- Cleanup proof showing adapter-owned runtime state was removed or preserved
  only when named volumes are intentionally retained.
- Comparison to the existing Docker/OrbStack baseline. Public Apple CLI
  comparison is optional context and never sufficient for success.

Runtime gates:

- Phase 3 smoke: one public-image LinuxPod run, cleanup verified.
- Phase 4 smoke: at least two services in one LinuxPod with readiness verified.
- Phase 6 smoke: backend-shaped public fixture with DB/job/API behavior.
- Phase 6 repeats: `5`, `10`, or `20+` iterations only when the previous gate
  justifies the added runtime cost.

## Risks And Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| LinuxPod API changes or remains experimental | Backend breaks across releases | Pin tested `apple/containerization` versions, isolate LinuxPod calls, record capability discovery |
| Host VM footprint remains unattributable | Cannot prove base VM memory win | Separate cgroup claims from host claims, use only reliable host sources, keep decision wording conservative |
| LinuxPod cannot match service-name DNS semantics | Backend stacks fail | Implement explicit project-local name mapping or block unsupported cases with clear diagnostics |
| Local builds still require Docker/OrbStack | OrbStackless story remains incomplete | Treat build support as its own gate; evaluate Apple `container build` or BuildKit-in-LinuxPod separately |
| Runtime cleanup removes unrelated files | Data loss | Adapter-owned prefixes, state store, approval gates, tests, no global cleanup |
| Optimizing benchmarks breaks Compose parity | Misleading evidence | Keep fixture behavior public and documented; separate runtime overhead tuning from app-level tuning |
| Docker/OrbStack stays materially better | Product thesis fails for replacement | Stop replacement positioning, keep LinuxPod as optional backend or research path, and keep Docker/OrbStack as the recommended runtime |

## Dependencies And Ownership Boundaries

Owned by this repository:

- Compose parsing and compatibility planning.
- Runtime backend interface.
- LinuxPod backend code.
- Dry-run, diagnostics, redaction, and state management.
- Public fixtures and evidence reports under this repository.

Not owned by this repository:

- Apple `container` CLI internals.
- `apple/containerization` upstream implementation.
- Docker/OrbStack internals.
- Registry credentials and account limits.
- Parent EMSI monorepo submodule pointers.
- Private EMSI application workloads.

## Affected Files And Docs

Expected future implementation files:

- `Package.swift`
- `Sources/ContainerComposeAdapter/...`
- `Tests/ContainerComposeAdapterTests/...`
- `docs/runtime-linuxpod.md`
- `docs/runtime-apple-container.md`
- `docs/evidence/linuxpod-compose-runtime/`
- `docs/plans/notes/<date>-linuxpod-compose-runtime-decision.md`

Current planning files touched by this plan creation or Phase 0 execution:

- `docs/plans/2026-06-12-linuxpod-compose-runtime-backend-plan.md`
- `docs/plans/index.md`
- `docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md`
- `docs/plans/completed/index.md`
- `docs/plans/notes/index.md`
- `docs/plans/notes/2026-06-12-linuxpod-api-audit-evidence.md`

## Rollback And Recovery

If LinuxPod proves blocked or not promising:

- Keep parser, planner, diagnostics, and dry-run contracts because they are
  runtime-neutral.
- Mark this plan `blocked`, `superseded`, or `completed` with a decision note.
- Restore public Apple CLI backend work only as a compatibility/fallback path,
  not as an efficiency claim.
- Keep Docker/OrbStack documented as the reference and fallback until an
  OrbStackless gate passes.

If a runtime smoke leaves owned state behind:

- Do not run global prune or destructive cleanup.
- Identify only `cca-linuxpod-*` state from the run record.
- Stop/delete only adapter-owned LinuxPod resources after explicit approval.
- Record cleanup evidence in JSONL and the decision note.

## Execution Prompt

```text
Continue in <repo-root>.

Execute docs/plans/2026-06-12-linuxpod-compose-runtime-backend-plan.md from Phase 0 through the next documented decision gate.

Before changes, read AGENTS.md, CLAUDE.md, README.md, docs/plans/index.md, docs/plans/2026-06-12-linuxpod-compose-runtime-backend-plan.md, docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md, docs/plans/notes/2026-06-11-linuxpod-base-overhead-spike-evidence.md, docs/plans/notes/2026-06-11-runtime-efficiency-benchmark-evidence.md, and docs/evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-report.md.

Use google-eng-practices plus superpowers:subagent-driven-development or superpowers:executing-plans when available.

Do not create/switch/rename/delete branches. Do not edit the parent EMSI monorepo or update submodule pointers. Do not commit or push unless explicitly requested.

Treat Docker/OrbStack-backed Docker Compose as the target to match or beat. Treat LinuxPod as the primary runtime efficiency experiment only while it is moving toward Docker/OrbStack-competitive metrics. Treat public Apple container CLI as fallback/capability-probe/negative-control only; beating it is not a success criterion. Preserve parser/planner/dry-run separation. Do not run private EMSI workloads, registry login, prune, global cleanup, or destructive host changes.

Do not run commands that create, start, stop, or delete LinuxPod/runtime resources until dry-run evidence exists and explicit runtime approval is given in the current task. Runtime resources must use adapter-owned cca-linuxpod-* names/state only.

After each phase, run the relevant verification: git diff --check for docs/plan changes, swift test once package/source files exist, dry-run smoke before runtime mutation, and JSONL evidence plus cleanup proof for any approved runtime run. Update docs/plans/index.md so it contains only the next concrete todo for each active plan, and update notes under docs/plans/notes/ when evidence changes the runtime strategy.
```
