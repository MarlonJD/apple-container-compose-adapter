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
`apple/containerization` package version `0.26.5`.

This repository has not implemented persistent LinuxPod hotplug, rootfs-cache
reuse, writable-layer support, Kubernetes input parsing, or full Compose
parsing yet. Those are planned or research items, not current behavior.

## Design Docs

- [Apple-native local development orchestrator](docs/apple-native-local-dev-orchestrator.md)
- [LocalDevProject IR](docs/localdevproject-ir.md)
- [LinuxPod persistent project runtime](docs/linuxpod-persistent-project-runtime.md)
- [Kubernetes input subset](docs/kubernetes-input-subset.md)
- [Benchmark and metrics plan](docs/benchmark-and-metrics-plan.md)

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

The generated plan uses adapter-owned names prefixed with `cca-linuxpod-`,
redacts likely secret environment values, and records JSONL evidence. Dry-run
output is required before any LinuxPod runtime mutation.

The `--evidence-jsonl` flag appends dry-run evidence in `--dry-run` mode and
runtime execution evidence after a successful approved runtime command.
Approved runtime execution output includes action-level results such as job
exit codes, captured log summaries, cleanup actions, and status metadata when
the selected backend provides them. Use `--format json` for the machine-readable
execution result.

## Phase 6 Benchmark Harness

The Phase 6 backend-shaped LinuxPod benchmark uses a signed executable so the
runtime run and cleanup happen inside one entitled process:

```bash
swift build --product container-compose-phase6-benchmark
scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark
.build/arm64-apple-macosx/debug/container-compose-phase6-benchmark \
  --iterations 5 \
  --project-prefix phase6-backend \
  --run-label phase6-warm \
  --evidence-jsonl docs/evidence/linuxpod-phase6-benchmark/phase6-warm.jsonl \
  --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
```

The harness records JSONL iteration and summary rows with guest cgroup memory,
CPU use, block I/O, timing, failure count, cleanup state, and host physical
memory status. Host physical memory remains `blocked` until a reliable
host-side attribution source exists.

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
