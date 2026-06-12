# Benchmark And Metrics Plan

## Principle

Separate cold runtime cost from warm local-development loop cost.

Cold benchmarks explain first-run cost. Warm benchmarks decide whether the
product is useful for daily development.

Do not claim host RAM savings without reliable host-level evidence.

## Required Metadata

Every benchmark record should carry enough context to interpret results:

- runtime kind;
- runtime version or implementation surface;
- `apple/containerization` version;
- Apple `container` CLI version when used;
- macOS version;
- host architecture;
- lifecycle mode: cold or warm;
- project id;
- whether the project runtime existed before the run;
- image cache hit/miss;
- rootfs cache hit/miss;
- initfs cache hit/miss;
- whether named volumes existed before the run.

The current Swift scaffold adds `BenchmarkRunMetadata` so Phase 6-style
iteration and summary records can preserve this context.

## Benchmark Scenarios

Required scenarios:

1. Simple web service.
2. Postgres only, fresh volume.
3. Postgres only, warm preserved volume.
4. Backend-shaped fixture:
   - Postgres;
   - named volume;
   - healthcheck;
   - migration job;
   - seed job;
   - API service;
   - published port;
   - load window.
5. DNS/connectivity test.
6. Port publishing and conflict test.
7. Bind mount I/O test.
8. Named volume I/O test.
9. Rootfs preparation microbenchmark.
10. Cleanup and stale-state test.

## Metrics

Record:

- startup time;
- readiness time;
- healthcheck attempts;
- job duration and exit code;
- log/status latency;
- guest cgroup memory current;
- guest cgroup memory peak if available;
- process count;
- CPU use;
- block read bytes;
- block write bytes;
- data footprint;
- completed work during a load window;
- cleanup duration;
- cleanup result;
- stale file/process/port count;
- failure and timeout count.

Host physical memory must be a separate field. If a reliable attribution source
does not exist, mark the result `blocked`.

## Microbenchmarks

| Microbenchmark | What it isolates |
| --- | --- |
| rootfs unpack | OCI image to ext4 cost |
| rootfs copy | per-container duplication baseline |
| APFS clone | clonefile/reflink feasibility and fallback rate |
| writable layer | read-only base plus writable layer correctness |
| pod create | LinuxPod VM creation time |
| hotplug addContainer | persistent pod service add/recreate behavior |
| container start | start latency after registration |
| exec latency | healthcheck overhead floor |
| named volume create | ext4 volume setup cost |
| Postgres fresh volume | initdb and DB cold start |
| Postgres warm volume | restart with preserved data |
| service DNS | lookup/connect latency |
| port publish | localhost reachability and release behavior |
| cleanup | stop/delete/release behavior |

## Baselines

Docker Desktop, OrbStack, Colima, Podman, Lima, and Rancher Desktop may be used
as comparison baselines or optimization references. They are not implementation
backends.

Apple `container` CLI may be used as:

- capability probe;
- simple workload reference;
- negative-control comparison;
- upstream reproduction helper.

LinuxPod results should be judged primarily against Docker/OrbStack-class
Compose behavior for local development, not only against Apple `container` CLI.

## Apple Upstream Topics

Benchmark reports should be structured so useful findings can become focused
Apple upstream issues or pull requests. Candidate topics:

- LinuxPod add-container or hotplug behavior for persistent project runtimes;
- rootfs preparation cost and image digest cache reuse;
- APFS clone or writable-layer feasibility;
- initfs, kernel, and vminit cache behavior;
- service DNS or hosts management for multi-service local projects;
- ext4 named-volume behavior, including database ownership and `lost+found`
  edge cases;
- healthcheck exec overhead;
- port publishing behavior and release proof;
- public Apple `container` CLI differences from lower-level
  `apple/containerization`;
- host memory attribution gaps on macOS.

Upstream reports should include public fixtures, exact runtime versions,
macOS/architecture metadata, JSONL evidence, and cleanup proof. They should not
include private EMSI workloads, secrets, registry credentials, or local machine
paths that are not necessary for reproduction.

## Gates

Early research gates:

- backend-shaped fixture runs DB, migrate, seed, API, readiness, logs, status,
  and cleanup;
- warm runs have zero failures before publication-style claims;
- cleanup leaves no adapter-owned stale state except preserved named volumes;
- block reads fall materially after rootfs/volume cache work;
- guest memory is explainable;
- host physical memory stays blocked until measured reliably;
- startup/readiness moves toward Docker/OrbStack baseline before replacement
  language is used.

## Output

Use JSONL for raw events and Markdown for reports.

Suggested event types:

- `run.started`
- `cache.checked`
- `rootfs.prepared`
- `pod.created`
- `container.started`
- `healthcheck.attempt`
- `job.completed`
- `port.published`
- `load.completed`
- `stats.sampled`
- `cleanup.completed`
- `run.completed`

Each event should be safe to share publicly: redact likely secrets, avoid
private workload names, and include enough metadata to reproduce the runtime
context.
