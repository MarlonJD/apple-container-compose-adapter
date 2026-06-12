# Pilot Phase 3 Apple Container Evidence

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../completed/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** Apple `container` command mapping, runtime measurements, capability gaps, and cleanup evidence for the public pilot fixtures.

## Phase 3 Verdict

Apple `container` measurements were run after the owner explicitly approved runtime mutation in the follow-up instruction.

Simple-web works through the Apple `container` CLI after one-time runtime setup. Backend-shaped work can be partially executed, but the exact Compose fixture does not map cleanly yet: named volumes need a Postgres `PGDATA` subdirectory workaround, and service-name DNS such as `db` was not available on the user-created Apple `container` network.

The Apple runtime was cleaned up after the pilot: no pilot containers, user-created networks, or named volumes remained. Apple image cache and the newly installed default kernel remained as runtime setup/cache.

## Local CLI Evidence Refreshed

| Probe | Status | Result |
| --- | --- | --- |
| `container --version` | `measured` | `container CLI version 1.0.0 (build: release, commit: ee848e3)`. |
| `container --help` | `measured` | Top-level commands include container lifecycle, image build, machine, volume, network, and system groups; plugins were unavailable until `container system start`. |
| `container help run` | `measured` | Shows `--env`, `--env-file`, `--user`, `--workdir`, `--cpus`, `--memory`, `--label`, `--mount`, `--name`, `--network`, `--publish`, `--publish-socket`, `--volume`, and related flags. |
| `container help network` | `measured` | Shows create, delete, list, inspect, and prune. |
| `container help volume` | `measured` | Shows create, delete, list, inspect, and prune. |
| Initial `container system status` | `cli-available-service-stopped` | `apiserver is not running and not registered with launchd`. |
| `container system start` | `measured` with setup caveat | First start began launching the apiserver, then prompted for the recommended kernel and exited because input was unavailable. A later status showed the apiserver was running. |
| `container system kernel set --recommended` | `measured` | Installed the recommended Kata kernel for arm64. Duration was not captured because the command ran as a long-running approved setup step. |
| Final `container system stop` | `measured` | Stopped the Apple `container` services. Final status returned `apiserver is not running and not registered with launchd`. |

Some read-only help/status commands had to be run outside the Codex app sandbox because XPC-backed CLI help returned `Operation not permitted` inside the sandbox.

## Simple-web Apple Measurements

| Metric | Result |
| --- | --- |
| First attempted run before kernel setup | Failed after `16.47s` with `default kernel not configured for architecture arm64`; the nginx image had already been fetched/unpacked. |
| First successful run after kernel setup | `37.31s`, including init image fetch/unpack; container started as `cca-pilot-simple-web`. |
| HTTP readiness | `curl http://127.0.0.1:18080/` returned 200 in `0.01s`. |
| Runtime list | Container running as linux/arm64, IP `192.168.64.2/24`, `4` CPUs, `1024 MB` memory. |
| Stats snapshot | CPU `0.00%`, memory `14.32MiB / 1.00GiB`, net `24.58KiB / 1.83KiB`, block I/O about `9.13MiB / 8KiB`. |
| Logs | Nginx started successfully on Linux `6.18.15`; request from host gateway returned 200. |
| Same-name repeated `container run` | Failed in `0.02s` with `container with id cca-pilot-simple-web already exists`; Apple CLI does not provide Compose-like idempotent `up` by itself. |
| Stop before warm run | `0.31s`. |
| Delete before warm run | `0.10s`. |
| Cached warm run | `0.93s`; image, kernel, and init image were cached. |
| Warm readiness | `curl` returned 200 in `0.01s`. |
| Final stop/delete | Stop `3.25s`; delete `0.09s`. |

## Backend-shaped Apple Measurements

These measurements are not exact Compose parity. They show what worked, what needed a workaround, and where the adapter must add behavior.

| Metric | Result |
| --- | --- |
| Network create | `container network create cca-pilot-backend-net` completed in `0.10s`. |
| Volume create | `container volume create cca-pilot-backend-db-data` completed in `0.65s`. |
| First DB run | `51.66s`, including `postgres:16-alpine` image fetch/unpack; container stopped immediately. |
| First DB blocker | Postgres `initdb` failed because Apple named volume mount contained `lost+found`; direct mount at `/var/lib/postgresql/data` is not compatible with the fixture as written. |
| DB workaround | Recreated the named volume and set `PGDATA=/var/lib/postgresql/data/pgdata`. Cached DB run then completed in `0.88s`. |
| DB health | `container exec ... pg_isready -U app -d app` returned accepting connections in `0.06s`. |
| Service-name DNS test | One-off container using `pg_isready -h db` failed in `0.95s` with no response. `getent hosts db` returned no host entry. |
| Container hostname test | `pg_isready -h cca-pilot-backend-db` also failed in `0.86s`. |
| IP connectivity test | `pg_isready -h 192.168.65.3` succeeded in `1.04s`; host `127.0.0.1:15432` TCP check succeeded in `0.02s`. |
| Migrate job workaround | One-off container using DB IP created the table in `0.85s`. |
| Seed job workaround | One-off container using DB IP inserted one row in `0.84s`. |
| API run workaround | API-like Python service connected to DB IP and started in `15.97s`, including `python:3.12-alpine` image fetch/unpack. |
| API readiness | `curl http://127.0.0.1:18081/ready` returned `ready` in `0.04s`. |
| Stats snapshot | API CPU `0.02%`, memory `31.03MiB / 1.00GiB`; DB CPU `0.00%`, memory `191.01MiB / 1.00GiB`. |
| DB row count | `1` after seed. |
| Down without volumes | Stop API/DB `5.25s`, delete API/DB `0.14s`, network delete `0.04s`; named volume remained. |
| Volume persistence | Recreated network and DB with the same named volume; DB warm run `0.74s`, health `0.08s`, row count remained `1`. |
| Final cleanup | Stop DB `0.13s`, delete DB `0.08s`, network delete `0.03s`, volume delete `0.09s`. |
| Final runtime state | `container list --all` empty, only default network listed, `container volume list` empty. `container system df` showed 4 cached images, 0 containers, 0 local volumes. |

## Simple-web Apple Command Plan

Planned project prefix: `cca-pilot-simple`.

| Operation | Planned argv | Mutation | Status |
| --- | --- | --- | --- |
| Start runtime service | `["container", "system", "start"]` | Starts/registers Apple container services. | `measured` |
| Run web container | `["container", "run", "--detach", "--name", "cca-pilot-simple-web", "--label", "com.container-compose-adapter.pilot.workload=simple-web", "--publish", "127.0.0.1:18080:80", "docker.io/library/nginx:1.27-alpine"]` | May pull image, create VM/container, start process, publish port. | `measured` |
| Readiness | `["curl", "-fsS", "http://127.0.0.1:18080/"]` | No runtime mutation. | `measured` |
| Status | `["container", "list", "--all"]`, `["container", "logs", "cca-pilot-simple-web"]`, `["container", "stats", "--no-stream", "cca-pilot-simple-web"]` | Read-only after runtime exists. | `measured` |
| Cleanup | `["container", "stop", "cca-pilot-simple-web"]`, `["container", "delete", "cca-pilot-simple-web"]` | Stops/deletes runtime resources. | `measured` |

## Backend-shaped Apple Command Plan

Planned project prefix: `cca-pilot-backend`.

| Operation | Planned argv | Mutation | Status |
| --- | --- | --- | --- |
| Start runtime service | `["container", "system", "start"]` | Starts/registers Apple container services. | `measured` |
| Create network | `["container", "network", "create", "cca-pilot-backend-net"]` | Creates runtime network. | `measured` |
| Create named volume | `["container", "volume", "create", "cca-pilot-backend-db-data"]` | Creates runtime volume. | `measured` |
| Start database | `["container", "run", "--detach", "--name", "cca-pilot-backend-db", "--label", "com.container-compose-adapter.pilot.workload=backend-shaped", "--label", "com.container-compose-adapter.pilot.role=db", "--network", "cca-pilot-backend-net", "--publish", "127.0.0.1:15432:5432", "--env", "POSTGRES_USER=app", "--env", "POSTGRES_PASSWORD=<redacted>", "--env", "POSTGRES_DB=app", "--env", "PGDATA=/var/lib/postgresql/data/pgdata", "--volume", "cca-pilot-backend-db-data:/var/lib/postgresql/data", "docker.io/library/postgres:16-alpine"]` | May pull image, create VM/container, attach network/volume, publish port. | `measured` with PGDATA workaround |
| Database health gate | `["container", "exec", "cca-pilot-backend-db", "pg_isready", "-U", "app", "-d", "app"]` | Read-only process exec after runtime exists. | `measured` |
| Run migrate job | `["container", "run", "--remove", "--name", "cca-pilot-backend-migrate", "--label", "com.container-compose-adapter.pilot.role=migrate", "--network", "cca-pilot-backend-net", "--env", "PGPASSWORD=<redacted>", "docker.io/library/postgres:16-alpine", "sh", "-ec", "psql -h <db-ip> -U app -d app -v ON_ERROR_STOP=1 -c \"create table if not exists pilot_items (id serial primary key, name text not null);\""]` | May pull/run one-off container and depends on DB reachability. | `measured` with IP workaround |
| Run seed job | `["container", "run", "--remove", "--name", "cca-pilot-backend-seed", "--label", "com.container-compose-adapter.pilot.role=seed", "--network", "cca-pilot-backend-net", "--env", "PGPASSWORD=<redacted>", "docker.io/library/postgres:16-alpine", "sh", "-ec", "psql -h <db-ip> -U app -d app -v ON_ERROR_STOP=1 -c \"insert into pilot_items (name) values ('public-fixture') on conflict do nothing;\""]` | May pull/run one-off container and depends on migration result. | `measured` with IP workaround |
| Start API-like service | `["container", "run", "--detach", "--name", "cca-pilot-backend-api", "--label", "com.container-compose-adapter.pilot.role=api", "--network", "cca-pilot-backend-net", "--publish", "127.0.0.1:18081:8080", "docker.io/library/python:3.12-alpine", "python", "-c", "<fixture http server script using db ip>"]` | May pull image, create VM/container, attach network, publish port. | `measured` with IP workaround |
| HTTP readiness | `["curl", "-fsS", "http://127.0.0.1:18081/ready"]` | No runtime mutation, but meaningful only after run. | `measured` with IP workaround |
| Status/logs/stats | `["container", "list", "--all"]`, `["container", "logs", "cca-pilot-backend-api"]`, `["container", "stats", "--no-stream", "cca-pilot-backend-db", "cca-pilot-backend-api"]` | Read-only after runtime exists. | `measured` |
| Cleanup without volumes | `["container", "stop", "cca-pilot-backend-api", "cca-pilot-backend-db"]`, `["container", "delete", "cca-pilot-backend-api", "cca-pilot-backend-db"]`, `["container", "network", "delete", "cca-pilot-backend-net"]` | Stops/deletes runtime resources except named volume. | `measured`; named volume persisted |
| Cleanup with volumes | `["container", "volume", "delete", "cca-pilot-backend-db-data"]` | Deletes named volume. | `measured`; final volume list empty |

## Capability Gaps To Measure Later

These are now measured capability gaps or follow-up requirements:

- Apple `container` did not automatically resolve Compose service names such as `db` on the user-created network.
- Apple named volumes mounted directly at Postgres `PGDATA` include `lost+found`; Postgres needs a subdirectory such as `PGDATA=/var/lib/postgresql/data/pgdata`.
- Health gates can be enforced with `container exec` probes, but the adapter must implement polling and timeouts.
- One-off job containers with `--remove` work for migrate/seed, but their logs/status need adapter capture before removal.
- Port publishing on `127.0.0.1` worked for simple-web, database, and API-like services.
- `container stats --no-stream` provides usable per-container CPU/memory/network/block snapshots.

## Evidence Rows

| Run ID | Workload | Runtime | Operation | Status | Reason |
| --- | --- | --- | --- | --- | --- |
| `2026-06-11-simple-web-apple-native` | `simple-web` | `apple-container-cli` | cold/setup run, cached warm run, readiness, status, logs, repeated run, cleanup | `measured` | Works after `container system start`, recommended kernel install, and init image setup. Same-name repeated run is not idempotent. |
| `2026-06-11-backend-shaped-apple-native` | `backend-shaped` | `apple-container-cli` | network, volume, db, jobs, API readiness, logs/status, cleanup | `measured-with-workarounds` | Backend works only with PGDATA subdirectory and IP-based service targeting; exact Compose service-name behavior is not present. |

## Phase 3 Follow-up

Implement adapter-owned service discovery and named-volume compatibility diagnostics before claiming backend-shaped Compose parity on Apple `container`.
