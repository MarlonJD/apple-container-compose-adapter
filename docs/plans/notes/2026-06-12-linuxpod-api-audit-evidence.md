# LinuxPod API Audit Evidence

**Date:** 2026-06-12
**Linked plan:** [LinuxPod Compose Runtime Backend Implementation Plan](../2026-06-12-linuxpod-compose-runtime-backend-plan.md)
**Decision:** `linuxpod-api-still-viable`
**Runtime mutation:** None.

## Decision

The current public `apple/containerization` source still supports the
LinuxPod-first direction in the active plan. No strategy reversal is needed.

The material Phase 0 update is narrower: service-name connectivity should start
with adapter-managed LinuxPod `Hosts` entries for the first implementation
path, because the current `LinuxPod` API exposes pod-level and container-level
hosts configuration and upstream integration tests cover inheritance and
container overrides. This does not prove Compose service-name parity yet; Phase
4 still needs dry-run coverage and a runtime-approved smoke before making a
compatibility claim.

## Source Inspected

Official public source was fetched without builds or runtime calls:

- Repository: `https://github.com/apple/containerization`
- Branch: `main`
- Commit: `1437c67f5a07cb39e8f5e79d0b5aeac0327932bd`
- Commit date: `2026-06-04T22:08:22Z`
- Latest public tag observed during the audit: `0.33.4` at
  `9275f365dd555c8f072e7d250d809f5eb7bdd746`
- Prior spike package pin: `0.26.5` at
  `636eef0eff00e451de6d5d426e6a6785b90b44e2`
- Files inspected:
  - `Sources/Containerization/LinuxPod.swift`
  - `Sources/Integration/PodTests.swift`
  - `Sources/Integration/NBDTests.swift`
  - `examples/ctr-example/Package.swift`
  - `examples/ctr-example/Sources/ctr-example/main.swift`

The fetched files were stored only under
`/private/tmp/cca-linuxpod-api-audit/` for read-only inspection.

## API Findings

- `LinuxPod` remains explicitly marked experimental and still models multiple
  Linux containers inside one VM, sharing CPU, memory, and network resources.
- `LinuxPod.Configuration` includes pod-level `cpus`, `memoryInBytes`,
  `interfaces`, `shareProcessNamespace`, `hostname`, `dns`, `hosts`,
  `volumes`, and VM lifecycle extensions.
- `LinuxPod.ContainerConfiguration` includes process configuration,
  per-container CPU and memory limits, hostname, sysctls, mounts, sockets,
  per-container DNS, per-container hosts, and optional init support.
- `LinuxPod.PodVolume` exists, but its public source currently models NBD-backed
  pod volumes. Upstream tests cover shared NBD pod volumes and persistence, so
  this is a viable Phase 3 research candidate; the adapter should still keep
  Compose named-volume planning runtime-neutral until a concrete volume backend
  is proven.
- Lifecycle APIs remain suitable for a backend boundary:
  `addContainer`, `create`, `startContainer`, `stopContainer`, `stop`,
  `waitContainer`, `killContainer`, `execInContainer`, `listContainers`,
  `statistics`, and scoped access through `withVirtualMachineInstance`.
- `statistics(containerIDs:categories:)` remains the direct per-container
  guest/cgroup source for process, memory, CPU, block I/O, network, and memory
  event evidence. It still does not solve reliable host physical footprint
  attribution by itself.

## Tests And Examples

Relevant upstream tests still support the plan assumptions:

- Multiple containers in one pod are covered by `testPodMultipleContainers`.
- Per-container statistics are covered by `testPodContainerStatistics`.
- Per-container resource limits are covered by
  `testPodContainerResourceLimits` and independent limit tests.
- Filesystem isolation and PID namespace isolation are covered.
- Optional shared PID namespace is covered by tests that set
  `shareProcessNamespace = true`.
- DNS and hosts support is stronger than the earlier plan wording assumed:
  upstream tests cover container-level DNS, pod-level DNS inheritance,
  container-level hosts, pod-level hosts inheritance, and container hosts
  overrides.
- Upstream tests note that containers in a pod share a network namespace.
- NBD-backed shared pod volumes and persistence are covered in upstream tests,
  but they are not yet proof that Compose named volumes should be implemented
  directly as LinuxPod pod volumes instead of adapter-owned state paths.

The `ctr-example` package remains a single-container `ContainerManager`
example, not a LinuxPod Compose-style example. It pins
`apple/containerization` `0.26.5`, uses `vminit:0.26.5`, and declares macOS
`26.0`.

## Impact On Active Plan

No plan replacement is required.

Plan updates from this audit:

- Keep LinuxPod as the primary runtime efficiency experiment.
- Keep Docker/OrbStack as the success target.
- Keep public Apple `container` CLI as fallback, probe, or negative control.
- For Phase 4 service-name connectivity, start with adapter-managed
  LinuxPod `Hosts` entries as the first design candidate.
- For Phase 3 named volumes, treat NBD-backed pod volumes as a candidate to
  evaluate against simpler adapter-owned state paths, not as a settled design.
- Keep Phase 5 host-footprint research open because the source audit did not
  find a reliable host physical memory attribution source.

## Verification

No runtime resources were created, started, stopped, or deleted. No registry
login, private workload, prune, global cleanup, branch operation, commit, push,
or parent submodule pointer update was performed.

Phase 0 verification is completed by running `git diff --check` after the plan
and index updates that reference this note, plus an explicit trailing-whitespace
scan over touched untracked Markdown files because they are not covered by
`git diff --check` until staged.
