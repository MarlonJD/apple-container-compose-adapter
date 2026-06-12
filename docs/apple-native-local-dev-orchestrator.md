# Apple-native Local Development Orchestrator

## Objective

Container Compose Adapter is evolving from a Compose-shaped runtime adapter into
an experimental Apple-native local development orchestrator for macOS.

The orchestrator should translate local-development intent into a shared
`LocalDevProject` graph and then plan the closest safe execution model on
Apple-native runtime primitives.

Primary input:

- Docker Compose files for local backend stacks.

Planned input:

- A local-development subset of Kubernetes manifests, including rendered Helm
  or Kustomize output.

Primary runtime research target:

- `apple/containerization` LinuxPod.

Product decision:

- Apple-native local-dev orchestrator.
- Core IR: `LocalDevProject`.
- Primary input: Docker Compose.
- Future input: Kubernetes local-development subset.

Non-goals:

- simple `container-compose` clone;
- Docker Engine clone;
- full Kubernetes distribution;
- Docker-compatible backend;
- Apple `container` CLI wrapper positioning.

## Architecture

Compose path:

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

`LocalDevProject` is the compatibility boundary. Frontends translate input
formats into local-development intent; the planner turns that intent into
runtime-neutral actions; the LinuxPod backend executes only approved,
adapter-owned actions.

## Product Thesis

The project is valuable if it proves this model:

- Docker Engine is not required for the supported local-development subset.
- One project maps to one explicit Apple-native project runtime.
- Compose and Kubernetes input formats converge into the same graph.
- Cold startup is measurable, and warm development loops can reuse runtime
  state, images/rootfs, and volumes.
- Diagnostics explain unsupported features instead of ignoring them.
- Cleanup is safe because it is scoped to adapter-owned state.

This is not a Docker Engine clone. It is not a full Kubernetes distribution.
It is a macOS-first local development orchestrator.

## Runtime Hierarchy

`apple/containerization` LinuxPod is the primary research target. It is where
the project should test one project = one persistent LinuxPod, service DNS,
ports, healthchecks, jobs, logs, status, exec, volumes, and safe cleanup.

Apple `container` CLI is secondary. Use it for:

- capability probes;
- upstream behavior comparison;
- simple workload reference runs;
- upstream issue and pull request reproduction helpers.

`LinuxContainer` / `ContainerManager` are lower-level research surfaces for:

- rootfs microbenchmarks;
- writable layer experiments;
- image/content store experiments.

Apple `container machine` persistence ideas are separate research. Do not make
that the main implementation path in this first scope.

Docker Desktop, OrbStack, Colima, Podman, Lima, and Rancher Desktop are
comparison baselines and optimization references only. They are not
implementation targets and should not be added as Docker-compatible backends.

`Mcrich23/Container-Compose` is also a comparison and compatibility reference,
not an implementation target. Existing Apple Container Compose wrappers map
Compose intent onto Apple `container` CLI/API behavior; this project studies
whether a persistent LinuxPod project runtime can solve the lower-level
runtime, storage, DNS, job, event, and recovery problems for backend-shaped
local-development workloads.

Microsoft WSL container is an optimization reference only. Its useful lesson is
the need for persistent session/storage/event/recovery machinery behind a
native host UX. Do not add dockerd, containerd, or WSL as a backend.

## Current Implementation Boundary

The current Swift package has runtime-neutral `RuntimePlan` planning, dry-run
output, diagnostics, redaction, safety checks, LinuxPod execution experiments,
benchmark records, and a minimal `LocalDevProject` IR scaffold.

This first run intentionally does not implement persistent LinuxPod hotplug,
rootfs-cache reuse, writable layers, Kubernetes parsing, or full Compose
parsing. Those belong behind explicit follow-up plans and benchmark gates.

## Safety Rules

Runtime mutation must stay explicit:

- select `--runtime linuxpod`;
- review dry-run output first;
- provide the current-task approval token;
- mutate only adapter-owned `cca-linuxpod-*` state.

Cleanup must stay narrow:

- no global prune;
- no host DNS mutation;
- no Docker Hub, registry, or Keychain mutation;
- no deletion outside adapter-owned paths;
- preserve named volumes by default;
- delete named volumes only when explicitly requested.

## Memory Claims

Apple-native does not automatically mean lower host RAM use. Memory claims need
reliable host-level evidence. Guest cgroup memory, process RSS, runtime memory,
and host physical footprint must be recorded separately. If host attribution is
not reliable, reports must say `blocked` instead of implying savings.

## Success Shape

A useful local-development target looks like:

- Postgres with an adapter-owned named volume;
- migration job;
- seed job;
- API service;
- service DNS/aliases;
- deterministic host port publishing;
- healthcheck orchestration;
- logs/status/exec;
- safe cleanup;
- cold and warm benchmark evidence.

The product becomes credible only when the supported graph runs with predictable
behavior, good diagnostics, clean cleanup, and measured cold/warm performance.
