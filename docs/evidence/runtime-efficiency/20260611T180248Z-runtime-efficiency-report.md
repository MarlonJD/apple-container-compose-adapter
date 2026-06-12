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
| `backend-shaped` | `docker-compose` | 1 |
| `postgres-db-only` | `docker-run` | 1 |
| `simple-web` | `docker-compose` | 1 |

## Timing Percentiles

| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `docker-compose` | `readiness_probe` | 1 | 0.013s | 0.013s | 0.013s | 0.013s |
| `backend-shaped` | `docker-compose` | `start_to_wait` | 1 | 13.194s | 13.194s | 13.194s | 13.194s |
| `backend-shaped` | `docker-compose` | `stop_delete` | 1 | 10.704s | 10.704s | 10.704s | 10.704s |
| `postgres-db-only` | `docker-run` | `delete` | 1 | 0.101s | 0.101s | 0.101s | 0.101s |
| `postgres-db-only` | `docker-run` | `health_wait` | 1 | 2.210s | 2.210s | 2.210s | 2.210s |
| `postgres-db-only` | `docker-run` | `start_command` | 1 | 0.182s | 0.182s | 0.182s | 0.182s |
| `postgres-db-only` | `docker-run` | `stop` | 1 | 0.148s | 0.148s | 0.148s | 0.148s |
| `postgres-db-only` | `docker-run` | `volume_create` | 1 | 0.049s | 0.049s | 0.049s | 0.049s |
| `postgres-db-only` | `docker-run` | `volume_delete` | 1 | 0.045s | 0.045s | 0.045s | 0.045s |
| `simple-web` | `docker-compose` | `readiness_probe` | 1 | 0.046s | 0.046s | 0.046s | 0.046s |
| `simple-web` | `docker-compose` | `start_to_wait` | 1 | 5.866s | 5.866s | 5.866s | 5.866s |
| `simple-web` | `docker-compose` | `stop_delete` | 1 | 0.313s | 0.313s | 0.313s | 0.313s |

## Memory And CPU Percentiles

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `docker-compose` | `db` | runtime memory | 1 | 18.12MiB | 18.12MiB | 18.12MiB | 18.12MiB |
| `backend-shaped` | `docker-compose` | `db` | process VmRSS | 1 | 26.54MiB | 26.54MiB | 26.54MiB | 26.54MiB |
| `backend-shaped` | `docker-compose` | `db` | cgroup current | 1 | 67.80MiB | 67.80MiB | 67.80MiB | 67.80MiB |
| `backend-shaped` | `docker-compose` | `db` | cgroup peak | 1 | 76.40MiB | 76.40MiB | 76.40MiB | 76.40MiB |
| `backend-shaped` | `docker-compose` | `db` | runtime CPU snapshot | 1 | 2.95% | 2.95% | 2.95% | 2.95% |
| `backend-shaped` | `docker-compose` | `api` | runtime memory | 1 | 27.75MiB | 27.75MiB | 27.75MiB | 27.75MiB |
| `backend-shaped` | `docker-compose` | `api` | process VmRSS | 1 | 18.76MiB | 18.76MiB | 18.76MiB | 18.76MiB |
| `backend-shaped` | `docker-compose` | `api` | cgroup current | 1 | 31.95MiB | 31.95MiB | 31.95MiB | 31.95MiB |
| `backend-shaped` | `docker-compose` | `api` | cgroup peak | 1 | 43.35MiB | 43.35MiB | 43.35MiB | 43.35MiB |
| `backend-shaped` | `docker-compose` | `api` | runtime CPU snapshot | 1 | 0.02% | 0.02% | 0.02% | 0.02% |
| `postgres-db-only` | `docker-run` | `db` | runtime memory | 1 | 52.60MiB | 52.60MiB | 52.60MiB | 52.60MiB |
| `postgres-db-only` | `docker-run` | `db` | process VmRSS | 1 | 26.61MiB | 26.61MiB | 26.61MiB | 26.61MiB |
| `postgres-db-only` | `docker-run` | `db` | cgroup current | 1 | 105.09MiB | 105.09MiB | 105.09MiB | 105.09MiB |
| `postgres-db-only` | `docker-run` | `db` | cgroup peak | 1 | 114.82MiB | 114.82MiB | 114.82MiB | 114.82MiB |
| `postgres-db-only` | `docker-run` | `db` | runtime CPU snapshot | 1 | 0.06% | 0.06% | 0.06% | 0.06% |
| `simple-web` | `docker-compose` | `web` | runtime memory | 1 | 24.35MiB | 24.35MiB | 24.35MiB | 24.35MiB |
| `simple-web` | `docker-compose` | `web` | process VmRSS | 1 | 9.02MiB | 9.02MiB | 9.02MiB | 9.02MiB |
| `simple-web` | `docker-compose` | `web` | cgroup current | 1 | 26.35MiB | 26.35MiB | 26.35MiB | 26.35MiB |
| `simple-web` | `docker-compose` | `web` | cgroup peak | 1 | 28.80MiB | 28.80MiB | 28.80MiB | 28.80MiB |
| `simple-web` | `docker-compose` | `web` | runtime CPU snapshot | 1 | 0.00% | 0.00% | 0.00% | 0.00% |

## Apple Runtime Lifecycle

- `container system start`: not run, n/a.
- `container system stop`: not run, n/a.

## Evidence Files

- Raw JSONL: `docs/evidence/runtime-efficiency/20260611T180248Z-runtime-efficiency-raw.jsonl`
- Summary JSON: `docs/evidence/runtime-efficiency/20260611T180248Z-runtime-efficiency-summary.json`

## Harness Command

```text
scripts/benchmark_runtime_efficiency.py --runtimes docker --simple-iterations 1 --db-iterations 1 --backend-iterations 1
```

## Cleanup Scope

The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.
