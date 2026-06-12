# Efficiency Pilot Public Fixtures

These fixtures are public, local-only workloads for parser, planner, and runtime
research. The adapter now uses them as `ComposeFrontend` parser fixtures for
the `LocalDevProject` -> dry-run path. They are still not runtime execution
examples unless a separate task explicitly approves runtime mutation.

## Supported Adapter Parser Slice

The current `ComposeFrontend` slice reads these fixture Compose files into
`LocalDevProject` and renders dry-run plans. The supported subset covers public
images, command and healthcheck intent, deterministic host ports, named
volumes, dependency conditions, environment values with secret redaction in
dry-run output, and explicit migrate/seed job roles from fixture labels.

Runtime mutation, image pulls, registry login, host DNS mutation, Kubernetes
input, persistent LinuxPod hotplug, rootfs-cache optimization, writable layers,
and Docker-compatible backend switching remain out of scope for these fixtures.

## Safety Rules

- Use project names prefixed with `cca-pilot-`.
- Use high host ports to avoid common local conflicts.
- Do not mount host credential directories.
- Treat every `docker compose up`, image pull, image build, container run,
  network create, volume create, and cleanup command as runtime mutation.
- Run dry-run/planned-command review first, then ask for explicit approval
  before executing runtime mutations.

## Fixture Paths

| Workload | Compose file | Purpose |
| --- | --- | --- |
| `simple-web` | [simple-web/compose.yaml](simple-web/compose.yaml) | One public HTTP service on `localhost:18080`; no volumes. |
| `backend-shaped` | [backend-shaped/compose.yaml](backend-shaped/compose.yaml) | Public database, migrate job, seed job, API-like HTTP service, named volume, and dependency gates. |

## Docker/OrbStack Baseline Command Plan

These commands were not run during the pilot continuation on 2026-06-11 because
they would pull images, create containers, create networks, create volumes, and
remove runtime resources.

### Simple Web

```bash
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml config
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml up -d --wait
curl -fsS http://127.0.0.1:18080/
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml ps
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml logs --tail=80
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml down
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml up -d --wait
docker compose -p cca-pilot-simple -f docs/evidence/fixtures/simple-web/compose.yaml down --volumes
```

### Backend-shaped

```bash
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml config
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml up -d --wait
curl -fsS http://127.0.0.1:18081/ready
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml ps
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml logs --tail=120
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml run --rm api python -c "import socket; socket.create_connection(('db', 5432), timeout=2).close(); print('db reachable')"
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml down
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml up -d --wait
docker compose -p cca-pilot-backend -f docs/evidence/fixtures/backend-shaped/compose.yaml down --volumes
```

## Metrics To Capture When Approved

- Cold start time to HTTP readiness.
- Warm start time to HTTP readiness.
- Repeated `up` idempotency and resource count.
- Rebuild time when a build-based variant exists.
- Idle and peak container CPU/memory using runtime stats.
- Disk usage before and after using runtime `df`/resource count probes.
- Log/status responsiveness.
- Named volume persistence across `down`.
- Named volume removal only after `down --volumes`.
- Cleanup scope: only `cca-pilot-*` runtime resources should be removed.
