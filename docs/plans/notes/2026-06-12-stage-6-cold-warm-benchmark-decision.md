# Stage 6 Cold And Image-store-seeded Benchmark Decision

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)
**Decision:** `stage6-image-store-only-warming-insufficient`

## Corrected Interpretation

Stage 6 solved Docker Hub rate-limit exposure for measurement and made the
benchmark stable, but image-store-only warming did not make LinuxPod Compose-level competitive.

The final successful run measured an **image-store-seeded fresh runtime**, not
a persistent project LinuxPod. It proves only that registry-free measurement and
image-store seeding are insufficient by themselves. It does not measure reuse
of the project LinuxPod, rootfs/initfs caches, named volumes, existing pod
lifecycle, or service hotplug/recreate.

The next meaningful experiment is:

```text
persistent project LinuxPod + rootfs/initfs/volume cache + service hotplug/reuse
```

## Lifecycle Terms

Use these labels for Stage 6 and later benchmark evidence:

| Lifecycle | Meaning |
| --- | --- |
| `cold` | No pre-seeded image store; rootfs, initfs, volumes, and pod lifecycle are fresh. |
| `image-store-seeded-fresh-runtime` | A prepared image store is copied before `up`; rootfs, initfs, volumes, and pod lifecycle are still fresh. |
| `persistent-warm-project-runtime` | Future-only target where the project LinuxPod exists, rootfs/initfs caches hit, named volumes already exist, and services are recreated, reused, or hotplugged. |

Older JSONL rows in this evidence package still use legacy fields such as
`lifecycle=warm`, `target_name=future LinuxPod warm`, `imageCacheStatus=hit`,
and `projectRuntimeExistedBeforeRun=true`. Those rows are immutable historical
evidence and should be read as **pre-metadata-correction** records. The seed
copy created the runtime directory before the benchmark recorded
`projectRuntimeExistedBeforeRun`, so that field is not proof of project runtime
reuse.

## Evidence

Fixture path:
[compose.yaml](../../evidence/fixtures/backend-shaped/compose.yaml).

No-side-effect dry-run evidence was captured before the readiness-budget fix:
[20260612T111539Z-stage6-backend-shaped-up-dry-run.jsonl](../../evidence/linuxpod-stage6-benchmark/20260612T111539Z-stage6-backend-shaped-up-dry-run.jsonl).
It still says `Wait for service_healthy with timeout 2s`; treat it as
pre-fix/stale wording. Current code describes this as a readiness wait budget,
and the executor still does not fully honor Compose healthcheck interval,
per-probe timeout, retries, and start-period semantics.

Cold evidence:
[20260612T111539Z-stage6-cold-5.jsonl](../../evidence/linuxpod-stage6-benchmark/20260612T111539Z-stage6-cold-5.jsonl).

Final image-store-seeded fresh runtime evidence:
[20260612T125100Z-stage6-warm-5-escalated-readiness.jsonl](../../evidence/linuxpod-stage6-benchmark/20260612T125100Z-stage6-warm-5-escalated-readiness.jsonl).
The filename and legacy JSON labels say `warm`, but the measured lifecycle was
image-store-seeded fresh runtime.

## Cold Results

Five cold iterations were requested. Three measured cleanly; two failed during
service image/rootfs preparation after Docker Hub returned unauthenticated
`429 Too Many Requests` responses. Cleanup removed adapter-owned state after
each iteration.

Cold p50 from the measured iterations: up `101.2s`, cleanup `0.14s`, guest
cgroup current `189.7MiB`, block read `105.4MiB`, block write `51.1MiB`.

## Image-store-seeded Fresh Runtime Results

The final run measured `5/5` successful iterations with `measuredIterations=5`
and `failureCount=0`.
The old JSONL summary reports `imageCacheStatus=hit`; with the corrected model
this should be read as a seed image-store hit, not as rootfs/initfs/volume/pod
warmth.

Observed state still showed:

- `rootfsCacheStatus=miss`
- `initfsCacheStatus=miss`
- `volumeExistedBeforeRun=false`
- no actual pod reuse evidence

P50 from the final run: up `44.3s`, cleanup `0.11s`, guest cgroup current
`189.7MiB`, block read `105.4MiB`, block write `51.0MiB`, CPU `0.89s`, process
count `7`.

The legacy `cgroupMemoryLimitBytes=18446744073709551612` value is a metadata
bug from wrapping unlimited cgroup limits and must not be used. Corrected code
represents effectively unlimited cgroup limits separately.

## Registry And Seed Safety

The mirror plus `linux/arm64` seed image store solved registry throttling for measurement
without Docker Hub login, Keychain changes, registry credential changes, or
global cache cleanup. Mirror digest checks were operator-checked on
2026-06-12, but raw HEAD/manifest evidence is not attached to this note.

Seed image stores are external/local benchmark cache state. They must not be
included in evidence packages by default, and benchmark cleanup must not delete
non-adapter-owned seed sources.

## Unmeasured Gaps

Stage 6 did not measure localhost developer access from macOS. Host port
publishing, host-port TTFB, load-window duration, completed requests, and
request failure count are unmeasured.

`status` is currently a local control-plane state check, and `logs` is
effectively a control-plane/no-op timing path until real log retrieval is
implemented. Near-zero status/logs durations are not performance claims.

Host physical memory remains `blocked` by the Phase 5 source decision; use only
guest-side metrics from this note.

## Viability Gate

Baseline: Docker Compose `start_to_wait` `12.859s`; DB+API guest memory
`86.4MiB`; block read `4.86MiB`; block write `55.50MiB`.

| Metric | Image-store-seeded fresh runtime p50 | Docker/OrbStack baseline | Gate | Result |
| --- | ---: | ---: | --- | --- |
| Backend guest cgroup current | `189.7MiB` | `86.4MiB` | Within `50%` | Fail, `2.20x` Docker baseline |
| Host physical footprint | `blocked` | Not comparable | Reliable source and within `50%` | Blocked by Phase 5 |
| Startup/readiness | `44.3s` up duration | `12.859s` Docker Compose `start_to_wait` | Within `50%` | Fail, `3.44x` Docker baseline |
| Block read | `105.4MiB` | `4.86MiB` | No worse than `2x` unless absolute delta is below `10MiB` | Fail, `21.7x` Docker baseline |
| Block write | `51.0MiB` | `55.50MiB` | Same broad range | Pass |
| Failure count | `0/5` | Required `0/5` | No failures | Pass |
| Cleanup | No adapter-owned project runtime state after every iteration | Required clean state | Pass |

## Next Experiment

Do not reposition the project as abandoned. Do not switch runtime target. Do
not add Docker-compatible, Colima, Podman, Lima, Rancher Desktop, Docker
Desktop, OrbStack, or container-compose backends.

The next runtime experiment, if explicitly approved, should isolate:

- rootfs-cache hit runtime
- initfs-cache hit runtime
- warm preserved volume
- persistent pod or hotplug
- all-warm project runtime

Required metrics: startup/readiness, rootfs prep duration, initfs prep
duration, volume create/reuse duration, pod create/reuse duration, container
start duration, healthcheck attempts/duration, cgroup current/peak, process
RSS, block read/write, data footprint, host port TTFB, completed work per load
window, and cleanup result.

## Verification

- `swift test` passed before runtime work (`86` tests).
- `git diff --check` passed before runtime work.
- Stage 6 dry-run evidence exists but is marked pre-readiness-budget-fix.
- Signed harness binary with `com.apple.security.virtualization` was verified.
- Final signed, escalated image-store-seeded fresh runtime run passed `5/5`
  with
  [20260612T125100Z-stage6-warm-5-escalated-readiness.jsonl](../../evidence/linuxpod-stage6-benchmark/20260612T125100Z-stage6-warm-5-escalated-readiness.jsonl).
- Final historical verification before this correction: `swift test` passed
  with `90` tests, and `git diff --check` passed.
