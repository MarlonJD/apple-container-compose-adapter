# Runtime Efficiency Benchmark Evidence

**Date:** 2026-06-11
**Scope:** Docker/OrbStack versus Apple `container` repeated benchmark evidence before starting implementation.
**Evidence report:** [Combined Runtime Efficiency Benchmark Report](../../evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-report.md)

## Verdict

Do not claim that Apple `container` is more efficient than Docker/OrbStack overall, and do not claim Docker Compose replacement readiness.

Apple `container` remains promising for simple cached web workloads, but backend-shaped replacement is not proven. Postgres process RSS is nearly identical between Docker and Apple, while Apple runtime/cgroup memory is much higher. Apple repeated-run lifecycle also required explicit readiness, unique resource names, and port-release waits to avoid XPC/bootstrap, stale state, and address-in-use failures.

## Data Set

| Runtime | `simple-web` | `postgres-db-only` | `backend-shaped` |
| --- | ---: | ---: | ---: |
| Docker/OrbStack | 50 iterations | 50 iterations | 20 iterations |
| Apple `container` | 20 iterations | 20 iterations | 10 iterations |

The Apple run uses PGDATA and DB-IP workarounds for backend-shaped behavior. It is not Compose parity.

## Key Timing Results

| Scenario | Runtime | Metric | p50 | p95 | p99 |
| --- | --- | --- | ---: | ---: | ---: |
| `simple-web` | Docker/OrbStack | `up --wait` | `5.795s` | `5.911s` | `6.057s` |
| `simple-web` | Apple `container` | `container run` command | `0.868s` | `1.037s` | `1.312s` |
| `simple-web` | Apple `container` | readiness wait | `0.015s` | `0.373s` | `5.695s` |
| `postgres-db-only` | Docker/OrbStack | start command | `0.165s` | `0.236s` | `0.286s` |
| `postgres-db-only` | Apple `container` | start command | `0.845s` | `0.935s` | `0.980s` |
| `backend-shaped` | Docker/OrbStack | `up --wait` | `12.859s` | `13.144s` | `13.354s` |
| `backend-shaped` | Apple `container` | DB start command | `0.873s` | `2.249s` | `2.813s` |

Comparable startup/readiness totals and stop/cleanup totals from the same raw
data:

| Scenario | Runtime | Startup/readiness p50 | p95 | p99 | Stop/cleanup p50 | p95 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `simple-web` | Docker/OrbStack | `5.795s` | `5.911s` | `6.057s` | `0.368s` | `0.604s` |
| `simple-web` | Apple `container` | `0.910s` | `1.727s` | `6.645s` | `0.352s` | `5.350s` |
| `postgres-db-only` | Docker/OrbStack | `2.357s` | `2.543s` | `3.038s` | `0.307s` | `0.523s` |
| `postgres-db-only` | Apple `container` | `2.016s` | `2.093s` | `2.147s` | `0.367s` | `0.769s` |
| `backend-shaped` | Docker/OrbStack | `12.859s` | `13.144s` | `13.354s` | `10.731s` | `10.845s` |
| `backend-shaped` | Apple `container` | `6.533s` | `11.690s` | `14.224s` | `5.839s` | `8.699s` |

## Key Resource Results

| Scenario | Runtime | Role | Metric | p50 | p95 | p99 |
| --- | --- | --- | --- | ---: | ---: | ---: |
| `simple-web` | Docker/OrbStack | web | cgroup memory | `17.18MiB` | `20.72MiB` | `23.53MiB` |
| `simple-web` | Apple `container` | web | cgroup memory | `15.13MiB` | `16.74MiB` | `18.48MiB` |
| `postgres-db-only` | Docker/OrbStack | db | process RSS | `26.68MiB` | `26.84MiB` | `26.84MiB` |
| `postgres-db-only` | Apple `container` | db | process RSS | `26.57MiB` | `26.73MiB` | `26.76MiB` |
| `postgres-db-only` | Docker/OrbStack | db | cgroup memory | `65.14MiB` | `71.39MiB` | `88.00MiB` |
| `postgres-db-only` | Apple `container` | db | cgroup memory | `187.45MiB` | `187.92MiB` | `190.89MiB` |
| `backend-shaped` | Docker/OrbStack | db | cgroup memory | `67.33MiB` | `96.63MiB` | `96.73MiB` |
| `backend-shaped` | Apple `container` | db | cgroup memory | `188.45MiB` | `190.85MiB` | `192.27MiB` |
| `backend-shaped` | Docker/OrbStack | api | cgroup memory | `19.07MiB` | `25.09MiB` | `34.17MiB` |
| `backend-shaped` | Apple `container` | api | cgroup memory | `33.10MiB` | `35.34MiB` | `36.66MiB` |

Postgres data directory footprint is effectively the same: about `45.70MiB` to `45.79MiB` across Docker and Apple. Apple reported higher DB block reads, while DB writes were in the same broad range.

## CPU, Throughput, Errors, And Disk I/O

Load CPU must be read together with completed work. Apple often used less CPU,
but it also completed less HTTP/SQL work in the same synthetic load window.

| Scenario | Runtime | Role | Load CPU p50 | Completed work p50 | Load errors p50 |
| --- | --- | --- | ---: | ---: | ---: |
| `simple-web` | Docker/OrbStack | web | `28.08%` | `4882` HTTP requests | `0` |
| `simple-web` | Apple `container` | web | `1.10%` | `1476` HTTP requests | `4` |
| `postgres-db-only` | Docker/OrbStack | db | `79.97%` | `498` SQL loops | n/a |
| `postgres-db-only` | Apple `container` | db | `67.59%` | `484` SQL loops | n/a |
| `backend-shaped` | Docker/OrbStack | api | `70.57%` | `4627` HTTP requests | `0` |
| `backend-shaped` | Apple `container` | api | `38.70%` | `2993` HTTP requests | `0` |
| `backend-shaped` | Docker/OrbStack | db | `107.97%` | `568` SQL loops | n/a |
| `backend-shaped` | Apple `container` | db | `57.34%` | `484` SQL loops | n/a |

Persistent DB disk footprint is effectively identical, but Apple reports much
higher DB block reads in these runs.

| Scenario | Runtime | Role | Data footprint p50 | Block read p50 | Block write p50 |
| --- | --- | --- | ---: | ---: | ---: |
| `postgres-db-only` | Docker/OrbStack | db | `45.70MiB` | `0.00MiB` | `55.03MiB` |
| `postgres-db-only` | Apple `container` | db | `45.70MiB` | `81.05MiB` | `50.41MiB` |
| `backend-shaped` | Docker/OrbStack | db | `45.78MiB` | `3.09MiB` | `55.50MiB` |
| `backend-shaped` | Apple `container` | db | `45.79MiB` | `81.05MiB` | `50.61MiB` |

## Interpretation

- Simple web: Apple `container` is promising on memory and command startup, but readiness p99 and stop p95 show lifecycle tail latency.
- Database: the Postgres process itself is not larger on Apple; the extra memory is in runtime/cgroup accounting or per-container VM overhead.
- CPU: idle snapshots are low for both runtimes. Synthetic load CPU is not directly comparable as throughput because Apple frequently completed less work during the same load window.
- Disk: DB data footprint is similar. Apple DB block reads are higher in the runtime-reported snapshot.
- Reliability: repeated Apple runs initially failed without explicit lifecycle waits. The adapter must own readiness polling, port-release waits, cleanup verification, and retry diagnostics before any replacement claim.

## Decision

Proceed with the adapter only as a compatibility implementation experiment, not as an efficiency replacement claim. Start with the no-side-effect CLI/`doctor` foundation, then dry-run planning and diagnostics. Do not claim Docker/OrbStack can be replaced for backend-shaped daily development until service discovery, named-volume behavior, resource tuning, and lifecycle stability are implemented and remeasured.
