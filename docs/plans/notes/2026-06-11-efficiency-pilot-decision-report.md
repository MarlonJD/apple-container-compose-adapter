# Efficiency Pilot Decision Report

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../completed/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** Decision report for pilot Phases 1 through 5 after refreshed Phase 0 evidence.

## Recommendation

Proceed narrower, but proceed with more confidence than the earlier skipped-only report allowed.

Start the main Container Compose Adapter implementation with the public Apple `container` CLI path: package/CLI scaffold, `doctor`, parser, normalizer, compatibility diagnostics, execution plan, redaction, dry-run rendering, runtime command rendering tests, then a carefully gated runtime executor.

Do not claim full OrbStackless backend readiness or shared-runtime parity yet. Simple-web is viable and cached Apple startup is fast. Backend-shaped work is possible, but exact Compose parity needs adapter-owned fixes for service discovery, idempotency, health polling, and named-volume behavior.

## Evidence Summary

| Phase | Evidence | Status | Report finding |
| --- | --- | --- | --- |
| 0 | [Phase 0 Capability Discovery Evidence](2026-06-11-phase-0-capability-discovery-evidence.md) | `measured` for no-side-effect probes | Docker/OrbStack baseline context is available. Apple `container` CLI `1.0.0` is installed, but its apiserver is stopped/unregistered. |
| 1 | [Pilot Phase 1 Harness Design](2026-06-11-pilot-phase-1-harness-design.md) | `measured` as design evidence | Evidence schema, command wrapper contract, redaction, snapshots, and dry-run gates are defined before runtime mutation. |
| 2 | [Pilot Phase 2 Docker Baseline Evidence](2026-06-11-pilot-phase-2-docker-baseline-evidence.md) | `measured` | Docker/OrbStack runs both public fixtures successfully. Backend required explicit `DOCKER_DEFAULT_PLATFORM=linux/arm64` because the shell default was `linux/amd64`. |
| 3 | [Pilot Phase 3 Apple Container Evidence](2026-06-11-pilot-phase-3-apple-container-evidence.md) | `measured`, `measured-with-workarounds` | Apple `container` runs simple-web successfully after runtime setup. Backend-shaped work runs only with PGDATA and IP-based service targeting workarounds. |
| 4 | [Pilot Phase 4 Shared Runtime Feasibility](2026-06-11-pilot-phase-4-shared-runtime-feasibility.md) | `measured` for docs/help/source inspection | Apple `container` CLI has no shared-runtime command. Lower-level `containerization` `LinuxPod` exists and is possible but out of scope for the first adapter path. |

## Runtime Measurement Result

Runtime measurements are available for public fixtures, with setup caveats.

| Workload | Docker/OrbStack baseline | Apple `container` native path | Comparison |
| --- | --- | --- | --- |
| `simple-web` | Cold `up --wait` `19.41s` with image pull; warm `up --wait` `5.82s`; repeated running `up` `0.64s`; memory snapshot `18.5MiB`. | First successful post-kernel run `37.31s` with init image setup; cached warm run `0.93s`; readiness `0.01s`; memory snapshot `14.32MiB`. | Apple cached simple-web startup is faster and uses slightly less measured container memory, but first-run setup is heavier because kernel/init image setup must be paid once. |
| `backend-shaped` | Cold `up --wait` `12.93s`; warm `up --wait` `12.84s`; DB/API memory snapshots `22.17MiB`/`27.5MiB`; service-name `db`, jobs, volume persistence, logs/status, cleanup all worked. | DB first image run `51.66s` then failed on direct named-volume mount; workaround DB run `0.88s`, API run `15.97s`, readiness `0.04s`; DB/API memory snapshots `191.01MiB`/`31.03MiB`; volume persistence worked with PGDATA workaround; service-name DNS did not. | Apple backend is not Compose-parity yet. The per-container VM memory allocation is 1GiB each by default and DB memory was much higher than Docker. Adapter work is needed before claiming backend readiness. |

The project may say simple public web workloads are promising on cached Apple `container` runs. It must not yet say backend-shaped Compose stacks are faster, lighter, or ready to replace OrbStack.

## Follow-up Runtime Efficiency Benchmark

After this decision report, repeated cached-image benchmarks were added in
[Runtime Efficiency Benchmark Evidence](2026-06-11-runtime-efficiency-benchmark-evidence.md).
The follow-up evidence tightens the recommendation: proceed only with the
narrow dry-run-first adapter foundation and do not claim that Apple `container`
is broadly more efficient than Docker/OrbStack.

Key follow-up findings:

- Apple `container` simple-web startup is much faster at p50, but the load loop
  completed fewer HTTP requests and recorded timeout/error samples.
- Apple `container` DB/backend runtime and cgroup memory are much higher than
  Docker/OrbStack, while Postgres process RSS and DB disk footprint are
  effectively the same.
- Apple DB block-read I/O is substantially higher in the measured DB workloads.
- Backend-shaped Apple measurements are still workaround measurements, not
  Compose parity.

## Shared-runtime Finding

The shared-runtime finding has two layers:

- Apple `container` CLI: unsupported. Local help and official CLI source expose container, image/build, machine, network, volume, and system commands, but no Compose/pod/shared-runtime command.
- Apple `containerization` package: possible but out of scope. `LinuxPod` supports a pod VM with multiple container root filesystems/processes, shared pod volumes, per-container lifecycle calls, exec, stats, and stop. It is not exposed by the CLI and would require a separate Swift-package-level adapter mode with its own image/rootfs, network, DNS, logs, volume, health, and cleanup work.

`container machine` remains a useful persistent Linux environment, not a Compose-equivalent shared runtime for isolated OCI services.

This is a delegation finding, not a product-goal finding: Container Compose Adapter still owns the Compose-style behavior. The pilot found that the public Apple `container` CLI does not already provide a native Compose/pod primitive that the project can simply wrap.

## Blockers

- Apple `container` required one-time setup: `container system start`, recommended kernel install, and init image fetch.
- Same-name repeated `container run` is not idempotent; adapter `up` must inspect/reuse/recreate resources deliberately.
- Apple named volumes can expose `lost+found` at the mount root; Postgres needs a `PGDATA` subdirectory or a targeted diagnostic/workaround.
- Apple user-created network did not provide Compose service-name DNS for `db`; adapter-owned service discovery or hosts/DNS strategy is required.
- Apple backend per-container defaults allocate `1024 MB` per container; resource flags should be planned and benchmarked.
- `LinuxPod` is source/API evidence only; no prototype or benchmark was run.

## Main Plan Update

The main implementation plan should proceed with the narrow Apple `container` CLI path:

1. Implement the no-side-effect CLI and `doctor` foundation.
2. Implement structured Compose parsing and compatibility diagnostics.
3. Implement execution planning and dry-run rendering.
4. Implement runtime command rendering to Apple `container` argv arrays with tests.
5. Add runtime executor only after dry-run tests, then implement simple-web first.
6. Add backend support only with explicit diagnostics/workarounds for named volumes, service discovery, resource sizing, health polling, one-off job capture, and idempotency.

## Next Concrete Todo

Start implementation Phase 0 of the main plan: create the minimal SwiftPM/CLI scaffold and no-side-effect `doctor` command with missing/stopped runtime diagnostics, installed-kernel detection, and tests.

## Runtime Commands Run After Approval

The following command classes were run after explicit follow-up approval:

- Docker/OrbStack: `docker compose up`, `docker compose run`, `docker compose down`, `docker compose down --volumes`, `docker pull --platform linux/arm64`.
- Apple `container`: `container system start`, `container system kernel set --recommended`, `container run`, `container exec`, `container network create/delete`, `container volume create/delete`, `container stop`, `container delete`, and `container system stop`.

## Commands Not Run

No `container build`, Docker build, registry login, prune, or private EMSI workload command was run.

## Verification

- `git diff --check` passed after Phase 1 documentation updates.
- `git diff --check` passed after Phase 2 fixture/baseline updates.
- `git diff --check` passed after Phase 3 Apple command mapping updates.
- `git diff --check` passed after Phase 4 shared-runtime updates.
- `git diff --check` passed after Phase 5 decision/index/main-plan updates.
- `docker compose -f docs/evidence/fixtures/simple-web/compose.yaml config` passed without starting containers.
- `docker compose -f docs/evidence/fixtures/backend-shaped/compose.yaml config` passed without starting containers.
- A trailing-whitespace scan over new evidence files passed.
- Docker/OrbStack runtime measurements were run and cleaned up; no `cca-pilot-*` Docker containers, networks, or volumes remained.
- Apple `container` runtime measurements were run and cleaned up; no pilot Apple containers, user-created networks, or named volumes remained.
- `container system stop` returned the apiserver to `not running and not registered with launchd`.

## Plan Lifecycle

The pilot plan is complete. Move it to `docs/plans/completed/`, record it in the completed index, and use the main implementation plan for the next dry-run-first development step.
