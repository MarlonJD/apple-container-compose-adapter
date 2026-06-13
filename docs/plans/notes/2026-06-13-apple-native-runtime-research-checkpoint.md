# Apple-native Runtime Research Checkpoint

**Date:** 2026-06-13
**Status:** `note-closed`
**Owner:** `tools/apple-container-compose-adapter`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Original Goal

The original product goal was an Apple-native local-dev orchestrator for
Compose/Kubernetes-defined backend stacks on macOS. Compose and Kubernetes
inputs would compile into `LocalDevProject`, then run through the closest safe
Apple-native runtime plan for repeated local backend development.

## Why This Is Not Just A Compose Wrapper

Existing tools such as `container-compose` primarily map Compose YAML onto
Apple `container` CLI/API behavior. That is useful compatibility work, but it
is not the full research question this repository explored.

Container Compose Adapter investigated direct
`apple/containerization` `LinuxPod` runtime primitives: persistent
project-scoped pods, rootfs/initfs and image-store reuse, ext4 named volumes,
service lifecycle behavior, hotplug capability, and APFS clone/COW-style rootfs
materialization. The question was whether those lower-level primitives could
become a practical Apple-native backend-shaped local-dev runtime, not whether a
Compose file can be translated into simple `container` commands.

## Evidence Summary

- Apple `container` CLI/simple path remains promising for simple workloads.
- Backend-shaped multi-container local-dev workloads remain difficult.
- `LinuxPod` can run the backend-shaped fixture functionally.
- Cold/fresh `LinuxPod` runtime remains slow for backend-shaped local-dev use.
- Image-store seeding improves the run significantly, but is insufficient by
  itself because rootfs/initfs/volume/pod lifecycle remains cold.
- Rootfs cache alone is insufficient because the current runtime still copies
  rootfs artifacts into project runtime state and then into per-container ext4
  images.
- Warm ext4 named volumes reduce block writes and preserve useful service data.
- Hotplug is not product-ready:
  - the default VZ-backed `LinuxPod` path has no installed hotplug provider;
  - a custom provider can be installed and receives the post-create call;
  - public ext4/block rootfs hotplug does not complete;
  - the second container does not start.
- Stage 10A clonefile/COW diagnostics are promising:
  - `clonefile` was strongly verified;
  - byte-for-byte rootfs copy work was avoided;
  - cleanup was clean;
  - `productReady=false`.

## Stage 10B Final Decision Experiment

Stage 10B was approved only as a guarded final decision experiment. It did not
change runtime defaults. The normal runtime still uses the existing full-copy
rootfs behavior unless the Stage 10B benchmark harness explicitly injects a
rootfs materialization override.

The intended comparison was:

- `fullCopy` backend-shaped `LinuxPod` runtime baseline;
- `auto`/`clonefile` backend-shaped `LinuxPod` runtime candidate, using Stage
  10A's positive clonefile evidence as the hypothesis;
- direct measurement of `up`/readiness, rootfs preparation, project/container
  materialization, block read/write, healthchecks, jobs, volume behavior,
  cleanup, and explicit `notMeasured` host-port/load-window fields.

Preflight dry-run rendered the backend-shaped plan without mutation:

```text
.build/debug/container-compose-adapter --runtime linuxpod --dry-run \
  --sample backend-shaped -p stage10b-runtime up
```

The dry-run showed warmed rootfs cache hits for both backend-shaped images,
`initfsCacheStatus=hit`, named-volume setup, database/API services, one-off
`migrate` and `seed` jobs, health/readiness waits, and adapter-owned cleanup
actions.

Signed runtime comparison attempts were then made with:

```text
.build/debug/container-compose-phase6-benchmark \
  --stage10b-runtime-comparison \
  --iterations 1 \
  --project-prefix stage10b \
  --run-label runtime \
  --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml \
  --docker-hub-mirror mirror.gcr.io \
  --evidence-jsonl docs/evidence/linuxpod-stage10b-runtime-comparison/20260613T141551Z-stage10b-runtime-comparison.jsonl \
  --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
```

Both the sandboxed attempt and the outside-sandbox attempt stalled during the
`fullCopy` `up` leg before the first Stage 10B JSONL evidence record was
written. The comparison record was therefore not produced, and the requested
`up`/readiness, rootfs preparation, materialization, block I/O, healthcheck,
job, volume, and cleanup metrics were not measured as a valid fullCopy versus
clonefile comparison.

Cleanup was handled explicitly after the interrupted attempts:

- `container-compose-adapter down --volumes` was run for
  `stage10b-runtime-fullcopy-001`;
- a follow-up adapter-owned Stage 10B state search returned no leftover
  `.container-compose-adapter` paths;
- the intended evidence path
  `docs/evidence/linuxpod-stage10b-runtime-comparison/20260613T141551Z-stage10b-runtime-comparison.jsonl`
  was absent, so no partial evidence file is being treated as proof.

Stage 10B also added a validator guard for any future rerun: host-port and
load-window fields must remain explicitly `notMeasured`, block I/O must be
labeled as whole-run only when phase attribution is unavailable, failed runs
must still prove clean cleanup, and Docker/OrbStack gate pass cannot be
recorded unless it was directly measured.

## Final Verdict

Pause productization. Preserve the Apple-native runtime work as research
evidence, not as a product-readiness claim.

Stage 10B did not show that `clonefile`/`auto` materially improves the real
backend-shaped `LinuxPod` runtime. These required continuation conditions
remain unproven:

- `up` and readiness are significantly lower than `fullCopy`;
- the backend-shaped fixture succeeds as a completed comparison;
- block I/O improves or the remaining block I/O is explained by measured data;
- cleanup and correctness are clean for both strategies;
- no host memory or energy savings are claimed without reliable measurement;
- no Docker/OrbStack gate or parity claim is made unless directly measured.

Because no valid Stage 10B comparison evidence exists, do not recommend Stage
10C repeated warm benchmarking. Keep productization paused and close this
research checkpoint.

## Product Path Not Resumed

Before Stage 10B, the only plausible product path was fast pod recreate plus
rootfs clone/COW, warm ext4 volumes, and a Compose UX minimum set:

- service DNS;
- `depends_on`;
- one-off jobs;
- ports;
- logs/status;
- adapter-owned cleanup.

Stage 10B did not justify resuming that path.

## Non-goals

- Docker Engine clone.
- Full Kubernetes distribution.
- Product reliance on `LinuxPod` hotplug.
- Host RAM or energy savings claims without reliable measurements.

## Checkpoint Boundary

Do not treat this checkpoint as approval to add runtime features, run mutating
runtime probes, make `clonefile` the default, update a parent submodule pointer,
or claim Docker/OrbStack parity.
