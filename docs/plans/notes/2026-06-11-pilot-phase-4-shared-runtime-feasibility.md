# Pilot Phase 4 Shared Runtime Feasibility

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../completed/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** Official Apple `container` docs, local CLI help, and non-mutating source/API inspection for shared-runtime feasibility.

## Phase 4 Verdict

Shared-runtime support is **not exposed by the Apple `container` CLI** as a Compose-style command, pod command, or Docker-host-style shared OCI runtime.

The lower-level `apple/containerization` source does include a public `LinuxPod` API that can create one pod VM and add multiple container root filesystems/processes inside it. That makes shared runtime **possible but out of scope for the first Container Compose Adapter implementation** unless the project explicitly chooses a separate Swift-package-level runtime mode.

Do not describe current `container` CLI support as a native Compose or pod runtime. Do treat `LinuxPod` as a future research track after the dry-run adapter is stable.

## Sources Inspected

Official web/docs:

- `https://github.com/apple/container`
- `https://github.com/apple/container/blob/main/docs/technical-overview.md`
- `https://github.com/apple/container/blob/main/docs/command-reference.md`
- `https://github.com/apple/container/blob/main/docs/container-machine.md`
- `https://github.com/apple/containerization`

Local CLI help:

- `container --version`
- `container --help`
- `container help run`
- `container help machine`
- `container help network`
- `container help volume`
- `container system status`

Non-mutating source/API inspection:

- Downloaded official `apple/container` `main` source archive to `/private/tmp/apple-container-main.tar.gz`.
- Downloaded official `apple/containerization` `main` source archive to `/private/tmp/apple-containerization-main.tar.gz`.
- Extracted both archives under `/private/tmp/apple-container-source-check`.
- Searched for `pod`, `compose`, `shared runtime`, `multi-container`, `LinuxPod`, `VirtualMachine`, `container machine`, and command registration terms.

No repository file outside this project was edited. No runtime resources were mutated.

## Apple `container` CLI Finding

Local help and `apple/container` command registration expose these command groups:

- container lifecycle: create, run, start, stop, exec, logs, list, inspect, stats, delete, prune;
- image/build;
- machine;
- network;
- volume;
- system;
- registry.

No `compose`, `pod`, `group`, or shared-runtime command was found in local help or in the `apple/container` CLI command registration source.

`container machine` is useful, but it is modeled as a Linux environment, not a Compose service group. The official docs say it runs the image init system, can run long-running services through a process supervisor, maps the user's home directory, and deletes persistent storage when the machine is removed. That can support development inside one Linux environment, but it does not preserve Compose service semantics by itself:

- separate OCI image lifecycle per service;
- per-service container logs/status/stats;
- Compose dependency gates;
- service-name DNS across isolated service containers;
- named-volume lifecycle matching `down` versus `down --volumes`;
- adapter-owned cleanup without deleting a broader development machine.

Classification for the CLI path: **unsupported as a built-in shared-runtime
primitive that the adapter can delegate to**. This does not mean the adapter
goal is invalid; it means the first implementation must provide Compose-style
planning, idempotency, service discovery, diagnostics, and cleanup itself on top
of the available Apple `container` CLI commands.

## `containerization` `LinuxPod` Finding

The `apple/containerization` source includes `Sources/Containerization/LinuxPod.swift`.

Relevant API evidence:

- `LinuxPod.Configuration` defines CPU and memory for the pod VM, network interfaces, optional shared PID namespace, default hostname/DNS/hosts, and pod volumes that can be shared with multiple containers.
- `LinuxPod.ContainerConfiguration` defines per-container process, optional per-container CPU/memory limits, hostname, sysctls, mounts, sockets, DNS, hosts, and init behavior.
- `addContainer` registers a container root filesystem before pod creation or hotplugs a container after creation when supported.
- `create` starts the underlying pod VM and sets up registered container root filesystems.
- `stop` stops all containers and the pod VM.
- `execInContainer`, `listContainers`, `statistics`, and `dialVsock` provide lifecycle and observability surfaces.
- Integration tests include multi-container pod cases and note that containers in a pod share a network namespace.

This is real lower-level API evidence that a shared-VM, multi-container mode may be possible without building a Docker daemon clone from scratch.

However, it is not yet a product-ready answer for this repository:

- It is not exposed through the installed `container` CLI.
- It would require the adapter to integrate directly with the `containerization` Swift package instead of shelling out only to `container`.
- It would require image pull/unpack/rootfs lifecycle work at the package level.
- It would require project-owned networking, DNS, service names, logs, stats, health gates, volume behavior, idempotency, and cleanup semantics.
- It would need a license and dependency review before being added to this AGPL project.
- It was not prototyped or measured in this phase.

Classification for the lower-level API path: **possible but out of scope for the first implementation; candidate for a follow-up research plan**.

## Architecture Decision

For the main implementation plan:

1. Proceed only with the dry-run-first adapter against the public `container` CLI.
2. Keep runtime execution gated until dry-run plans, parser/planner tests, and explicit approval are in place.
3. Do not claim OrbStackless efficiency or shared-runtime parity.
4. Add `containerization` `LinuxPod` as an optional future research path, not as a requirement for the first adapter.

## Phase 4 Follow-up

If the owner wants a shared runtime after the dry-run adapter exists, create a separate plan that prototypes `LinuxPod` with only the public simple-web fixture first. That prototype should not be mixed into the first CLI-shellout implementation path.
