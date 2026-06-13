# Container Compose Adapter

Experimental Apple-native local development orchestrator for Compose and
Kubernetes-defined backend stacks on macOS.

Container Compose Adapter is evolving into an experimental Apple-native local
development orchestrator for macOS. It compiles Docker Compose files and, in a
future phase, a local-development subset of Kubernetes manifests into a shared
`LocalDevProject` graph, then plans that graph for an Apple-native runtime.

The primary runtime research target is `apple/containerization` LinuxPod: one
project-scoped LinuxPod runtime with cached images/rootfs, reusable named
volumes, service DNS, deterministic host ports, healthchecks, one-off jobs,
logs, status, diagnostics, and safe adapter-owned cleanup. The LinuxPod runtime
path is experimental/research-grade, but it is the main Apple-native runtime
surface this repository is studying.

Apple `container` CLI is a secondary Apple surface for capability probes,
upstream behavior comparison, simple workload reference runs, and upstream
reproduction helpers. Lower-level `LinuxContainer` / `ContainerManager` APIs
are research surfaces for rootfs, writable-layer, and image/content-store
experiments. Apple `container machine` persistence ideas belong in separate
research, not the current implementation path.

Docker Desktop, OrbStack, Colima, Podman, Lima, and Rancher Desktop are
comparison baselines and optimization references only. They are not
implementation targets, and this repository does not add Docker-compatible
backend switching.

The project is not a Docker Engine clone and is not a full Kubernetes
distribution. Kubernetes support means planned local-development manifest
translation into `LocalDevProject`, not a cluster control plane, controllers,
operators, scheduler, kubelet, or production Kubernetes conformance.

Apple-native runtime primitives do not automatically imply lower host RAM use.
Any memory claim needs reliable host-level evidence. Current benchmark schemas
separate guest cgroup signals from host physical memory and mark host memory
comparison blocked until a reliable attribution source exists.

This project is not affiliated with Apple or Docker.

## Not Another Container Compose Wrapper

This project is not intended to duplicate existing Apple Container Compose wrappers such as [`Mcrich23/Container-Compose`](https://github.com/Mcrich23/Container-Compose).
Existing tools primarily map Docker Compose files onto Apple `container`
CLI/API behavior. That is a useful layer, and it should remain an external
comparison point rather than becoming this repository's implementation target.

Container Compose Adapter investigates whether `apple/containerization`
LinuxPod can become a high-performance Apple-native project runtime for
backend-shaped local development workloads, using a persistent LinuxPod project runtime, image/rootfs/initfs caches, reusable Linux-side ext4 named volumes,
service DNS, deterministic ports, healthchecks, one-off jobs, logs/status/exec,
a recovery/event model, metrics, diagnostics, and safe adapter-owned cleanup.

Docker Compose files are the primary input. Kubernetes is a local-development input subset for rendered manifests, not a full Kubernetes distribution. Docker
Desktop, OrbStack, Colima, Podman, Lima, Rancher Desktop, and Microsoft WSL
container are comparison baselines or optimization references only. Microsoft WSL container is an optimization reference only, not a backend target. This
project does not claim host RAM savings without reliable host-level evidence.

## Product Direction

Target architecture:

```text
Docker Compose YAML
        -> ComposeFrontend
        -> LocalDevProject IR
        -> AppleNativePlanner
        -> LinuxPodProjectRuntime
```

Future Kubernetes path:

```text
Kubernetes YAML / Helm template output / Kustomize output
        -> KubernetesSubsetFrontend
        -> LocalDevProject IR
        -> AppleNativePlanner
        -> LinuxPodProjectRuntime
```

Useful first-class behavior for local development includes service names,
environment interpolation, port publishing, bind mounts, named volumes,
profiles, one-off jobs, logs, health readiness, dependency order, and cleanup
behavior. Unsupported Compose or Kubernetes features should produce clear
diagnostics instead of surprising runtime behavior.

## Current Status

The current SwiftPM implementation is intentionally small and gate-driven:

- Runtime-neutral planning, dry-run output, diagnostics, redaction, safety
  checks, `LocalDevProject` IR scaffolding, and benchmark metadata live in the
  core library.
- `NoopDryRunBackend` renders plans without runtime side effects.
- `LinuxPodBackend` is available only through explicit runtime selection and
  requires a current-task approval token for commands that create, start, stop,
  or delete runtime resources.
- Docker/OrbStack-backed Docker Compose remains a compatibility and efficiency
  baseline only. It is not a backend implementation path.

The LinuxPod path currently uses the pinned
`apple/containerization` package version `0.33.4`.

This repository has not implemented product-ready persistent LinuxPod hotplug,
writable-layer support, or full Compose parsing yet. Those are planned or
research items, not current behavior.

## Research Status

As of 2026-06-13, productization is paused and the Apple-native runtime work is
preserved as a research checkpoint.

The evidence is mixed. Apple `container` remains promising for simple
workloads, and LinuxPod can run the backend-shaped fixture, but cold/fresh
backend-shaped runtime remains slow. Image-store seeding helps substantially but
does not solve rootfs/initfs/volume/pod lifecycle cost by itself. Rootfs cache
hits are not enough while the runtime still performs full rootfs materialization
copies into project and per-container ext4 images. Warm ext4 named volumes help
block-write behavior.

LinuxPod hotplug is not a product path here: the default VZ provider is missing,
a diagnostic custom provider can receive the call, public ext4/block rootfs
hotplug still does not complete, and the second container does not start.

Stage 10A clonefile/COW diagnostics are promising because `clonefile` was
strongly verified, byte-for-byte rootfs copy work was avoided, and cleanup was
clean. That remains diagnostic evidence only: `clonefile` is not the default,
the evidence records `productReady=false`, and no Docker/OrbStack parity,
Docker/OrbStack gate, host RAM, or energy savings claim is made.

Stage 10B was attempted as a guarded final decision experiment comparing
full-copy rootfs materialization with the `auto`/`clonefile` candidate in the
real backend-shaped LinuxPod runtime. The comparison stalled during the
full-copy leg before any valid Stage 10B JSONL comparison evidence was
produced. Cleanup was checked clean, but `up`/readiness, rootfs preparation,
project/container materialization, block I/O, healthcheck, job, and volume
comparison metrics were not measured as a valid fullCopy versus clonefile
record.

Do not recommend Stage 10C repeated warm benchmarking from the current
evidence. Productization remains paused, `clonefile` remains non-default, and
no Docker/OrbStack gate, Docker/OrbStack parity, host RAM, or energy savings
claim is made.

## Design Docs

- [Apple-native local development orchestrator](docs/apple-native-local-dev-orchestrator.md)
- [LocalDevProject IR](docs/localdevproject-ir.md)
- [LinuxPod persistent project runtime](docs/linuxpod-persistent-project-runtime.md)
- [Kubernetes input subset](docs/kubernetes-input-subset.md)
- [Benchmark and metrics plan](docs/benchmark-and-metrics-plan.md)
- [Competitive context: Container-Compose](docs/competitive-context/container-compose.md)
- [Optimization reference: WSL container](docs/optimization-references/wsl-container.md)

## Build And Test

Run from the repository root:

```bash
swift test
```

## Local LinuxPod Signing

LinuxPod runtime execution uses Virtualization.framework. A binary launched
through plain `swift run` does not carry the required entitlement, so runtime
smoke runs must use a signed executable. Run the signing helper after each
`swift build` or `swift test` that may replace the debug binary:

```bash
swift build
scripts/sign-debug-runtime.sh
```

Verify the entitlement before running runtime-mutating commands:

```bash
codesign -d --entitlements :- .build/arm64-apple-macosx/debug/container-compose-adapter
```

## Dry Run

Render the public-image LinuxPod smoke plan without creating runtime resources:

```bash
swift run container-compose-adapter \
  --runtime linuxpod \
  --dry-run \
  --sample public-smoke \
  --project-name phase3-public-smoke \
  --format text \
  --evidence-jsonl docs/evidence/linuxpod-compose-runtime/phase3-public-smoke-dry-run.jsonl \
  up
```

Use `--sample backend-shaped` to render the public DB -> migrate -> seed -> API
fixture used by the LinuxPod one-pod Phase 4 gate.

Use `--compose-file <path>` to derive the runtime plan from a Compose file
through the Compose frontend and Apple-native planner instead of a built-in
sample plan. This is the fixture-derived path required by the Stage 5
backend-shaped smoke gate. `--compose-file` and `--sample` are mutually
exclusive.

The generated plan uses adapter-owned names prefixed with `cca-linuxpod-`,
redacts likely secret environment values, and records JSONL evidence. Dry-run
output is required before any LinuxPod runtime mutation.

The `--evidence-jsonl` flag appends dry-run evidence in `--dry-run` mode and
runtime execution evidence after a successful approved runtime command.
Approved runtime execution output includes action-level results such as job
exit codes, captured log summaries, cleanup actions, and status metadata when
the selected backend provides them. Use `--format json` for the machine-readable
execution result.

## Stage 4 Microbenchmark Plan

Emit the Stage 4 rootfs, named-volume, and healthcheck microbenchmark plan as
JSONL without creating runtime, cache, or project state:

```bash
swift run container-compose-stage4-microbenchmarks \
  --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml \
  --project-name backend-shaped \
  --evidence-jsonl docs/evidence/linuxpod-stage4-microbenchmarks/stage4-plan.jsonl \
  --operation-evidence-jsonl docs/evidence/linuxpod-stage4-microbenchmarks/stage4-operations.jsonl \
  --validate-evidence
```

This command records only the no-runtime plan shape. Actual rootfs, volume, or
healthcheck measurement is runtime-mutating work and still requires explicit
current-task approval before it can run.

The core library also defines the Stage 4 measurement JSONL record and
approval-gated runner path. `LinuxPodStage4MicrobenchmarkRunner` translates
rootfs, volume, and healthcheck probes into scoped measurement operations and
wraps an injected operation executor's result as measurement JSONL. It can also
render the approval-gated measurement operations that a future runtime executor
would execute, including mutation scope and cleanup expectations, without
running them. `Stage4MicrobenchmarkEvidenceValidator` validates no-runtime plan
and operation evidence shape, approval requirements, mutation scope, global
mutation safety, cleanup expectations, required rootfs/volume/healthcheck probe
coverage, and probe identity fields; the command can run that validator with
`--validate-evidence`. The same validator also checks future measurement JSONL
against the planned probes, required cold/warm metadata, image cache hit/miss
for image-backed probes, initfs/kernel/vminit runtime context, planned runtime
target name, timing, block I/O, guest cgroup metrics, cleanup result, and
structured cleanup proof with stale-state counts, rootfs cache state, initfs
cache-state consistency, named-volume lifecycle state, matching
`apple/containerization` metadata, and blocked host-memory attribution. No
concrete runtime operation executor is configured by default.
When runtime-approved measurements exist, pass
`--measurement-evidence-jsonl <path>` together with `--validate-evidence` to
validate the measurement JSONL against the emitted plan. The measurement flag is
validation-only; the Stage 4 command rejects it without `--validate-evidence`
and never treats it as approval to run measurements.

## Stage 5 Backend-shaped Smoke Dry Run

Emit the Stage 5 backend-shaped product-smoke evidence from the public Compose
fixture without creating, starting, stopping, or deleting runtime resources:

```bash
swift run container-compose-stage5-backend-smoke \
  --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml \
  --project-name backend-shaped \
  --evidence-jsonl docs/evidence/linuxpod-stage5-backend-smoke/stage5-dry-run.jsonl \
  --validate-evidence
```

The command renders and validates the fixture-derived LinuxPod dry-run surfaces
for `up`, `logs`, `status`, `run`, and `down --volumes`. The JSONL record covers
Postgres, the `db-data` named volume, migrate and seed jobs, the API service,
service readiness/healthchecks, deterministic host ports, adapter-managed
service hosts, and cleanup proof. This command is no-runtime only and rejects
runtime approval tokens; a signed Stage 5 runtime smoke is a separate
current-task approval-gated action.

## Phase 6 Benchmark Harness

The Phase 6 backend-shaped LinuxPod benchmark uses a signed executable so the
runtime run and cleanup happen inside one entitled process:

```bash
swift build --product container-compose-phase6-benchmark
scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark
.build/arm64-apple-macosx/debug/container-compose-phase6-benchmark \
  --iterations 5 \
  --project-prefix phase6-backend \
  --run-label phase6-cold \
  --lifecycle cold \
  --evidence-jsonl docs/evidence/linuxpod-phase6-benchmark/phase6-cold.jsonl \
  --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
```

The harness records JSONL iteration and summary rows with guest cgroup memory,
CPU use, block I/O, timing, failure count, cleanup state, and host physical
memory status. Host physical memory remains `blocked` until a reliable
host-side attribution source exists.

Stage 6 additions: `--compose-file <path>` runs the fixture-derived
ComposeFrontend plan instead of the built-in sample. `--lifecycle` accepts:

- `cold`: no pre-seeded image store and fresh rootfs/initfs/volume/pod state.
- `image-store-seeded-fresh-runtime`: copy a prepared image store into each
  fresh project runtime before `up`; rootfs/initfs/volume/pod state is still
  cold.
- `persistent-warm-project-runtime`: reserved for a future experiment where the
  project LinuxPod, rootfs/initfs cache, named volume, and service lifecycle are
  actually reused.

`--seed-image-store <path>` copies a pre-pulled image store into each
iteration's fresh project runtime so the benchmark can isolate image-store
availability from registry pulls. `--prepare-seed-image-store` prepares that
seed store before measured iterations by pulling the LinuxPod init image plus
the plan's `linux/arm64` service images once; if `--seed-image-store` is
omitted, the prepared seed path is used for the measured iterations. Seed
stores are local benchmark cache state, not evidence artifacts. By default they
must live under
`.container-compose-adapter/benchmark-seed-image-stores/` and contain the
`.container-compose-adapter-seed-image-store` sentinel; pass
`--allow-external-seed-image-store` only for explicitly reviewed external
paths.
`--docker-hub-mirror <host-or-prefix>` rewrites Docker Hub official image
references such as `postgres:16-alpine`, `docker.io/postgres:16-alpine`, and
`docker.io/library/postgres:16-alpine` to the mirror prefix, for example
`mirror.gcr.io/library/postgres:16-alpine`, without changing non-Docker Hub or
namespaced Docker Hub image references.

For Stage 6 rate-limit mitigation, use the verified public mirror and prepare
the image-store seed outside the measured iterations:

```bash
.build/arm64-apple-macosx/debug/container-compose-phase6-benchmark \
  --iterations 5 \
  --project-prefix stage6-backend \
  --run-label stage6-seeded-image-store \
  --lifecycle image-store-seeded-fresh-runtime \
  --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml \
  --docker-hub-mirror mirror.gcr.io \
  --prepare-seed-image-store .container-compose-adapter/benchmark-seed-image-stores/stage6-arm64 \
  --evidence-jsonl docs/evidence/linuxpod-stage6-benchmark/stage6-seeded-image-store.jsonl \
  --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
```

Seeding is a benchmark harness step, not a product persistent-cache feature.
Repeated cold runs pull on every iteration because adapter state is
per-project, so public registry throttling can still affect cold batches; the
evidence records such failures as registry throttling, not runtime failures.
The current Stage 6 harness marks localhost host-port reachability and
completed requests per load window as `notMeasured`; it proves guest-side
readiness/jobs/cleanup only until host port publishing is implemented and
probed from macOS.

## Kubernetes Input Subset

Rendered Kubernetes YAML (kubectl/Helm/Kustomize output) can drive the same
planner and dry-run surfaces through `--k8s-file`:

```bash
swift run container-compose-adapter \
  --runtime linuxpod \
  --dry-run \
  --k8s-file docs/evidence/fixtures/backend-shaped/k8s.yaml \
  -p backend-shaped \
  up
```

The `KubernetesSubsetFrontend` translates Deployment, StatefulSet, Service,
ConfigMap, Secret, Job, PersistentVolumeClaim, Ingress, and Namespace documents
into `LocalDevProject`. `docs/kubernetes-input-subset.md` documents the
supported subset, the `cca.local/*` annotations (deterministic host ports,
dependency ordering, profiles, ignore), the expected render style, and the
explicit non-goals. Kubernetes support means local-development manifest
translation only; it is not a cluster, controller, or operator runtime. The
backend-shaped Kubernetes fixture produces the same runtime plan as the
Compose fixture, which is verified by tests.

## Runtime Mutation

Commands that create, start, stop, or delete LinuxPod/runtime resources require
all of the following:

- explicit approval in the current task;
- the runtime flag `--runtime linuxpod`;
- the approval token `I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION`;
- adapter-owned `cca-linuxpod-*` resource names and state only.

Do not use this project for private workloads, registry login, Keychain
mutation, Docker Hub credential changes, global prune/cleanup, host DNS
mutation, or destructive host changes.

Cleanup only touches adapter-owned paths. `down` preserves named volumes by
default, and `down --volumes` may delete only adapter-owned project volumes.

## License

Copyright (C) 2026 Burak Karahan

Container Compose Adapter is free software licensed under the GNU Affero
General Public License v3.0 or later. See [LICENSE](LICENSE) for the full
license text.

SPDX-License-Identifier: AGPL-3.0-or-later
