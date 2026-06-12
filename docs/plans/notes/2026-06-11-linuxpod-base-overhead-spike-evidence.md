# LinuxPod Base Overhead Spike Evidence

**Date:** 2026-06-11
**Linked plan:** [LinuxPod Base Overhead Spike Plan](../completed/2026-06-11-linuxpod-base-overhead-spike-plan.md)
**Decision:** `promising`
**Primary evidence:** [LinuxPod Base Overhead Evidence Report](../../evidence/linuxpod-base-overhead/20260611T203449Z-linuxpod-base-overhead-report.md)
**Host RSS follow-up:** [LinuxPod Host RSS Evidence Report](../../evidence/linuxpod-base-overhead/20260611T210811Z-linuxpod-base-overhead-hostrss-report.md)
**Additional evidence:** [Postgres API Boot Probe Observation](../../evidence/linuxpod-base-overhead/20260611T204739Z-postgres-api-boot-probe-observation.md)

## Decision

LinuxPod is **promising for the base-overhead hypothesis**, but not ready to
change the main Container Compose Adapter runtime strategy.

The strongest single-service result is `postgres-only`: LinuxPod reported
`124.75MiB` cgroup current memory for Postgres, versus the existing public Apple
`container` CLI baseline of `187.45MiB`. That is about `62.70MiB` lower, or a
`33.45%` reduction on the closest comparable guest/cgroup metric.

The multi-service smoke also supports continued LinuxPod research. With a
Postgres DB plus a second Postgres-image client fixture in the same LinuxPod,
`postgres-api` reported `137.13MiB` cgroup current memory. The marginal increase
over `postgres-only` was only `12.38MiB`, not another VM-sized `~187MiB` cost.

Host RSS was investigated in a follow-up run by sampling the signed runner
process with `/bin/ps` while the VM was alive. The values were not usable as VM
footprint proof: `idle-pod` reported `47.94MiB`, while `postgres-only` and
`postgres-api` reported lower values of `36.42MiB` and `35.67MiB`. Because the
host RSS signal does not scale with guest workload or cgroup memory, it likely
does not capture the LinuxPod VM's resident footprint in a comparable way.

The main adapter should therefore stay on the public Apple `container` CLI
dry-run-first path. LinuxPod deserves a separate future backend plan only after
host-side VM memory, service semantics, and repeated lifecycle behavior are
measured with a reliable host-side source.

## Source And API Feasibility

Official source inspected from
`/private/tmp/apple-container-source-check/containerization-main`:

- `Sources/Containerization/LinuxPod.swift`
- `Sources/Integration/PodTests.swift`
- `examples/ctr-example/Package.swift`
- `examples/ctr-example/Sources/ctr-example/main.swift`

Relevant findings:

- `LinuxPod` is an experimental public API that creates one VM and can add
  multiple container root filesystems/processes sharing CPU, memory, and
  network resources.
- `LinuxPod.statistics()` exposes per-container process, memory, CPU, block
  I/O, network, and memory event categories through `ContainerStatistics`.
- Integration tests cover multiple containers, exec, stats, per-container
  limits, filesystem isolation, optional shared PID namespace, and cleanup via
  `pod.stop()`.
- Direct SwiftPM use is viable: the isolated spike imports
  `apple/containerization` `0.26.5`, builds, and dry-runs all three modes.

## Spike Artifacts

Created:

- `experiments/linuxpod-base-overhead/Package.swift`
- `experiments/linuxpod-base-overhead/Package.resolved`
- `experiments/linuxpod-base-overhead/Sources/LinuxPodBaseOverheadSpike/main.swift`
- `experiments/linuxpod-base-overhead/README.md`
- `experiments/linuxpod-base-overhead/linuxpod-base-overhead.entitlements`
- `scripts/summarize_linuxpod_base_overhead.py`
- `docs/evidence/linuxpod-base-overhead/20260611T202028Z-linuxpod-base-overhead-raw.jsonl`
- `docs/evidence/linuxpod-base-overhead/20260611T202028Z-linuxpod-base-overhead-summary.json`
- `docs/evidence/linuxpod-base-overhead/20260611T202028Z-linuxpod-base-overhead-report.md`
- `docs/evidence/linuxpod-base-overhead/20260611T203449Z-linuxpod-base-overhead-raw.jsonl`
- `docs/evidence/linuxpod-base-overhead/20260611T203449Z-linuxpod-base-overhead-summary.json`
- `docs/evidence/linuxpod-base-overhead/20260611T203449Z-linuxpod-base-overhead-report.md`
- `docs/evidence/linuxpod-base-overhead/20260611T210811Z-linuxpod-base-overhead-hostrss-raw.jsonl`
- `docs/evidence/linuxpod-base-overhead/20260611T210811Z-linuxpod-base-overhead-hostrss-summary.json`
- `docs/evidence/linuxpod-base-overhead/20260611T210811Z-linuxpod-base-overhead-hostrss-report.md`

`Package.resolved` pins `apple/containerization` `0.26.5` at revision
`636eef0eff00e451de6d5d426e6a6785b90b44e2`.

## Evidence Summary

Primary runtime JSONL records: `10`

| Scenario | Measured | Blocked | Key result |
| --- | ---: | ---: | --- |
| `idle-pod` | 1 | 1 | `1.81MiB` cgroup current, `0.78MiB` process RSS, cleanup `pod-stopped,owned-state-deleted` |
| `postgres-only` | 1 | 1 | `124.75MiB` cgroup current, `26.57MiB` process RSS, `38.50MiB` DB footprint, cleanup `pod-stopped,owned-state-deleted` |
| `postgres-api` | 1 | 5 | `137.13MiB` cgroup current, `27.36MiB` process RSS, `38.50MiB` DB footprint, cleanup `pod-stopped,owned-state-deleted` |

Host RSS follow-up records: `3`, all measured with login-free public mirror
references:

- `mirror.gcr.io/library/alpine:3.20`
- `mirror.gcr.io/library/postgres:16-alpine`

Blocked records document early missing-entitlement attempts, a runner overflow
while summing multiple unlimited cgroup limits, and Docker Hub unauthenticated
pull-rate `429` responses. Registry login was not run.

## Measured Runtime Metrics

Measured `idle-pod` details:

- cgroup current: `1.81MiB`
- process RSS: `0.77MiB` to `0.78MiB`
- host runner RSS follow-up: `47.94MiB`
- create/start: `0.428s` to `0.666s`
- stop/delete: `0.022s` to `0.038s`
- block read/write: `1.58MiB` / `0`
- load completed work/errors: `0` / `0`

Measured `postgres-only` details:

- cgroup current: `124.75MiB` to `125.06MiB`
- process RSS: `26.57MiB` to `26.64MiB`
- host runner RSS follow-up: `36.42MiB`
- DB data footprint: `38.50MiB`
- readiness: `1.096s` to `1.100s`
- SQL probe: `0.041s` to `0.056s`
- stop/delete: about `0.101s`
- block read/write: `64.27MiB` / `38.87MiB`
- load completed work/errors: `1` / `0`

Measured `postgres-api` details:

- cgroup current: `137.13MiB` to `137.35MiB`
- cgroup peak: about `148MiB`
- process RSS: `27.36MiB`
- host runner RSS follow-up: `35.67MiB`
- DB data footprint: `38.50MiB`
- SQL probe from client fixture to DB over `127.0.0.1`: `0.045s` to `0.051s`
- process count: `13`
- block read/write: about `75MiB` / `38.88MiB`
- load completed work/errors: `1` / `0`

## Baseline Comparison

Existing baseline:
[Combined Runtime Efficiency Benchmark Report](../../evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-report.md)

Relevant baseline values:

- Apple `container` `postgres-db-only` cgroup current p50: `187.45MiB`.
- Apple `container` `postgres-db-only` runtime memory p50: `187.01MiB`.
- Docker/OrbStack `postgres-db-only` cgroup current p50: `65.14MiB`.
- Docker/OrbStack `postgres-db-only` runtime memory p50: `17.21MiB`.
- Postgres process RSS is similar: Apple p50 `26.57MiB`, Docker p50
  `26.68MiB`, LinuxPod `postgres-only` smoke `26.57MiB`.
- Apple `container` `backend-shaped` DB plus API cgroup current p50 is about
  `221.55MiB` (`188.45MiB` DB + `33.10MiB` API).
- LinuxPod `postgres-api` fixture cgroup current was about `137MiB`, but this
  is a client fixture, not the same API workload as the baseline.

LinuxPod's single Postgres cgroup result is materially below the public Apple
CLI path and near-identical on process RSS, which supports the hypothesis that
some of the Apple CLI DB memory gap is runtime/containerization overhead rather
than Postgres itself. LinuxPod still remains materially above Docker/OrbStack
on cgroup current memory.

The `postgres-api` result supports shared-runtime research because the marginal
second-container cgroup increase was about `12MiB`, but it does not yet prove
backend-shaped API parity.

The host runner RSS sampler did not produce a useful VM-overhead comparison.
Those values are recorded as evidence that this host-side method is insufficient,
not as proof that LinuxPod host memory is lower than Apple CLI.

## Repeats And Skips

Publication-grade Phase 4 repeat runs were skipped.

Reasons:

- The valid `postgres-only` smoke crossed the 30 percent reduction gate versus
  Apple CLI cgroup current memory.
- The valid `postgres-api` smoke showed a second-container marginal cost that is
  process-sized rather than VM-sized.
- Host runtime RSS still lacks a reliable source even after runner-process RSS
  sampling.
- Registry login, prune, global cleanup, and private EMSI workloads were out of
  scope and were not run.

## Commands Not Run

Not run:

- registry login;
- Docker Hub credential changes;
- private EMSI workloads;
- `container system stop`;
- `container system reset`;
- `container image prune`;
- `docker system prune`;
- global cleanup outside `cca-linuxpod-spike-*`;
- 3-repeat or 10+ publication-grade LinuxPod benchmark suites.

## Cleanup Status

All JSONL runtime records report cleanup as `owned-state-deleted`; measured
records also report `pod-stopped`.

One intermediate `postgres-api` run reached boot and SQL-probe success but was
cut off before JSON metrics and cleanup reporting. Its spike-owned runtime
directory was later verified as absent. The final cleanup check showed only the
empty runtime root:

```text
docs/evidence/linuxpod-base-overhead/runtime
```

The runtime root is ignored by `.gitignore` because rootfs files and image-store
blobs are temporary cleanup targets, not durable evidence.

## Recommendation

Keep the main Container Compose Adapter implementation on the public Apple
`container` CLI dry-run-first path. Do not switch the main adapter to LinuxPod
yet.

Open a separate future LinuxPod backend plan only if the product direction needs
shared-VM behavior. That plan should start with:

- a reliable host-side VM/runtime memory measurement source;
- a realistic API workload, not only a Postgres client fixture;
- repeated lifecycle measurements once host-side memory and service semantics
  are observable;
- a cached or mirrored public-image fixture strategy that avoids Docker Hub rate
  limits without registry login.

Do not claim Docker/OrbStack replacement or backend-stack parity from this
spike. The safe claim is narrower: **LinuxPod looks promising for reducing the
public Apple CLI single-DB cgroup memory overhead and for avoiding VM-sized
second-service cost, but host-VM evidence and realistic API parity remain
incomplete.**

## Verification

Passed:

- `swift build` in `experiments/linuxpod-base-overhead`
- direct binary dry-run for `idle-pod`, `postgres-only`, and `postgres-api`
  with mirror image references
- signed runtime smoke for `idle-pod`
- signed runtime smoke for `postgres-only`
- signed runtime smoke for `postgres-api` using login-free public mirror
  references after Docker Hub `429`
- signed host-RSS follow-up smoke for `idle-pod`, `postgres-only`, and
  `postgres-api`
- `python3 scripts/summarize_linuxpod_base_overhead.py ...`
- `git diff --check`

Runtime smoke used only `cca-linuxpod-spike-*` owned resources. No private EMSI
workloads, registry login, prune, global cleanup, branch operation, commit, push,
or parent submodule pointer update was performed.
