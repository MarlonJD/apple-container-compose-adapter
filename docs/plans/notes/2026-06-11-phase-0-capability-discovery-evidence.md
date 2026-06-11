# Phase 0 Capability Discovery Evidence

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** No-side-effect baseline context, Docker/OrbStack availability, Apple `container` availability, and official shared-runtime feasibility evidence.

## Phase 0 Verdict

- Local Apple `container` CLI evidence is `skipped-runtime-unavailable`: `command -v container`, `container --version`, and `container --help` all showed that `container` is not installed in the current PATH.
- Docker/OrbStack baseline context is available: the active Docker context is `orbstack`, Docker client/server queries succeed, and Docker Compose is installed. No Compose project was run.
- Official Apple docs inspected in Phase 0 describe the native `container`/`containerization` model as one lightweight VM per Linux container.
- No official pod-like or Docker-host-style shared OCI container runtime primitive was found in the inspected Apple `container` CLI docs or `containerization` README.
- `container machine` is an official primitive for a persistent Linux environment that can run commands and system services inside one VM. It is not, based on inspected docs, a Compose-equivalent shared runtime for multiple isolated OCI service containers with separate lifecycle, logs, networking, and cleanup.

This phase is not a go/no-go recommendation yet. It establishes that Phase 1 needs a dry-run evidence schema and explicit `skipped-runtime-unavailable` handling before any runtime measurements or mutating commands.

## Command Safety

No command intentionally created, started, stopped, pulled, removed, pruned, or mutated containers, images, networks, or volumes.

One attempted read-only command, `orb version`, unexpectedly tried to `chmod` OrbStack's local run directory and failed under the sandbox. It was not escalated because Phase 0 only needed non-mutating availability evidence.

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
| `command -v container` | Locate Apple `container` CLI only. | Exit code `1`; no binary found in PATH. |
| `container --version` | Print CLI version if installed. | Exit code `127`; command not found. |
| `container --help` | Print local command surface if installed. | Exit code `127`; command not found. |

Local help output for build, run, network, volume, exec, logs, status/list, and system commands could not be captured because the CLI is unavailable. Phase 0 therefore used official Apple docs as the capability reference.

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

Decision implication: treat official shared-runtime support as not found in Phase 0. Do not claim shared-runtime feasibility unless Phase 4 later proves a supported `containerization` API pattern that preserves Compose service boundaries without becoming a new Docker/OrbStack-like runtime.

## Commands Not Fully Captured

- Local Apple `container` help surfaces were not captured because `container` is not installed.
- `sysctl` hardware fields were blocked by the sandbox; replaced by `system_profiler`.
- OrbStack CLI version was not captured because `orb version` attempted a sandbox-denied directory permission change.
- OrbStack process list was not captured because process-list access is blocked by the app sandbox.

## Next Todo For Phase 1

Define the measurement evidence schema and no-mutation harness contract, including command metadata, redaction, resource snapshot strategy, `measured` versus `skipped-runtime-unavailable` status, and an explicit rule that dry-run-only harness behavior lands before any runtime mutation.
