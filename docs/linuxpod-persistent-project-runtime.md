# LinuxPod Persistent Project Runtime

## Purpose

This document defines the intended LinuxPod runtime direction. It is a design
target, not a claim about current implementation.

The target model is:

```text
one LocalDevProject = one persistent LinuxPod runtime
```

The runtime should be explicit, inspectable, benchmarked, and safe to clean up.

## Cold Lifecycle

Cold mode means:

- no project runtime exists;
- image/content cache may be empty;
- rootfs cache may be empty;
- initfs/kernel/vminit cache may be cold;
- named volumes may be fresh;
- the LinuxPod must be created before services run.

Cold benchmarks prove reproducibility and first-run cost. They should not be
used alone to market local development performance.

## Warm Lifecycle

Warm mode means:

- project runtime already exists or can be reused;
- image/content cache exists;
- rootfs cache exists by image digest;
- initfs/kernel/vminit cache is reusable;
- named volumes exist and are preserved;
- only changed services/jobs need recreate or restart.

Warm benchmarks are the primary product-value signal because they reflect the
developer loop.

## Image And Content Store Reuse

The runtime should keep image/content state separate from project runtime state.
Potential cache keys:

- image reference plus digest;
- platform;
- `apple/containerization` version;
- rootfs format/version;
- vminit image digest;
- kernel version and architecture.

Normal project cleanup must not delete reusable global caches unless a future
explicit cache cleanup command is designed and approved.

## Rootfs Strategy

Rootfs work should be tested as microbenchmarks before becoming default
runtime behavior.

Experiments:

- full rootfs copy baseline;
- APFS clone or clonefile when available;
- read-only base rootfs plus per-container writable layer;
- writable layer reuse;
- lazy rootfs creation;
- rootfs pool keyed by image digest.

Metrics:

- rootfs prep time;
- bytes copied;
- block read/write;
- clone success/fallback;
- container start time;
- correctness for Postgres/API workloads;
- cleanup result.

Do not claim rootfs-cache wins until benchmark metadata proves cold/warm cache
state.

## Initfs, Kernel, And Vminit Reuse

Persistent runtime research should measure whether initfs, kernel, and vminit
state can be reused safely.

Record:

- vminit image reference and digest;
- kernel path/version;
- initfs cache hit/miss;
- containerization version;
- macOS version;
- host architecture.

If any of these values change, warm-cache results must be interpreted
carefully.

## Named Volume Lifecycle

Named volumes should be adapter-owned Linux-side ext4 volumes for database
workloads.

Rules:

- preserve named volumes by default;
- delete only with explicit volume cleanup;
- delete only adapter-owned project volume paths;
- use sentinel metadata when possible;
- never delete broad host paths or non-adapter-owned paths.

Experiments:

- fresh ext4 creation;
- empty ext4 template clone;
- warm preserved volume;
- fast reset of adapter-owned volume only;
- Postgres initdb fresh vs warm volume;
- block I/O and guest memory deltas.

## Service DNS And Aliases

Minimum expected behavior:

- service name resolves inside the project runtime;
- aliases resolve inside the project runtime;
- future Kubernetes Service names resolve inside the project runtime;
- host-to-container paths are documented;
- container-to-container paths are benchmarked.

The current LinuxPod experiments use host entries. That is acceptable as an
early proof, but a durable implementation should evaluate proper project DNS or
an equivalent managed resolver.

## Deterministic Host Port Publishing

Host ports must be deterministic in the first supported runtime subset.

Runtime planning should:

- fail early on missing host ports where dynamic assignment is unsupported;
- detect likely conflicts before mutation when practical;
- record published port metadata;
- prove release during cleanup;
- avoid host DNS mutation.

## Healthcheck Orchestration

Healthchecks must preserve Compose semantics where they matter:

- `service_started`;
- `service_healthy`;
- `service_completed_successfully`;
- timeout and retry behavior;
- structured failure logs.

Future optimization should measure healthcheck overhead separately. A naive
exec-per-probe loop may be correct but too expensive for warm development.

## One-off Job Orchestration

Jobs should:

- run after dependencies meet their conditions;
- capture exit status;
- capture stdout/stderr summary for evidence;
- block dependent services on failure unless the job is explicitly optional;
- participate in `run` and `up` planning.

Migration and seed jobs are the first backend-shaped fixture requirements.

## Logs, Status, And Exec

Minimum runtime surface:

- `logs` returns per-service log metadata and tails;
- `status` reports service/job lifecycle state;
- `exec` is planned as a future operation for service debugging;
- all outputs redact likely secrets.

## Cleanup Safety

Runtime cleanup must be narrow:

- stop only the adapter-owned project LinuxPod;
- delete only adapter-owned runtime state;
- delete named volumes only when requested;
- never run global prune;
- never mutate registry credentials, Keychain, Docker Hub, host DNS, or
  unrelated host paths.

The current state-store guard rejects cleanup for non-adapter-owned project
directories. Concrete runtime executors should keep equivalent checks at every
filesystem mutation boundary.

## Next Run Boundary

The next implementation run can safely focus on persistent LinuxPod and
microbenchmarks only after this scaffold is stable:

- hotplug/add-container behavior;
- rootfs cache hit proof;
- APFS clone vs full copy;
- writable-layer feasibility;
- preserved project runtime modes;
- benchmark metadata for cold/warm/cache state.
