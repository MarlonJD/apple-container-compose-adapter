# Runtime Efficiency Benchmark Evidence

**Date:** 2026-06-11
**Scope:** Docker/OrbStack versus Apple `container` repeated runtime measurements before implementation starts.

## Methodology

- Public fixtures only; no private EMSI workloads.
- Images and runtime caches were preserved; this report measures cached-image runtime behavior with fresh benchmark containers and volumes.
- DB scenarios use fresh volumes per iteration.
- Apple backend uses the already discovered PGDATA and DB-IP workarounds; service-name DNS parity is not assumed.
- Percentiles are sample percentiles from the recorded iteration count.
- Runtime stats are one idle snapshot after readiness; process RSS and cgroup memory are collected from inside the container when available.
- No image prune, registry login, Docker build, Apple `container build`, or global cleanup was run.

## Iteration Counts

| Scenario | Runtime | Iterations |
| --- | --- | ---: |
| `backend-shaped` | `apple-container` | 10 |
| `postgres-db-only` | `apple-container` | 20 |
| `simple-web` | `apple-container` | 20 |

## Timing Percentiles

| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `api_port_closed` | 10 | 0.000s | 0.001s | 0.001s | 0.001s |
| `backend-shaped` | `apple-container` | `api_start_command` | 10 | 0.915s | 1.147s | 1.221s | 1.240s |
| `backend-shaped` | `apple-container` | `db_health_wait` | 10 | 1.171s | 1.223s | 1.246s | 1.251s |
| `backend-shaped` | `apple-container` | `db_port_closed` | 10 | 0.000s | 0.000s | 0.000s | 0.000s |
| `backend-shaped` | `apple-container` | `db_start_command` | 10 | 0.873s | 2.249s | 2.813s | 2.954s |
| `backend-shaped` | `apple-container` | `delete` | 10 | 0.189s | 0.324s | 0.383s | 0.398s |
| `backend-shaped` | `apple-container` | `migrate` | 10 | 0.949s | 1.007s | 1.010s | 1.011s |
| `backend-shaped` | `apple-container` | `network_create` | 10 | 0.085s | 0.145s | 0.155s | 0.157s |
| `backend-shaped` | `apple-container` | `network_delete` | 10 | 0.028s | 0.130s | 0.168s | 0.177s |
| `backend-shaped` | `apple-container` | `readiness_probe` | 10 | 1.041s | 1.056s | 1.057s | 1.057s |
| `backend-shaped` | `apple-container` | `seed` | 10 | 0.980s | 1.127s | 1.134s | 1.136s |
| `backend-shaped` | `apple-container` | `stop` | 10 | 5.468s | 8.421s | 8.467s | 8.479s |
| `backend-shaped` | `apple-container` | `volume_create` | 10 | 0.512s | 3.989s | 5.765s | 6.209s |
| `backend-shaped` | `apple-container` | `volume_delete` | 10 | 0.070s | 0.085s | 0.093s | 0.095s |
| `postgres-db-only` | `apple-container` | `delete` | 20 | 0.118s | 0.136s | 0.157s | 0.163s |
| `postgres-db-only` | `apple-container` | `health_wait` | 20 | 1.166s | 1.210s | 1.212s | 1.212s |
| `postgres-db-only` | `apple-container` | `start_command` | 20 | 0.845s | 0.935s | 0.980s | 0.991s |
| `postgres-db-only` | `apple-container` | `stop` | 20 | 0.171s | 0.597s | 2.728s | 3.260s |
| `postgres-db-only` | `apple-container` | `volume_create` | 20 | 0.505s | 0.972s | 1.321s | 1.408s |
| `postgres-db-only` | `apple-container` | `volume_delete` | 20 | 0.075s | 0.094s | 0.097s | 0.098s |
| `simple-web` | `apple-container` | `delete` | 20 | 0.125s | 0.141s | 0.144s | 0.145s |
| `simple-web` | `apple-container` | `port_closed` | 20 | 0.000s | 0.000s | 0.000s | 0.000s |
| `simple-web` | `apple-container` | `readiness_probe` | 20 | 0.015s | 0.373s | 5.695s | 7.026s |
| `simple-web` | `apple-container` | `start_command` | 20 | 0.868s | 1.037s | 1.312s | 1.381s |
| `simple-web` | `apple-container` | `stop` | 20 | 0.232s | 5.254s | 5.455s | 5.506s |

## Memory And CPU Percentiles

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `db` | runtime memory | 10 | 188.15MiB | 190.62MiB | 192.10MiB | 192.47MiB |
| `backend-shaped` | `apple-container` | `db` | process VmRSS | 10 | 26.57MiB | 26.69MiB | 26.71MiB | 26.71MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup current | 10 | 188.45MiB | 190.85MiB | 192.27MiB | 192.62MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup peak | 10 | 200.14MiB | 202.87MiB | 204.28MiB | 204.63MiB |
| `backend-shaped` | `apple-container` | `db` | block read | 10 | 81.05MiB | 83.37MiB | 84.89MiB | 85.27MiB |
| `backend-shaped` | `apple-container` | `db` | block write | 10 | 50.61MiB | 50.62MiB | 50.62MiB | 50.62MiB |
| `backend-shaped` | `apple-container` | `db` | net read | 10 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `backend-shaped` | `apple-container` | `db` | net write | 10 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `db` | disk /var/lib/postgresql/data | 10 | 45.79MiB | 45.79MiB | 45.79MiB | 45.79MiB |
| `backend-shaped` | `apple-container` | `db` | runtime CPU snapshot | 10 | 0.05% | 0.07% | 0.07% | 0.07% |
| `backend-shaped` | `apple-container` | `db` | load CPU snapshot | 10 | 57.34% | 71.09% | 71.43% | 71.51% |
| `backend-shaped` | `apple-container` | `api` | runtime memory | 10 | 31.59MiB | 33.79MiB | 35.21MiB | 35.56MiB |
| `backend-shaped` | `apple-container` | `api` | process VmRSS | 10 | 18.72MiB | 18.81MiB | 18.82MiB | 18.82MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup current | 10 | 33.10MiB | 35.34MiB | 36.66MiB | 36.99MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup peak | 10 | 33.36MiB | 35.59MiB | 36.91MiB | 37.24MiB |
| `backend-shaped` | `apple-container` | `api` | block read | 10 | 18.12MiB | 20.40MiB | 21.89MiB | 22.26MiB |
| `backend-shaped` | `apple-container` | `api` | block write | 10 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | net read | 10 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `backend-shaped` | `apple-container` | `api` | net write | 10 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | runtime CPU snapshot | 10 | 0.02% | 0.02% | 0.02% | 0.02% |
| `backend-shaped` | `apple-container` | `api` | load CPU snapshot | 10 | 38.70% | 49.25% | 50.47% | 50.77% |
| `backend-shaped` | `apple-container` | `api` | load HTTP requests | 10 | 2993 | 3460 | 3512 | 3525 |
| `postgres-db-only` | `apple-container` | `db` | runtime memory | 20 | 187.01MiB | 187.68MiB | 190.50MiB | 191.20MiB |
| `postgres-db-only` | `apple-container` | `db` | process VmRSS | 20 | 26.57MiB | 26.73MiB | 26.76MiB | 26.77MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup current | 20 | 187.45MiB | 187.92MiB | 190.89MiB | 191.63MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup peak | 20 | 200.44MiB | 200.93MiB | 203.70MiB | 204.40MiB |
| `postgres-db-only` | `apple-container` | `db` | block read | 20 | 81.05MiB | 81.26MiB | 84.46MiB | 85.26MiB |
| `postgres-db-only` | `apple-container` | `db` | block write | 20 | 50.41MiB | 50.41MiB | 50.41MiB | 50.41MiB |
| `postgres-db-only` | `apple-container` | `db` | net read | 20 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `postgres-db-only` | `apple-container` | `db` | net write | 20 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `postgres-db-only` | `apple-container` | `db` | disk /var/lib/postgresql/data | 20 | 45.70MiB | 45.70MiB | 45.70MiB | 45.70MiB |
| `postgres-db-only` | `apple-container` | `db` | runtime CPU snapshot | 20 | 0.05% | 0.06% | 0.07% | 0.07% |
| `postgres-db-only` | `apple-container` | `db` | load CPU snapshot | 20 | 67.59% | 72.20% | 73.38% | 73.67% |
| `simple-web` | `apple-container` | `web` | runtime memory | 20 | 14.59MiB | 14.99MiB | 17.46MiB | 18.08MiB |
| `simple-web` | `apple-container` | `web` | process VmRSS | 20 | 5.44MiB | 5.52MiB | 5.53MiB | 5.53MiB |
| `simple-web` | `apple-container` | `web` | cgroup current | 20 | 15.13MiB | 16.74MiB | 18.48MiB | 18.91MiB |
| `simple-web` | `apple-container` | `web` | cgroup peak | 20 | 15.87MiB | 16.79MiB | 19.24MiB | 19.86MiB |
| `simple-web` | `apple-container` | `web` | block read | 20 | 9.13MiB | 9.32MiB | 12.26MiB | 13.00MiB |
| `simple-web` | `apple-container` | `web` | block write | 20 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | net read | 20 | 0.00MiB | 0.01MiB | 0.02MiB | 0.02MiB |
| `simple-web` | `apple-container` | `web` | net write | 20 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | disk /usr/share/nginx/html | 20 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | disk /var/cache/nginx | 20 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `simple-web` | `apple-container` | `web` | runtime CPU snapshot | 20 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `apple-container` | `web` | load CPU snapshot | 20 | 1.10% | 7.11% | 9.10% | 9.60% |
| `simple-web` | `apple-container` | `web` | load HTTP requests | 20 | 1476 | 3320 | 4206 | 4427 |

## Apple Runtime Lifecycle

- `container system start`: 0, 0.060s.
- `container system stop`: 0, 0.042s.

## Evidence Files

- Raw JSONL: `docs/evidence/runtime-efficiency/20260611T184900Z-runtime-efficiency-raw.jsonl`
- Summary JSON: `docs/evidence/runtime-efficiency/20260611T184900Z-runtime-efficiency-summary.json`

## Harness Command

```text
scripts/benchmark_runtime_efficiency.py --runtimes apple --simple-iterations 20 --db-iterations 20 --backend-iterations 10
```

## Cleanup Scope

The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.
