# LinuxPod Base Overhead Spike

This isolated SwiftPM package checks whether a direct `apple/containerization`
`LinuxPod` measurement spike is viable before the main Container Compose Adapter
implementation grows a shared-runtime backend.

The package is decision evidence, not product code.

## Source Feasibility

Inspected official source under
`/private/tmp/apple-container-source-check/containerization-main`:

- `Sources/Containerization/LinuxPod.swift`
- `Sources/Integration/PodTests.swift`
- `examples/ctr-example/Package.swift`
- `examples/ctr-example/Sources/ctr-example/main.swift`

Findings:

- `LinuxPod` is an experimental public API that creates one VM and can add
  multiple container root filesystems/processes that share pod CPU, memory, and
  network resources.
- `LinuxPod.statistics()` exposes process, memory, CPU, block I/O, network, and
  memory event categories through `ContainerStatistics`.
- Integration tests show multiple containers, exec, stats, per-container limits,
  filesystem isolation, optional shared PID namespace, and cleanup through
  `pod.stop()`.
- Real runtime measurement requires kernel/initfs resolution, image
  pull/unpack/rootfs creation, VM/network setup, and cleanup. Those operations
  mutate local runtime or experiment state and are approval-gated.

The package pins `apple/containerization` exact version `0.26.5`, matching the
official example dependency inspected for the spike. `Package.resolved` records
the resolved revision after `swift build`.

## Dry-run Commands

Run from this directory:

```bash
swift build
swift run linuxpod-base-overhead --mode idle-pod --iterations 1 --dry-run --output ../../docs/evidence/linuxpod-base-overhead/<timestamp>-linuxpod-base-overhead-raw.jsonl
swift run linuxpod-base-overhead --mode postgres-only --iterations 1 --dry-run --output ../../docs/evidence/linuxpod-base-overhead/<timestamp>-linuxpod-base-overhead-raw.jsonl
swift run linuxpod-base-overhead --mode postgres-api --iterations 1 --dry-run --output ../../docs/evidence/linuxpod-base-overhead/<timestamp>-linuxpod-base-overhead-raw.jsonl
```

Each dry-run prints planned actions and writes JSONL records without creating
pods, networks, volumes, rootfs files, images, registry sessions, or Apple
`container` runtime state.

Image references default to Docker Hub for Alpine and Postgres plus the official
`ghcr.io/apple/containerization/vminit` image. Use explicit overrides when a
login-free public mirror is required for a controlled spike:

```bash
linuxpod-base-overhead \
  --mode postgres-api \
  --iterations 1 \
  --dry-run \
  --alpine-reference mirror.gcr.io/library/alpine:3.20 \
  --postgres-reference mirror.gcr.io/library/postgres:16-alpine
```

## JSONL Schema

Each record uses `schemaVersion: linuxpod-base-overhead/v1` and includes:

- `recordType`
- `scenario`
- `runtimeBackend`
- `source`
- `iteration`
- `iterationsPlanned`
- `status`
- `statusReason`
- `approvalGate`
- `plannedActions`
- `metrics`
- `cleanup`
- `redaction`

Metric fields are present even when null so runtime evidence can be compared
with the Docker/OrbStack and Apple `container` CLI baseline:

- setup/create/readiness/load/stop/delete timings;
- process RSS and high-water RSS;
- cgroup memory current, peak, and limit;
- host runtime RSS when a reliable process can be identified;
- DB data footprint;
- block read/write bytes;
- CPU percent;
- completed work and error counts.

`hostRuntimeRSSBytes` is sampled from the signed runner process when present.
It is useful as a host-side observation, but it is not a proven VM physical
footprint because macOS Virtualization memory may not be fully represented by
the runner process RSS.

## Statuses

Runtime measurement statuses:

- `measured`
- `measured-with-limitations`
- `skipped-runtime-unavailable`
- `blocked-api`
- `blocked-runtime`
- `failed-cleanup`

Dry-run records use `planned-dry-run` as a pre-runtime planning status.

## Redaction

The spike redacts secret-looking fields whose keys include:

- `PASSWORD`
- `TOKEN`
- `SECRET`
- `KEY`
- `CREDENTIAL`
- `PRIVATE`
- `AUTH`
- `SESSION`
- `DATABASE_URL`

Dry-run and future failure summaries must not print generated passwords,
connection URLs, registry credentials, or host paths outside the experiment
scope.

## Cleanup Rules

Any future runtime run must use only resources with the
`cca-linuxpod-spike-*` prefix and must verify cleanup before continuing:

- stop the owned LinuxPod;
- release owned network resources;
- delete owned rootfs/state files;
- verify no owned runtime state remains;
- record cleanup status in JSONL.

Do not run prune commands, registry login, private workloads, parent monorepo
edits, global Apple `container` cleanup, global Docker cleanup, or destructive
host changes.

## Approval Gate

Commands that create, start, stop, or delete LinuxPod/runtime resources require
explicit owner approval for the exact command set before execution. Without that
approval, runtime smoke and repeat measurements are recorded as skipped/blocked
evidence.
