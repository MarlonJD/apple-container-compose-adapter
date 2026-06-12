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
| `backend-shaped` | `docker-compose` | 1 |
| `postgres-db-only` | `apple-container` | 1 |
| `postgres-db-only` | `docker-run` | 1 |
| `simple-web` | `apple-container` | 1 |
| `simple-web` | `docker-compose` | 1 |

## Timing Percentiles

| Scenario | Runtime | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `api_start_command` | 1 | 0.871s | 0.871s | 0.871s | 0.871s |
| `backend-shaped` | `apple-container` | `db_health_wait` | 1 | 1.156s | 1.156s | 1.156s | 1.156s |
| `backend-shaped` | `apple-container` | `db_start_command` | 1 | 0.781s | 0.781s | 0.781s | 0.781s |
| `backend-shaped` | `apple-container` | `delete` | 1 | 0.149s | 0.149s | 0.149s | 0.149s |
| `backend-shaped` | `apple-container` | `migrate` | 1 | 0.868s | 0.868s | 0.868s | 0.868s |
| `backend-shaped` | `apple-container` | `network_create` | 1 | 0.073s | 0.073s | 0.073s | 0.073s |
| `backend-shaped` | `apple-container` | `network_delete` | 1 | 0.030s | 0.030s | 0.030s | 0.030s |
| `backend-shaped` | `apple-container` | `readiness_probe` | 1 | 1.033s | 1.033s | 1.033s | 1.033s |
| `backend-shaped` | `apple-container` | `seed` | 1 | 0.928s | 0.928s | 0.928s | 0.928s |
| `backend-shaped` | `apple-container` | `stop` | 1 | 5.272s | 5.272s | 5.272s | 5.272s |
| `backend-shaped` | `apple-container` | `volume_create` | 1 | 0.720s | 0.720s | 0.720s | 0.720s |
| `backend-shaped` | `apple-container` | `volume_delete` | 1 | 0.069s | 0.069s | 0.069s | 0.069s |
| `backend-shaped` | `docker-compose` | `readiness_probe` | 1 | 0.014s | 0.014s | 0.014s | 0.014s |
| `backend-shaped` | `docker-compose` | `start_to_wait` | 1 | 12.885s | 12.885s | 12.885s | 12.885s |
| `backend-shaped` | `docker-compose` | `stop_delete` | 1 | 10.687s | 10.687s | 10.687s | 10.687s |
| `postgres-db-only` | `apple-container` | `delete` | 1 | 0.125s | 0.125s | 0.125s | 0.125s |
| `postgres-db-only` | `apple-container` | `health_wait` | 1 | 1.135s | 1.135s | 1.135s | 1.135s |
| `postgres-db-only` | `apple-container` | `start_command` | 1 | 0.894s | 0.894s | 0.894s | 0.894s |
| `postgres-db-only` | `apple-container` | `stop` | 1 | 0.152s | 0.152s | 0.152s | 0.152s |
| `postgres-db-only` | `apple-container` | `volume_create` | 1 | 0.903s | 0.903s | 0.903s | 0.903s |
| `postgres-db-only` | `apple-container` | `volume_delete` | 1 | 0.094s | 0.094s | 0.094s | 0.094s |
| `postgres-db-only` | `docker-run` | `delete` | 1 | 0.142s | 0.142s | 0.142s | 0.142s |
| `postgres-db-only` | `docker-run` | `health_wait` | 1 | 2.189s | 2.189s | 2.189s | 2.189s |
| `postgres-db-only` | `docker-run` | `start_command` | 1 | 0.175s | 0.175s | 0.175s | 0.175s |
| `postgres-db-only` | `docker-run` | `stop` | 1 | 0.156s | 0.156s | 0.156s | 0.156s |
| `postgres-db-only` | `docker-run` | `volume_create` | 1 | 0.033s | 0.033s | 0.033s | 0.033s |
| `postgres-db-only` | `docker-run` | `volume_delete` | 1 | 0.157s | 0.157s | 0.157s | 0.157s |
| `simple-web` | `apple-container` | `delete` | 1 | 0.129s | 0.129s | 0.129s | 0.129s |
| `simple-web` | `apple-container` | `readiness_probe` | 1 | 0.015s | 0.015s | 0.015s | 0.015s |
| `simple-web` | `apple-container` | `start_command` | 1 | 1.229s | 1.229s | 1.229s | 1.229s |
| `simple-web` | `apple-container` | `stop` | 1 | 3.409s | 3.409s | 3.409s | 3.409s |
| `simple-web` | `docker-compose` | `readiness_probe` | 1 | 0.033s | 0.033s | 0.033s | 0.033s |
| `simple-web` | `docker-compose` | `start_to_wait` | 1 | 5.945s | 5.945s | 5.945s | 5.945s |
| `simple-web` | `docker-compose` | `stop_delete` | 1 | 0.378s | 0.378s | 0.378s | 0.378s |

## Memory And CPU Percentiles

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `db` | runtime memory | 1 | 188.05MiB | 188.05MiB | 188.05MiB | 188.05MiB |
| `backend-shaped` | `apple-container` | `db` | process VmRSS | 1 | 26.57MiB | 26.57MiB | 26.57MiB | 26.57MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup current | 1 | 188.58MiB | 188.58MiB | 188.58MiB | 188.58MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup peak | 1 | 200.57MiB | 200.57MiB | 200.57MiB | 200.57MiB |
| `backend-shaped` | `apple-container` | `db` | block read | 1 | 81.05MiB | 81.05MiB | 81.05MiB | 81.05MiB |
| `backend-shaped` | `apple-container` | `db` | block write | 1 | 50.61MiB | 50.61MiB | 50.61MiB | 50.61MiB |
| `backend-shaped` | `apple-container` | `db` | net read | 1 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `backend-shaped` | `apple-container` | `db` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `db` | disk /var/lib/postgresql/data | 1 | 45.79MiB | 45.79MiB | 45.79MiB | 45.79MiB |
| `backend-shaped` | `apple-container` | `db` | runtime CPU snapshot | 1 | 0.05% | 0.05% | 0.05% | 0.05% |
| `backend-shaped` | `apple-container` | `db` | load CPU snapshot | 1 | 86.90% | 86.90% | 86.90% | 86.90% |
| `backend-shaped` | `apple-container` | `api` | runtime memory | 1 | 31.61MiB | 31.61MiB | 31.61MiB | 31.61MiB |
| `backend-shaped` | `apple-container` | `api` | process VmRSS | 1 | 18.63MiB | 18.63MiB | 18.63MiB | 18.63MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup current | 1 | 33.11MiB | 33.11MiB | 33.11MiB | 33.11MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup peak | 1 | 33.23MiB | 33.23MiB | 33.23MiB | 33.23MiB |
| `backend-shaped` | `apple-container` | `api` | block read | 1 | 18.12MiB | 18.12MiB | 18.12MiB | 18.12MiB |
| `backend-shaped` | `apple-container` | `api` | block write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | net read | 1 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `backend-shaped` | `apple-container` | `api` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | runtime CPU snapshot | 1 | 0.03% | 0.03% | 0.03% | 0.03% |
| `backend-shaped` | `apple-container` | `api` | load CPU snapshot | 1 | 40.39% | 40.39% | 40.39% | 40.39% |
| `backend-shaped` | `apple-container` | `api` | load HTTP requests | 1 | 3154 | 3154 | 3154 | 3154 |
| `backend-shaped` | `docker-compose` | `db` | runtime memory | 1 | 18.14MiB | 18.14MiB | 18.14MiB | 18.14MiB |
| `backend-shaped` | `docker-compose` | `db` | process VmRSS | 1 | 26.66MiB | 26.66MiB | 26.66MiB | 26.66MiB |
| `backend-shaped` | `docker-compose` | `db` | cgroup current | 1 | 63.93MiB | 63.93MiB | 63.93MiB | 63.93MiB |
| `backend-shaped` | `docker-compose` | `db` | cgroup peak | 1 | 76.09MiB | 76.09MiB | 76.09MiB | 76.09MiB |
| `backend-shaped` | `docker-compose` | `db` | block read | 1 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `backend-shaped` | `docker-compose` | `db` | block write | 1 | 55.50MiB | 55.50MiB | 55.50MiB | 55.50MiB |
| `backend-shaped` | `docker-compose` | `db` | net read | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `docker-compose` | `db` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `docker-compose` | `db` | disk /var/lib/postgresql/data | 1 | 45.78MiB | 45.78MiB | 45.78MiB | 45.78MiB |
| `backend-shaped` | `docker-compose` | `db` | runtime CPU snapshot | 1 | 1.71% | 1.71% | 1.71% | 1.71% |
| `backend-shaped` | `docker-compose` | `db` | load CPU snapshot | 1 | 97.91% | 97.91% | 97.91% | 97.91% |
| `backend-shaped` | `docker-compose` | `api` | runtime memory | 1 | 28.32MiB | 28.32MiB | 28.32MiB | 28.32MiB |
| `backend-shaped` | `docker-compose` | `api` | process VmRSS | 1 | 18.94MiB | 18.94MiB | 18.94MiB | 18.94MiB |
| `backend-shaped` | `docker-compose` | `api` | cgroup current | 1 | 35.51MiB | 35.51MiB | 35.51MiB | 35.51MiB |
| `backend-shaped` | `docker-compose` | `api` | cgroup peak | 1 | 43.45MiB | 43.45MiB | 43.45MiB | 43.45MiB |
| `backend-shaped` | `docker-compose` | `api` | block read | 1 | 19.07MiB | 19.07MiB | 19.07MiB | 19.07MiB |
| `backend-shaped` | `docker-compose` | `api` | block write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `docker-compose` | `api` | net read | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `docker-compose` | `api` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `docker-compose` | `api` | runtime CPU snapshot | 1 | 0.67% | 0.67% | 0.67% | 0.67% |
| `backend-shaped` | `docker-compose` | `api` | load CPU snapshot | 1 | 79.55% | 79.55% | 79.55% | 79.55% |
| `backend-shaped` | `docker-compose` | `api` | load HTTP requests | 1 | 3207 | 3207 | 3207 | 3207 |
| `postgres-db-only` | `apple-container` | `db` | runtime memory | 1 | 187.18MiB | 187.18MiB | 187.18MiB | 187.18MiB |
| `postgres-db-only` | `apple-container` | `db` | process VmRSS | 1 | 26.63MiB | 26.63MiB | 26.63MiB | 26.63MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup current | 1 | 187.61MiB | 187.61MiB | 187.61MiB | 187.61MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup peak | 1 | 200.58MiB | 200.58MiB | 200.58MiB | 200.58MiB |
| `postgres-db-only` | `apple-container` | `db` | block read | 1 | 81.04MiB | 81.04MiB | 81.04MiB | 81.04MiB |
| `postgres-db-only` | `apple-container` | `db` | block write | 1 | 50.41MiB | 50.41MiB | 50.41MiB | 50.41MiB |
| `postgres-db-only` | `apple-container` | `db` | net read | 1 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `postgres-db-only` | `apple-container` | `db` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `postgres-db-only` | `apple-container` | `db` | disk /var/lib/postgresql/data | 1 | 45.70MiB | 45.70MiB | 45.70MiB | 45.70MiB |
| `postgres-db-only` | `apple-container` | `db` | runtime CPU snapshot | 1 | 0.05% | 0.05% | 0.05% | 0.05% |
| `postgres-db-only` | `apple-container` | `db` | load CPU snapshot | 1 | 73.22% | 73.22% | 73.22% | 73.22% |
| `postgres-db-only` | `docker-run` | `db` | runtime memory | 1 | 52.53MiB | 52.53MiB | 52.53MiB | 52.53MiB |
| `postgres-db-only` | `docker-run` | `db` | process VmRSS | 1 | 26.78MiB | 26.78MiB | 26.78MiB | 26.78MiB |
| `postgres-db-only` | `docker-run` | `db` | cgroup current | 1 | 101.74MiB | 101.74MiB | 101.74MiB | 101.74MiB |
| `postgres-db-only` | `docker-run` | `db` | cgroup peak | 1 | 114.57MiB | 114.57MiB | 114.57MiB | 114.57MiB |
| `postgres-db-only` | `docker-run` | `db` | block read | 1 | 38.62MiB | 38.62MiB | 38.62MiB | 38.62MiB |
| `postgres-db-only` | `docker-run` | `db` | block write | 1 | 55.03MiB | 55.03MiB | 55.03MiB | 55.03MiB |
| `postgres-db-only` | `docker-run` | `db` | net read | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `postgres-db-only` | `docker-run` | `db` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `postgres-db-only` | `docker-run` | `db` | disk /var/lib/postgresql/data | 1 | 45.70MiB | 45.70MiB | 45.70MiB | 45.70MiB |
| `postgres-db-only` | `docker-run` | `db` | runtime CPU snapshot | 1 | 0.05% | 0.05% | 0.05% | 0.05% |
| `postgres-db-only` | `docker-run` | `db` | load CPU snapshot | 1 | 57.03% | 57.03% | 57.03% | 57.03% |
| `simple-web` | `apple-container` | `web` | runtime memory | 1 | 14.58MiB | 14.58MiB | 14.58MiB | 14.58MiB |
| `simple-web` | `apple-container` | `web` | process VmRSS | 1 | 5.39MiB | 5.39MiB | 5.39MiB | 5.39MiB |
| `simple-web` | `apple-container` | `web` | cgroup current | 1 | 16.39MiB | 16.39MiB | 16.39MiB | 16.39MiB |
| `simple-web` | `apple-container` | `web` | cgroup peak | 1 | 16.61MiB | 16.61MiB | 16.61MiB | 16.61MiB |
| `simple-web` | `apple-container` | `web` | block read | 1 | 9.13MiB | 9.13MiB | 9.13MiB | 9.13MiB |
| `simple-web` | `apple-container` | `web` | block write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | net read | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | disk /usr/share/nginx/html | 1 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | disk /var/cache/nginx | 1 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `simple-web` | `apple-container` | `web` | runtime CPU snapshot | 1 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `apple-container` | `web` | load CPU snapshot | 1 | 9.61% | 9.61% | 9.61% | 9.61% |
| `simple-web` | `apple-container` | `web` | load HTTP requests | 1 | 4353 | 4353 | 4353 | 4353 |
| `simple-web` | `docker-compose` | `web` | runtime memory | 1 | 16.53MiB | 16.53MiB | 16.53MiB | 16.53MiB |
| `simple-web` | `docker-compose` | `web` | process VmRSS | 1 | 9.00MiB | 9.00MiB | 9.00MiB | 9.00MiB |
| `simple-web` | `docker-compose` | `web` | cgroup current | 1 | 26.07MiB | 26.07MiB | 26.07MiB | 26.07MiB |
| `simple-web` | `docker-compose` | `web` | cgroup peak | 1 | 28.36MiB | 28.36MiB | 28.36MiB | 28.36MiB |
| `simple-web` | `docker-compose` | `web` | block read | 1 | 9.14MiB | 9.14MiB | 9.14MiB | 9.14MiB |
| `simple-web` | `docker-compose` | `web` | block write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `docker-compose` | `web` | net read | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `docker-compose` | `web` | net write | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `docker-compose` | `web` | disk /usr/share/nginx/html | 1 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `docker-compose` | `web` | disk /var/cache/nginx | 1 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `docker-compose` | `web` | runtime CPU snapshot | 1 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `docker-compose` | `web` | load CPU snapshot | 1 | 25.99% | 25.99% | 25.99% | 25.99% |
| `simple-web` | `docker-compose` | `web` | load HTTP requests | 1 | 5257 | 5257 | 5257 | 5257 |

## Apple Runtime Lifecycle

- `container system start`: 0, 0.564s.
- `container system stop`: 0, 0.112s.

## Evidence Files

- Raw JSONL: `docs/evidence/runtime-efficiency/20260611T181055Z-runtime-efficiency-raw.jsonl`
- Summary JSON: `docs/evidence/runtime-efficiency/20260611T181055Z-runtime-efficiency-summary.json`

## Harness Command

```text
scripts/benchmark_runtime_efficiency.py --runtimes docker,apple --simple-iterations 1 --db-iterations 1 --backend-iterations 1
```

## Cleanup Scope

The harness cleaned only resources named with the `cca-bench-*` prefix. Cached images and installed Apple runtime setup were left in place.
