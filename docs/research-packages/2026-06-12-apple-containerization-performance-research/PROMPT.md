# Deep Research Prompt

You are a senior systems/runtime engineer and technical researcher. I am
evaluating whether a macOS developer tool called Container Compose Adapter can
reach Docker Compose-level local backend development performance by building on
Apple's open source `container` CLI and `apple/containerization` Swift package.

Use the attached package as measured local evidence. Also browse current
upstream sources and documentation before answering, especially:

- `apple/container`
- `apple/containerization`
- `apple/container/issues/1698`
- `apple/containerization/issues/729`
- Docker Desktop VMM/settings docs
- Lima, Colima, Finch, Podman Desktop, and Rancher Desktop official sources

Current date assumption: June 12, 2026. Verify whether upstream behavior,
issues, releases, APIs, or docs have changed since then.

## Context

Container Compose Adapter maps Docker Compose-style local development intent
onto Apple's `container` CLI and, experimentally, onto
`apple/containerization` LinuxPod. The goal is practical Compose compatibility
for local development on Apple silicon/macOS, not an official Apple tool and
not a Docker Engine clone.

Measured local evidence so far:

- Docker/OrbStack remains much better for backend-shaped Compose workloads in
  the provided benchmark.
- Apple `container` is promising for simple web workloads but reports much
  higher Postgres cgroup/runtime memory and block reads than Docker/OrbStack,
  despite similar Postgres process RSS and similar DB data footprint.
- macOS host process memory attribution was blocked: guest VM memory growth was
  not charged to the runner process by the tested host tools.
- LinuxPod can run the backend-shaped fixture end to end in one shared VM, but
  the Phase 6 gate failed on guest cgroup memory, startup/readiness, and block
  read volume.
- The current LinuxPod implementation is intentionally safe and clean: it uses
  adapter-owned state, prepares image rootfs files, creates ext4 named volumes,
  clones per-container rootfs, and deletes adapter-owned runtime state on
  cleanup. This may be too cold compared with Docker's long-lived VM, engine,
  image store, overlay/layer cache, and warm page cache model.

## Files to read first

Read these local package files before forming conclusions:

1. `README.md`
2. `EVIDENCE_INDEX.md`
3. `evidence/20260611T185918Z-combined-runtime-efficiency-report.md`
4. `plans/2026-06-12-linuxpod-phase-6-benchmark-decision.md`
5. `plans/2026-06-12-linuxpod-phase-5-host-footprint-evidence.md`
6. `plans/2026-06-11-apple-upstream-benchmark-issue-package.md`
7. `source/ContainerizationLinuxPodRuntimeExecutor.swift`
8. `source/LinuxPodBackend.swift`
9. `source/HostFootprint.swift`
10. `source/Phase6Benchmark.swift`
11. `fixtures/backend-shaped/compose.yaml`

Then inspect the raw JSONL only when needed to validate or challenge the
summary.

## Research questions

Answer these questions with evidence and code/source references:

1. Are the bad results primarily caused by our adapter implementation, by
   Apple `container` / `containerization` architecture, by benchmark shape, or
   by an unavoidable tradeoff of per-container/per-pod VM isolation?
2. What specific optimizations exist in Docker Desktop, OrbStack-class
   runtimes, Lima/Colima/Finch/containerd, or Podman that explain the better
   Compose backend results?
3. In Apple `container` and `apple/containerization`, where are the equivalent
   optimization points?
   - image/content store reuse
   - rootfs generation and ext4 image reuse
   - overlay/writable layer support
   - LinuxPod lifecycle reuse
   - initfs/vminit/kernel reuse
   - virtiofs/shared mount behavior
   - named volume implementation
   - networking, DNS, and service discovery
   - port publishing and host access
   - readiness/healthcheck/job orchestration
   - VM memory sizing and memory accounting
   - block I/O accounting and cache behavior
4. Can LinuxPod be made Compose-level competitive with a persistent warm
   project runtime and rootfs/layer cache, or is Docker/containerd-in-one-VM the
   more realistic open source direction?
5. Would using Apple `container` CLI directly, `apple/containerization`
   `LinuxContainer`, or `LinuxPod` be the best base for a Compose adapter?
6. If Apple upstream needs changes, what are the smallest useful upstream
   issues or PR proposals?
7. If the right answer is not Apple `containerization`, which open source
   alternative should be the practical target: Lima+Docker, Lima+containerd,
   Colima, Finch, Podman machine, Rancher Desktop, or another runtime?

## Required output

Produce a detailed research report with these sections:

1. Executive verdict
   - Use one of: `continue-apple-linuxpod`, `pause-apple-linuxpod`,
     `switch-to-open-source-docker-compatible-vm`, or `hybrid`.
   - Include confidence level and what evidence could change the verdict.
2. Root-cause tree
   - Separate adapter-caused, upstream-caused, benchmark-caused, and
     architecture-caused factors.
3. Source-level findings
   - Cite exact upstream files, types, functions, docs, or issues where
     possible.
   - Cite exact local package files where the adapter may be cold or
     suboptimal.
4. Optimization map
   - Rank each optimization by expected impact, implementation difficulty,
     upstream dependency, and risk.
5. Compose-level roadmap
   - Cover service DNS, networks, ports, bind mounts, named volumes, profiles,
     healthchecks, depends_on ordering, one-off jobs, logs, status, cleanup,
     build support, and diagnostics.
6. Benchmark plan
   - Design no-side-effect dry runs, microbenchmarks, and runtime smoke tests
     that can isolate rootfs prep, pod create, container start, readiness,
     network/DNS, named volume I/O, and cleanup.
   - Include metrics: cgroup current/peak, process RSS, runtime memory, block
     read/write, data footprint, startup/readiness, cleanup, failure rate, and
     completed work per load window.
7. Upstream engagement plan
   - Draft concise issue/PR topics for Apple if appropriate.
8. Open source alternative comparison
   - Compare Lima, Colima, Finch, Podman, Rancher Desktop, Docker Desktop, and
     OrbStack where data is available.
9. Recommendation
   - Give a concrete 2-week plan and a 6-week plan.
   - State explicitly whether Container Compose Adapter should keep LinuxPod as
     a research path, switch the runtime target, or maintain multiple backends.

## Rules

- Do not rely on marketing claims without matching them to source code,
  architecture, or measurements.
- Do not claim host RAM savings unless there is a reliable host-level source.
- Treat Docker Compose behavior as the compatibility reference.
- Treat Apple `container` behavior as a runtime target, not as an official
  Compose implementation.
- If a claim cannot be verified from sources, mark it as an inference.
- Prefer patches and experiments that are small enough to be validated in this
  repository.
- Keep the final answer technical and decision-oriented.
