# Phase 0 Capability Discovery Evidence

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../completed/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** No-side-effect baseline context, Docker/OrbStack availability, Apple `container` availability, and official shared-runtime feasibility evidence.

## Phase 0 Verdict

- Local Apple `container` CLI evidence was refreshed after installation: `container` is now present at `/usr/local/bin/container`, with CLI version `1.0.0` build `release`, commit `ee848e3`.
- Apple `container` runtime service evidence is still not ready for measurement: `container system status` reports that the apiserver is not running and is not registered with launchd. The pilot did not run `container system start`.
- Docker/OrbStack baseline context is available: the active Docker context is `orbstack`, Docker client/server queries succeed, and Docker Compose is installed. No Compose project was run.
- Official Apple docs inspected in Phase 0 describe the native `container`/`containerization` model as one lightweight VM per Linux container.
- No official pod-like or Docker-host-style shared OCI container runtime primitive was found in the inspected Apple `container` CLI docs or `containerization` README.
- `container machine` is an official primitive for a persistent Linux environment that can run commands and system services inside one VM. It is not, based on inspected docs, a Compose-equivalent shared runtime for multiple isolated OCI service containers with separate lifecycle, logs, networking, and cleanup.

This phase is not a go/no-go recommendation yet. It establishes that Phase 1 needs a dry-run evidence schema and explicit status handling for `cli-available-service-stopped`, `measured`, `skipped-runtime-unavailable`, and `blocked` before any runtime measurements or mutating commands.

## Command Safety

No command intentionally created, started, stopped, pulled, removed, pruned, or mutated containers, images, networks, or volumes.

One attempted read-only command, `orb version`, unexpectedly tried to `chmod` OrbStack's local run directory and failed under the sandbox. It was not escalated because Phase 0 only needed non-mutating availability evidence.

After Apple `container` was installed, several read-only `container` system and help commands needed to be retried outside the app sandbox because the sandbox returned `Operation not permitted` for XPC-backed queries. The retried commands were still read-only. No `container system start`, image pull, build, run, network create, volume create, or cleanup command was run.

## Local Machine Context

| Evidence | Result |
| --- | --- |
| Capture time | `2026-06-11T19:39:19+0300 +03` |
| macOS | `26.5.1` build `25F80` |
| Darwin / architecture | Darwin kernel `25.5.0`, `arm64` |
| Hardware | MacBook Pro `Mac14,7`, Apple M2, 8 cores, 16 GB memory |
| Shell | `/bin/zsh`, zsh `5.9`, `TERM=dumb` |
| Swift | Apple Swift `6.3.2`, target `arm64-apple-macosx26.0` |
| Xcode | Xcode `26.5`, build `17F42` |

Notes:

- `sysctl` probes for memory and CPU fields failed with `Operation not permitted` in the sandbox.
- `system_profiler SPHardwareDataType -detailLevel mini` supplied the hardware and memory evidence instead.

## Docker And OrbStack Context

| Command | Expected no-side-effect behavior | Actual result |
| --- | --- | --- |
| `command -v docker` | Locate Docker CLI only. | Docker CLI present at `/usr/local/bin/docker`. |
| `docker context show` | Print active Docker context. | Active context is `orbstack`. |
| `docker context ls` | List Docker contexts. | `orbstack` is current; its local Unix socket path was redacted from this note. |
| `docker version` | Query client/server versions without starting containers. | Docker client and server both responded with version `29.4.0`; server is Linux/arm64 with containerd `v2.2.2` and runc `1.4.2`. |
| `docker compose version` | Print Compose plugin version. | Docker Compose `v5.1.2`. |
| `docker system df` | Query Docker resource counts and disk usage. | Images: 5 total, 4 active, 5.608 GB. Containers: 4 total, 2 active. Local volumes: 1 total, 1 active. Build cache: 98 entries. |
| `command -v orb` | Locate OrbStack CLI only. | OrbStack CLI present at `/usr/local/bin/orb`. |
| `orb version` | Expected version-only output. | Failed before returning a version because the CLI attempted `chmod` on OrbStack's local run directory and the sandbox denied it. Not escalated. |
| `pgrep -fl OrbStack` | Inspect whether OrbStack processes are visible. | Failed because process-list access is blocked in this app sandbox (`sysmond service not found`). |

Interpretation: Docker/OrbStack is available enough for future baseline measurement, but Phase 0 did not run Docker Compose or change any Docker/OrbStack resources.

## Apple Container Local Capability

| Command | Expected no-side-effect behavior | Actual result |
| --- | --- | --- |
| `command -v container` | Locate Apple `container` CLI only. | `/usr/local/bin/container`. |
| `container --version` | Print CLI version if installed. | `container CLI version 1.0.0 (build: release, commit: ee848e3)`. |
| `container --help` | Print local command surface if installed. | Top-level help printed container, image, machine, volume, builder, network, and system subcommand groups. It also reported `PLUGINS: not available, run container system start`. |
| `container system status` | Read service status. | Outside the sandbox: `apiserver is not running and not registered with launchd`. |
| `container system version` | Read CLI/API server version information. | CLI row returned version `1.0.0`, build `release`, commit `ee848e3ebfd7c73b04dd419683be54fb450b8779`. No server row was present. |
| `container system df` | Read disk usage for images, containers, and volumes. | Failed because the service is not started: XPC connection invalid and guidance to run `container system start`. |
| `container list --all` | Read container list. | Failed because the service is not started: XPC connection invalid and guidance to run `container system start`. |
| `container network list` | Read network list. | Failed because the service is not started: XPC connection invalid and guidance to run `container system start`. |
| `container volume list` | Read volume list. | Failed because the service is not started: XPC connection invalid and guidance to run `container system start`. |

Subcommand-specific help was captured through `container help ...` outside the app sandbox. Direct forms such as `container run --help` returned only top-level help in this environment.

## Local Capability Surface After Install

| Area | Local help evidence | Phase 0 implication |
| --- | --- | --- |
| Build | `container help build` shows Dockerfile/Containerfile build support with build args, file path, labels, memory/CPU, output type, platform, secrets, tags, target, DNS options, and pull flag. | Build capability exists at the CLI surface, but no build was run. Measurement still requires service startup approval and a dry-run harness first. |
| Run | `container help run` shows env/env-file, user/workdir, CPU/memory, labels, mounts, name, network, publish, publish-socket, read-only, remove, Rosetta, runtime, SSH, tmpfs, volume, and virtualization flags. | Single-container execution surface is rich enough to map many Compose fields, but runtime behavior is unmeasured. |
| Network | `container help network` shows create/delete/list/inspect/prune. `container help network create` exposes internal, label, option, plugin, subnet, and IPv6 subnet flags. | Network management surface exists; service-name DNS and multi-service connectivity remain unmeasured. |
| Volume | `container help volume` shows create/delete/list/inspect/prune. `container help volume create` exposes labels, driver options, and size. | Named volume surface exists; persistence and cleanup behavior remain unmeasured. |
| Exec/logs | `container help exec` and `container help logs` show exec process flags and log follow/tail/boot options. | Developer workflow primitives exist at the CLI surface. |
| Status/list | There is no standalone `container status` command in local help. `container help list` and `container help stats` provide list and resource usage surfaces. | Adapter `status` should compose list/inspect/stats rather than assuming native `status`. |
| System | `container help system` shows df, dns, kernel, logs, property, start, status, stop, and version. `container help system status` and `container help system df` show formatted read options. | Useful read-only system probes exist, but runtime service is currently stopped/unregistered. |
| Machine | `container help machine` shows create/delete/inspect/list/logs/run/set/set-default/stop and examples for running commands inside a container machine. | `container machine` remains a Linux-environment primitive, not documented evidence of Compose-style shared OCI service containers. |

## Official Apple Documentation Evidence

Sources inspected:

- [apple/container README](https://github.com/apple/container)
- [apple/container technical overview](https://github.com/apple/container/blob/main/docs/technical-overview.md)
- [apple/container command reference](https://github.com/apple/container/blob/main/docs/command-reference.md)
- [apple/container container-machine docs](https://github.com/apple/container/blob/main/docs/container-machine.md)
- [apple/containerization README](https://github.com/apple/containerization)

Findings:

- `apple/container` positions the tool as running Linux containers as lightweight VMs on Mac and using the lower-level `Containerization` Swift package.
- The technical overview contrasts the usual shared Linux VM model with Apple's model and states that `container` runs a lightweight VM for each container.
- The technical overview also says `container-apiserver` launches a `container-runtime-linux` helper for each created container.
- The technical overview documents a memory caveat: memory freed inside a container VM is not currently relinquished back to the host without restarting the container.
- The `containerization` README independently says each Linux container executes inside its own lightweight VM. It also describes `vminitd` as the VM initial process that exposes a GRPC API for launching containerized processes inside that VM.
- The command reference includes command surfaces for `container run`, `container build`, `container create`, `container list`, `container exec`, `container logs`, `container stats`, `container network`, `container volume`, builder commands, system commands, and `container machine`.
- The command reference search did not find `pod`, `compose`, or shared-runtime commands. The only relevant multi-process/shared-environment surface found was `container machine`.
- `container machine` is documented as a persistent Linux environment based on an OCI image. It can run commands, boot on demand, expose a login shell, mount the user's home directory, and support real Linux services through an image init system such as `systemd`.

## Capability Surface From Official Docs

| Area | Official surface found | Phase 0 implication |
| --- | --- | --- |
| Build | `container build`; builder start/status/stop/delete. | Local image builds appear conceptually supported, but runtime measurement is blocked until CLI is installed and explicit mutation is approved. |
| Run/create | `container run`, `container create`, `container start`, `container stop`, `container kill`, `container delete`. | Single-container lifecycle exists in docs. Compose orchestration still needs adapter planning and tests. |
| Network | `container network create/delete/prune/list/inspect`, macOS 26+. | User-defined network management exists in docs. Multi-service DNS/connectivity still needs measurement. |
| Volume | `container volume create/delete/prune/list/inspect`; named and anonymous volume behavior documented. | Named volume support is plausible but needs local CLI and runtime evidence. |
| Exec/logs | `container exec`, `container logs`. | Developer workflow primitives exist in docs. |
| Status/list | `container list`, `container inspect`, `container stats`; no standalone `container status` was found. | Adapter `status` should likely compose list/inspect/stats data instead of assuming a native status command. |
| System | `container system start/stop/status/version/logs/df/dns/kernel/property`. | Some useful no-side-effect future probes exist, especially `system status`, `system version`, `system df`, and property list. |
| Machine | `container machine create/run/list/inspect/set/logs/stop/delete`. | Official Linux-environment primitive exists, but it is not documented as multiple OCI containers inside one VM. |

## Shared Runtime Assessment

Phase 0 found the documented native runtime model to be per-container VM. It did not find an official Apple primitive equivalent to "one shared Docker host running many OCI containers" or a pod-like grouping model.

The closest official primitive is `container machine`, but the documented abstraction is a persistent Linux environment:

- It runs the image init system and can support long-running system services.
- It is useful for Linux development and may be a future research path for running several processes in one VM.
- It does not, from the inspected docs, preserve separate OCI container roots, per-service image lifecycle, Compose-style service cleanup, container logs, container stats, or service-name network semantics for multiple services inside one shared VM.

Decision implication from Phase 0 docs/help: treat official `container` CLI shared-runtime support as not found. Later Phase 4 source/API inspection found a lower-level `containerization` `LinuxPod` API, but that is not exposed through the `container` CLI and remains a separate research path until prototyped.

## Commands Not Fully Captured

- Runtime resource snapshots were not captured because the Apple `container` apiserver is not running and is not registered with launchd. The pilot did not start it.
- `sysctl` hardware fields were blocked by the sandbox; replaced by `system_profiler`.
- OrbStack CLI version was not captured because `orb version` attempted a sandbox-denied directory permission change.
- OrbStack process list was not captured because process-list access is blocked by the app sandbox.

## Next Todo For Phase 1

Define the measurement evidence schema and no-mutation harness contract, including command metadata, redaction, resource snapshot strategy, `cli-available-service-stopped`, `measured`, `skipped-runtime-unavailable`, and `blocked` statuses, plus an explicit rule that dry-run-only harness behavior lands before any runtime mutation.
