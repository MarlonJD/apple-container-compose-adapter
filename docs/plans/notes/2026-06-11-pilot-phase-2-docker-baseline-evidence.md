# Pilot Phase 2 Docker Baseline Evidence

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../completed/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** Public Docker Compose fixture definitions and Docker/OrbStack baseline measurements.

## Phase 2 Verdict

The public fixtures under [docs/evidence/fixtures](../../evidence/fixtures/README.md) were measured on Docker/OrbStack after the owner explicitly approved runtime mutation in the follow-up instruction.

Docker/OrbStack is a working baseline for both public fixtures. The backend-shaped fixture required an environment override because the shell had `DOCKER_DEFAULT_PLATFORM=linux/amd64` while cached local images were arm64 on this Apple silicon host. Backend measurements below were run with `DOCKER_DEFAULT_PLATFORM=linux/arm64`.

## Fixture Summary

| Workload | Fixture | Status | Runtime mutation required to measure |
| --- | --- | --- | --- |
| `simple-web` | [simple-web/compose.yaml](../../evidence/fixtures/simple-web/compose.yaml) | Measured and cleaned up. | Image pull if missing, container create/start, default network create, container stop/remove, network cleanup. |
| `backend-shaped` | [backend-shaped/compose.yaml](../../evidence/fixtures/backend-shaped/compose.yaml) | Measured with `DOCKER_DEFAULT_PLATFORM=linux/arm64` and cleaned up. | Image pulls if missing, database container, migrate job, seed job, API container, default network, named volume, cleanup. |

## Measured Results

### Simple-web

| Metric | Result |
| --- | --- |
| Cold `up -d --wait` | `19.41s`, including `nginx:1.27-alpine` pull. |
| HTTP readiness after up | `curl http://127.0.0.1:18080/` returned 200 in `0.03s`. |
| Status | One running healthy container: `cca-pilot-simple-web-1`. |
| Idle stats snapshot | CPU `3.34%`, memory `18.5MiB / 7.818GiB`, shortly after startup. |
| Repeated `up -d --wait` while running | `0.64s`, same container remained healthy. |
| `down` | `0.41s`, removed container and project network. |
| Warm `up -d --wait` after image cache | `5.82s`. |
| Final `down --volumes` | `0.36s`; no named volume existed. |

### Backend-shaped

| Metric | Result |
| --- | --- |
| Initial run issue | First backend run failed because `DOCKER_DEFAULT_PLATFORM=linux/amd64` conflicted with arm64 cached `postgres:16-alpine`. |
| Corrective runtime condition | Re-ran backend with `DOCKER_DEFAULT_PLATFORM=linux/arm64`; pulled/used arm64 public images. |
| Cold `up -d --wait` | `12.93s`, including database health, migrate job, seed job, and API health. |
| HTTP readiness after up | `curl http://127.0.0.1:18081/ready` returned `ready` in `0.01s`. |
| Status | API and DB running healthy; migrate and seed completed successfully. |
| Idle stats snapshot | DB CPU `2.84%`, memory `22.17MiB`; API CPU `8.57%`, memory `27.5MiB`, shortly after startup. |
| Service-name connectivity | One-off `docker compose run --rm api ... socket.create_connection(('db', 5432))` returned `db reachable` in `2.42s`. |
| Repeated `up -d --wait` while running | `2.46s`; Compose reran completed migrate/seed job containers. |
| Row count before `down` | `3`, because the seed job inserted once during cold up, one-off run dependency execution, and repeated up. |
| `down` without volumes | `10.62s`, removed containers and project network, preserved `cca-pilot-backend_db-data`. |
| Volume persistence after `down` | `docker volume ls` still showed `cca-pilot-backend_db-data`. |
| Warm `up -d --wait` with preserved volume | `12.84s`; readiness returned `ready` in `0.02s`. |
| Row count after warm up | `4`, proving the named volume persisted and the seed job inserted again. |
| Final `down --volumes` | `10.75s`; removed containers, network, and `cca-pilot-backend_db-data`. |
| Cleanup check | No `cca-pilot-*` Docker containers, networks, or volumes remained. |

## Evidence Rows

| Run ID | Workload | Runtime | Operation | Status | Reason |
| --- | --- | --- | --- | --- | --- |
| `2026-06-11-simple-web-docker-baseline` | `simple-web` | `docker-orbstack` | cold/warm readiness, status, logs, repeated up, cleanup | `measured` | Public fixture ran and cleaned up successfully. |
| `2026-06-11-backend-shaped-docker-baseline` | `backend-shaped` | `docker-orbstack` | cold/warm readiness, jobs, API-to-db, named volume, status, logs, cleanup | `measured` | Public fixture ran with explicit arm64 platform override and cleaned up successfully. |

## Named Volume Behavior To Verify Later

For `backend-shaped`, the expected Docker Compose reference behavior is:

- `down` removes project containers and the project network but preserves `db-data`.
- repeated `up` reuses `db-data`.
- `down --volumes` removes `db-data`.

This behavior was measured and matched Docker Compose expectations.

## Phase 2 Follow-up

For future repeatability, either unset `DOCKER_DEFAULT_PLATFORM` or set it explicitly to `linux/arm64` for Apple silicon baseline runs. The measured host had `DOCKER_DEFAULT_PLATFORM=linux/amd64`, which caused the first backend attempt to fail before the platform override.
