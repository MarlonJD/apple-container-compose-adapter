# Stage 5 Backend-shaped Product Smoke Evidence

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-open`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Dry-run Evidence

Fixture-derived no-runtime evidence was generated from
`docs/evidence/fixtures/backend-shaped/compose.yaml`:

- Evidence:
  [20260612T093000Z-stage5-backend-smoke-dry-run.jsonl](../../evidence/linuxpod-stage5-backend-smoke/20260612T093000Z-stage5-backend-smoke-dry-run.jsonl)
- Command:
  `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name backend-shaped --timestamp 2026-06-12T09:30:00.000Z --evidence-jsonl docs/evidence/linuxpod-stage5-backend-smoke/20260612T093000Z-stage5-backend-smoke-dry-run.jsonl --store-root /tmp/container-compose-stage5-backend-smoke --validate-evidence`
- Validation: `stage5-validation: passed 12 capability check(s)`.

The JSONL record covers the Stage 5 dry-run product shape:

- Postgres service: `db`, image `docker.io/library/postgres:16-alpine`,
  image-default process metadata, redacted `POSTGRES_PASSWORD`, and
  deterministic host port `15432:5432/tcp`.
- Named volume: `db-data` planned under adapter-owned project state.
- Migrate job: `migrate` depends on `db:service_healthy`, runs after Postgres
  readiness, and captures job lifecycle in the dry-run.
- Seed job: `seed` depends on `migrate:service_completed_successfully` and is
  included in both `up` and `run` surfaces.
- API service: `api`, image `docker.io/library/python:3.12-alpine`, depends on
  `db:service_healthy` and `seed:service_completed_successfully`, and uses
  deterministic host port `18081:8080/tcp`.
- Service readiness/healthchecks: readiness waits exist for `db`, `migrate`,
  `seed`, and `api`; `db` and `api` preserve their healthcheck commands.
- service DNS/managed hosts: project runtime and container metadata preserve
  `127.0.0.1 db migrate seed api`.
- logs/status/run surfaces: `logs` renders four no-side-effect log collection
  actions; `status` renders no-side-effect inspection with
  `db,migrate,seed,api`; `run` prepares dependencies and jobs without starting
  the API service.
- Cleanup proof: `down --volumes` dry-run includes stop runtime, delete runtime,
  and `db-data` named-volume cleanup, with cleanup status still marked
  `not-run` / `planned-only`.

## Runtime Evidence Gap

No signed Stage 5 runtime smoke was run in this task. The user explicitly
required no runtime mutation until dry-run evidence passed and explicit runtime
approval was available. Dry-run evidence now passes, but no current-task runtime
approval was provided.

The active roadmap index should therefore keep Stage 5 open on the next
concrete todo: request explicit runtime approval for a signed Stage 5 runtime
smoke, then run exactly one backend-shaped fixture smoke with cleanup proof if
approval is granted.

## Verification

Completed in this task:

- `swift test --filter Stage5BackendSmokeTests`
- `swift run container-compose-stage5-backend-smoke ... --validate-evidence`
- `swift test`
- `git diff --check`

Remaining before Stage 5 can close:

- Signed runtime smoke with explicit current-task approval.
- Runtime cleanup proof showing zero adapter-owned leftovers except intended
  preserved cache state.
