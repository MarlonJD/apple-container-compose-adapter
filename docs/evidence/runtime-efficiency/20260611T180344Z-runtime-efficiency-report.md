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
| `backend-shaped` | `apple-container` | 1 |
| `postgres-db-only` | `apple-container` | 1 |
| `simple-web` | `apple-container` | 1 |

## Timing Percentiles

| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `api_start_command` | 1 | 0.844s | 0.844s | 0.844s | 0.844s |
| `backend-shaped` | `apple-container` | `db_health_wait` | 1 | 1.147s | 1.147s | 1.147s | 1.147s |
| `backend-shaped` | `apple-container` | `db_start_command` | 1 | 0.826s | 0.826s | 0.826s | 0.826s |
| `backend-shaped` | `apple-container` | `delete` | 1 | 0.146s | 0.146s | 0.146s | 0.146s |
| `backend-shaped` | `apple-container` | `migrate` | 1 | 0.882s | 0.882s | 0.882s | 0.882s |
| `backend-shaped` | `apple-container` | `network_create` | 1 | 0.083s | 0.083s | 0.083s | 0.083s |
| `backend-shaped` | `apple-container` | `network_delete` | 1 | 0.171s | 0.171s | 0.171s | 0.171s |
| `backend-shaped` | `apple-container` | `readiness_probe` | 1 | 1.016s | 1.016s | 1.016s | 1.016s |
| `backend-shaped` | `apple-container` | `seed` | 1 | 1.030s | 1.030s | 1.030s | 1.030s |
| `backend-shaped` | `apple-container` | `stop` | 1 | 8.408s | 8.408s | 8.408s | 8.408s |
| `backend-shaped` | `apple-container` | `volume_create` | 1 | 0.928s | 0.928s | 0.928s | 0.928s |
| `backend-shaped` | `apple-container` | `volume_delete` | 1 | 0.143s | 0.143s | 0.143s | 0.143s |
| `postgres-db-only` | `apple-container` | `delete` | 1 | 0.111s | 0.111s | 0.111s | 0.111s |
| `postgres-db-only` | `apple-container` | `health_wait` | 1 | 1.157s | 1.157s | 1.157s | 1.157s |
| `postgres-db-only` | `apple-container` | `start_command` | 1 | 0.815s | 0.815s | 0.815s | 0.815s |
| `postgres-db-only` | `apple-container` | `stop` | 1 | 0.153s | 0.153s | 0.153s | 0.153s |
| `postgres-db-only` | `apple-container` | `volume_create` | 1 | 0.588s | 0.588s | 0.588s | 0.588s |
| `postgres-db-only` | `apple-container` | `volume_delete` | 1 | 0.074s | 0.074s | 0.074s | 0.074s |
| `simple-web` | `apple-container` | `delete` | 1 | 0.098s | 0.098s | 0.098s | 0.098s |
| `simple-web` | `apple-container` | `readiness_probe` | 1 | 0.021s | 0.021s | 0.021s | 0.021s |
| `simple-web` | `apple-container` | `start_command` | 1 | 1.018s | 1.018s | 1.018s | 1.018s |
| `simple-web` | `apple-container` | `stop` | 1 | 0.207s | 0.207s | 0.207s | 0.207s |

## Memory And CPU Percentiles

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `db` | runtime memory | 1 | 188.42MiB | 188.42MiB | 188.42MiB | 188.42MiB |
| `backend-shaped` | `apple-container` | `db` | process VmRSS | 1 | 26.70MiB | 26.70MiB | 26.70MiB | 26.70MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup current | 1 | 188.52MiB | 188.52MiB | 188.52MiB | 188.52MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup peak | 1 | 200.35MiB | 200.35MiB | 200.35MiB | 200.35MiB |
| `backend-shaped` | `apple-container` | `db` | runtime CPU snapshot | 1 | 0.08% | 0.08% | 0.08% | 0.08% |
| `backend-shaped` | `apple-container` | `api` | runtime memory | 1 | 31.53MiB | 31.53MiB | 31.53MiB | 31.53MiB |
| `backend-shaped` | `apple-container` | `api` | process VmRSS | 1 | 18.63MiB | 18.63MiB | 18.63MiB | 18.63MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup current | 1 | 34.36MiB | 34.36MiB | 34.36MiB | 34.36MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup peak | 1 | 34.61MiB | 34.61MiB | 34.61MiB | 34.61MiB |
| `backend-shaped` | `apple-container` | `api` | runtime CPU snapshot | 1 | 0.02% | 0.02% | 0.02% | 0.02% |
| `postgres-db-only` | `apple-container` | `db` | runtime memory | 1 | 186.89MiB | 186.89MiB | 186.89MiB | 186.89MiB |
| `postgres-db-only` | `apple-container` | `db` | process VmRSS | 1 | 26.55MiB | 26.55MiB | 26.55MiB | 26.55MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup current | 1 | 187.52MiB | 187.52MiB | 187.52MiB | 187.52MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup peak | 1 | 200.50MiB | 200.50MiB | 200.50MiB | 200.50MiB |
| `postgres-db-only` | `apple-container` | `db` | runtime CPU snapshot | 1 | 0.05% | 0.05% | 0.05% | 0.05% |
| `simple-web` | `apple-container` | `web` | runtime memory | 1 | 14.59MiB | 14.59MiB | 14.59MiB | 14.59MiB |
| `simple-web` | `apple-container` | `web` | process VmRSS | 1 | 5.47MiB | 5.47MiB | 5.47MiB | 5.47MiB |
| `simple-web` | `apple-container` | `web` | cgroup current | 1 | 15.12MiB | 15.12MiB | 15.12MiB | 15.12MiB |
| `simple-web` | `apple-container` | `web` | cgroup peak | 1 | 15.86MiB | 15.86MiB | 15.86MiB | 15.86MiB |
| `simple-web` | `apple-container` | `web` | runtime CPU snapshot | 1 | 0.00% | 0.00% | 0.00% | 0.00% |

## Apple Runtime Lifecycle

- `container system start`: 0, 0.679s.
- `container system stop`: 0, 0.072s.

## Evidence Files

- Raw JSONL: `docs/evidence/runtime-efficiency/20260611T180344Z-runtime-efficiency-raw.jsonl`
- Summary JSON: `docs/evidence/runtime-efficiency/20260611T180344Z-runtime-efficiency-summary.json`

## Harness Command

```text
scripts/benchmark_runtime_efficiency.py --runtimes apple --simple-iterations 1 --db-iterations 1 --backend-iterations 1
```

## Cleanup Scope

The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.
