# Combined Runtime Efficiency Benchmark Report

**Date:** 2026-06-11
**Scope:** Docker/OrbStack full reference run plus fixed Apple `container` run after adding readiness and port-release waits.

## Data Sets

- Docker raw source: `docs/evidence/runtime-efficiency/20260611T181254Z-runtime-efficiency-raw.jsonl` (`simple-web` 50, `postgres-db-only` 50, `backend-shaped` 20).
- Apple raw source: `docs/evidence/runtime-efficiency/20260611T184900Z-runtime-efficiency-raw.jsonl` (`simple-web` 20, `postgres-db-only` 20, `backend-shaped` 10).
- Combined raw: `docs/evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-raw.jsonl`.
- Combined summary: `docs/evidence/runtime-efficiency/20260611T185918Z-combined-runtime-efficiency-summary.json`.

Earlier Apple attempts hit XPC/bootstrap, stale state, and port-release failures. Those failed attempts are excluded from percentile math and recorded as stability incidents in the narrative below.

## Iteration Counts

| Scenario | Runtime | Iterations |
| --- | --- | ---: |
| `backend-shaped` | `apple-container` | 10 |
| `backend-shaped` | `docker-compose` | 20 |
| `postgres-db-only` | `apple-container` | 20 |
| `postgres-db-only` | `docker-run` | 50 |
| `simple-web` | `apple-container` | 20 |
| `simple-web` | `docker-compose` | 50 |

## Timing Summary

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
| `backend-shaped` | `docker-compose` | `readiness_probe` | 20 | 0.018s | 0.056s | 0.091s | 0.099s |
| `backend-shaped` | `docker-compose` | `start_to_wait` | 20 | 12.859s | 13.144s | 13.354s | 13.406s |
| `backend-shaped` | `docker-compose` | `stop_delete` | 20 | 10.731s | 10.845s | 10.867s | 10.872s |
| `postgres-db-only` | `apple-container` | `delete` | 20 | 0.118s | 0.136s | 0.157s | 0.163s |
| `postgres-db-only` | `apple-container` | `health_wait` | 20 | 1.166s | 1.210s | 1.212s | 1.212s |
| `postgres-db-only` | `apple-container` | `start_command` | 20 | 0.845s | 0.935s | 0.980s | 0.991s |
| `postgres-db-only` | `apple-container` | `stop` | 20 | 0.171s | 0.597s | 2.728s | 3.260s |
| `postgres-db-only` | `apple-container` | `volume_create` | 20 | 0.505s | 0.972s | 1.321s | 1.408s |
| `postgres-db-only` | `apple-container` | `volume_delete` | 20 | 0.075s | 0.094s | 0.097s | 0.098s |
| `postgres-db-only` | `docker-run` | `delete` | 50 | 0.078s | 0.198s | 0.281s | 0.346s |
| `postgres-db-only` | `docker-run` | `health_wait` | 50 | 2.194s | 2.295s | 2.831s | 3.306s |
| `postgres-db-only` | `docker-run` | `start_command` | 50 | 0.165s | 0.236s | 0.286s | 0.323s |
| `postgres-db-only` | `docker-run` | `stop` | 50 | 0.174s | 0.292s | 0.520s | 0.676s |
| `postgres-db-only` | `docker-run` | `volume_create` | 50 | 0.031s | 0.043s | 0.049s | 0.050s |
| `postgres-db-only` | `docker-run` | `volume_delete` | 50 | 0.048s | 0.092s | 0.103s | 0.111s |
| `simple-web` | `apple-container` | `delete` | 20 | 0.125s | 0.141s | 0.144s | 0.145s |
| `simple-web` | `apple-container` | `port_closed` | 20 | 0.000s | 0.000s | 0.000s | 0.000s |
| `simple-web` | `apple-container` | `readiness_probe` | 20 | 0.015s | 0.373s | 5.695s | 7.026s |
| `simple-web` | `apple-container` | `start_command` | 20 | 0.868s | 1.037s | 1.312s | 1.381s |
| `simple-web` | `apple-container` | `stop` | 20 | 0.232s | 5.254s | 5.455s | 5.506s |
| `simple-web` | `docker-compose` | `readiness_probe` | 50 | 0.032s | 0.038s | 0.055s | 0.071s |
| `simple-web` | `docker-compose` | `start_to_wait` | 50 | 5.795s | 5.911s | 6.057s | 6.070s |
| `simple-web` | `docker-compose` | `stop_delete` | 50 | 0.368s | 0.604s | 0.655s | 0.657s |

## Resource Summary

| Scenario | Runtime | Role | Metric | n | p50 | p95 | p99 | max |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `backend-shaped` | `apple-container` | `db` | runtime memory | 10 | 188.15MiB | 190.62MiB | 192.10MiB | 192.47MiB |
| `backend-shaped` | `apple-container` | `db` | process VmRSS | 10 | 26.57MiB | 26.69MiB | 26.71MiB | 26.71MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup current | 10 | 188.45MiB | 190.85MiB | 192.27MiB | 192.62MiB |
| `backend-shaped` | `apple-container` | `db` | cgroup peak | 10 | 200.14MiB | 202.87MiB | 204.28MiB | 204.63MiB |
| `backend-shaped` | `apple-container` | `db` | idle CPU snapshot | 10 | 0.05% | 0.07% | 0.07% | 0.07% |
| `backend-shaped` | `apple-container` | `db` | load CPU snapshot | 10 | 57.34% | 71.09% | 71.43% | 71.51% |
| `backend-shaped` | `apple-container` | `db` | block read | 10 | 81.05MiB | 83.37MiB | 84.89MiB | 85.27MiB |
| `backend-shaped` | `apple-container` | `db` | block write | 10 | 50.61MiB | 50.62MiB | 50.62MiB | 50.62MiB |
| `backend-shaped` | `apple-container` | `db` | disk /var/lib/postgresql/data | 10 | 45.79MiB | 45.79MiB | 45.79MiB | 45.79MiB |
| `backend-shaped` | `apple-container` | `api` | runtime memory | 10 | 31.59MiB | 33.79MiB | 35.21MiB | 35.56MiB |
| `backend-shaped` | `apple-container` | `api` | process VmRSS | 10 | 18.72MiB | 18.81MiB | 18.82MiB | 18.82MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup current | 10 | 33.10MiB | 35.34MiB | 36.66MiB | 36.99MiB |
| `backend-shaped` | `apple-container` | `api` | cgroup peak | 10 | 33.36MiB | 35.59MiB | 36.91MiB | 37.24MiB |
| `backend-shaped` | `apple-container` | `api` | idle CPU snapshot | 10 | 0.02% | 0.02% | 0.02% | 0.02% |
| `backend-shaped` | `apple-container` | `api` | load CPU snapshot | 10 | 38.70% | 49.25% | 50.47% | 50.77% |
| `backend-shaped` | `apple-container` | `api` | block read | 10 | 18.12MiB | 20.40MiB | 21.89MiB | 22.26MiB |
| `backend-shaped` | `apple-container` | `api` | block write | 10 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `backend-shaped` | `apple-container` | `api` | load HTTP requests | 10 | 2993 | 3460 | 3512 | 3525 |
| `backend-shaped` | `docker-compose` | `db` | runtime memory | 20 | 20.09MiB | 44.95MiB | 45.25MiB | 45.32MiB |
| `backend-shaped` | `docker-compose` | `db` | process VmRSS | 20 | 26.65MiB | 26.79MiB | 26.80MiB | 26.80MiB |
| `backend-shaped` | `docker-compose` | `db` | cgroup current | 20 | 67.33MiB | 96.63MiB | 96.73MiB | 96.76MiB |
| `backend-shaped` | `docker-compose` | `db` | cgroup peak | 20 | 79.23MiB | 105.71MiB | 106.21MiB | 106.34MiB |
| `backend-shaped` | `docker-compose` | `db` | idle CPU snapshot | 20 | 2.47% | 2.77% | 3.41% | 3.57% |
| `backend-shaped` | `docker-compose` | `db` | load CPU snapshot | 20 | 107.97% | 131.96% | 131.98% | 131.98% |
| `backend-shaped` | `docker-compose` | `db` | block read | 20 | 3.09MiB | 29.49MiB | 29.85MiB | 29.95MiB |
| `backend-shaped` | `docker-compose` | `db` | block write | 20 | 55.50MiB | 55.50MiB | 55.50MiB | 55.50MiB |
| `backend-shaped` | `docker-compose` | `db` | disk /var/lib/postgresql/data | 20 | 45.78MiB | 45.78MiB | 45.78MiB | 45.78MiB |
| `backend-shaped` | `docker-compose` | `api` | runtime memory | 20 | 11.89MiB | 17.95MiB | 26.16MiB | 28.21MiB |
| `backend-shaped` | `docker-compose` | `api` | process VmRSS | 20 | 18.86MiB | 18.95MiB | 18.96MiB | 18.96MiB |
| `backend-shaped` | `docker-compose` | `api` | cgroup current | 20 | 19.07MiB | 25.09MiB | 34.17MiB | 36.44MiB |
| `backend-shaped` | `docker-compose` | `api` | cgroup peak | 20 | 26.37MiB | 32.72MiB | 41.13MiB | 43.23MiB |
| `backend-shaped` | `docker-compose` | `api` | idle CPU snapshot | 20 | 0.03% | 0.08% | 0.30% | 0.36% |
| `backend-shaped` | `docker-compose` | `api` | load CPU snapshot | 20 | 70.57% | 90.41% | 92.00% | 92.40% |
| `backend-shaped` | `docker-compose` | `api` | block read | 20 | 1.77MiB | 7.99MiB | 16.78MiB | 18.98MiB |
| `backend-shaped` | `docker-compose` | `api` | block write | 20 | 0.00MiB | 0.09MiB | 1.50MiB | 1.85MiB |
| `backend-shaped` | `docker-compose` | `api` | load HTTP requests | 20 | 4627 | 6023 | 6236 | 6289 |
| `postgres-db-only` | `apple-container` | `db` | runtime memory | 20 | 187.01MiB | 187.68MiB | 190.50MiB | 191.20MiB |
| `postgres-db-only` | `apple-container` | `db` | process VmRSS | 20 | 26.57MiB | 26.73MiB | 26.76MiB | 26.77MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup current | 20 | 187.45MiB | 187.92MiB | 190.89MiB | 191.63MiB |
| `postgres-db-only` | `apple-container` | `db` | cgroup peak | 20 | 200.44MiB | 200.93MiB | 203.70MiB | 204.40MiB |
| `postgres-db-only` | `apple-container` | `db` | idle CPU snapshot | 20 | 0.05% | 0.06% | 0.07% | 0.07% |
| `postgres-db-only` | `apple-container` | `db` | load CPU snapshot | 20 | 67.59% | 72.20% | 73.38% | 73.67% |
| `postgres-db-only` | `apple-container` | `db` | block read | 20 | 81.05MiB | 81.26MiB | 84.46MiB | 85.26MiB |
| `postgres-db-only` | `apple-container` | `db` | block write | 20 | 50.41MiB | 50.41MiB | 50.41MiB | 50.41MiB |
| `postgres-db-only` | `apple-container` | `db` | disk /var/lib/postgresql/data | 20 | 45.70MiB | 45.70MiB | 45.70MiB | 45.70MiB |
| `postgres-db-only` | `docker-run` | `db` | runtime memory | 50 | 17.21MiB | 22.58MiB | 37.95MiB | 52.45MiB |
| `postgres-db-only` | `docker-run` | `db` | process VmRSS | 50 | 26.68MiB | 26.84MiB | 26.84MiB | 26.84MiB |
| `postgres-db-only` | `docker-run` | `db` | cgroup current | 50 | 65.14MiB | 71.39MiB | 88.00MiB | 101.17MiB |
| `postgres-db-only` | `docker-run` | `db` | cgroup peak | 50 | 76.36MiB | 84.34MiB | 100.26MiB | 114.87MiB |
| `postgres-db-only` | `docker-run` | `db` | idle CPU snapshot | 50 | 0.06% | 8.43% | 10.36% | 10.55% |
| `postgres-db-only` | `docker-run` | `db` | load CPU snapshot | 50 | 79.97% | 129.61% | 131.37% | 132.32% |
| `postgres-db-only` | `docker-run` | `db` | block read | 50 | 0.00MiB | 8.00MiB | 23.99MiB | 38.62MiB |
| `postgres-db-only` | `docker-run` | `db` | block write | 50 | 55.03MiB | 55.03MiB | 55.03MiB | 55.03MiB |
| `postgres-db-only` | `docker-run` | `db` | disk /var/lib/postgresql/data | 50 | 45.70MiB | 45.70MiB | 45.70MiB | 45.70MiB |
| `simple-web` | `apple-container` | `web` | runtime memory | 20 | 14.59MiB | 14.99MiB | 17.46MiB | 18.08MiB |
| `simple-web` | `apple-container` | `web` | process VmRSS | 20 | 5.44MiB | 5.52MiB | 5.53MiB | 5.53MiB |
| `simple-web` | `apple-container` | `web` | cgroup current | 20 | 15.13MiB | 16.74MiB | 18.48MiB | 18.91MiB |
| `simple-web` | `apple-container` | `web` | cgroup peak | 20 | 15.87MiB | 16.79MiB | 19.24MiB | 19.86MiB |
| `simple-web` | `apple-container` | `web` | idle CPU snapshot | 20 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `apple-container` | `web` | load CPU snapshot | 20 | 1.10% | 7.11% | 9.10% | 9.60% |
| `simple-web` | `apple-container` | `web` | block read | 20 | 9.13MiB | 9.32MiB | 12.26MiB | 13.00MiB |
| `simple-web` | `apple-container` | `web` | block write | 20 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `apple-container` | `web` | disk /usr/share/nginx/html | 20 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `apple-container` | `web` | disk /var/cache/nginx | 20 | 0.02MiB | 0.02MiB | 0.02MiB | 0.02MiB |
| `simple-web` | `apple-container` | `web` | load HTTP requests | 20 | 1476 | 3320 | 4206 | 4427 |
| `simple-web` | `docker-compose` | `web` | runtime memory | 50 | 15.98MiB | 19.22MiB | 22.13MiB | 24.73MiB |
| `simple-web` | `docker-compose` | `web` | process VmRSS | 50 | 9.01MiB | 9.02MiB | 9.02MiB | 9.02MiB |
| `simple-web` | `docker-compose` | `web` | cgroup current | 50 | 17.18MiB | 20.72MiB | 23.53MiB | 26.22MiB |
| `simple-web` | `docker-compose` | `web` | cgroup peak | 50 | 19.97MiB | 23.46MiB | 26.88MiB | 29.84MiB |
| `simple-web` | `docker-compose` | `web` | idle CPU snapshot | 50 | 0.00% | 0.00% | 0.00% | 0.00% |
| `simple-web` | `docker-compose` | `web` | load CPU snapshot | 50 | 28.08% | 36.36% | 37.71% | 37.79% |
| `simple-web` | `docker-compose` | `web` | block read | 50 | 0.00MiB | 3.45MiB | 6.29MiB | 8.91MiB |
| `simple-web` | `docker-compose` | `web` | block write | 50 | 0.00MiB | 0.00MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `docker-compose` | `web` | disk /usr/share/nginx/html | 50 | 0.01MiB | 0.01MiB | 0.01MiB | 0.01MiB |
| `simple-web` | `docker-compose` | `web` | disk /var/cache/nginx | 50 | 0.00MiB | 0.00MiB | 0.00MiB | 0.00MiB |
| `simple-web` | `docker-compose` | `web` | load HTTP requests | 50 | 4882 | 5975 | 6257 | 6389 |

## Preliminary Finding

- `simple-web`: Apple `container` remains promising on memory and start command time, but cleanup/port-release waits are required for repeated runs.
- `postgres-db-only`: Postgres process RSS is close between Docker and Apple, but Apple cgroup/runtime memory is materially higher.
- `backend-shaped`: Apple is faster on the workaround path for several command-level timings, but it is not Compose parity because it uses PGDATA and DB-IP workarounds.
- CPU: idle snapshots are low for both runtimes. Load CPU snapshots are synthetic and should be read as harness-local stress samples, not production throughput.
- Disk: Postgres data directory footprint is similar. Apple reports higher DB block reads, while writes are in the same broad range.
- Reliability: before port-release waits and unique names, Apple repeated runs hit XPC/bootstrap, stale state, and address-in-use failures. That is a blocker for replacement claims until the adapter handles lifecycle waits and cleanup robustly.

## Decision

Do not claim Docker Compose/OrbStack replacement yet. Continue adapter implementation only with explicit lifecycle, readiness, port-release, service discovery, and volume diagnostics. Apple `container` is promising for simple web workloads, but backend replacement remains unproven.
