# Stage 5 Backend-shaped Product Smoke Evidence

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
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

## Runtime Smoke Evidence

Explicit current-task runtime approval was granted on 2026-06-12 for exactly
one signed backend-shaped fixture runtime smoke. The smoke used the
fixture-derived path: `ComposeFrontend` parsed
`docs/evidence/fixtures/backend-shaped/compose.yaml`, `AppleNativePlanner`
produced the runtime plan, and the signed debug `container-compose-adapter`
binary (new `--compose-file` flag, virtualization entitlement verified via
`doctor`) executed it through `LinuxPodBackend` with the explicit approval
token.

Runtime execution JSONL:

- Up:
  [20260612T110105Z-stage5-backend-smoke-runtime-up.jsonl](../../evidence/linuxpod-stage5-backend-smoke/20260612T110105Z-stage5-backend-smoke-runtime-up.jsonl)
- Status (no-side-effect):
  [20260612T110105Z-stage5-backend-smoke-runtime-status.jsonl](../../evidence/linuxpod-stage5-backend-smoke/20260612T110105Z-stage5-backend-smoke-runtime-status.jsonl)
- Cleanup proof:
  [20260612T110105Z-stage5-backend-smoke-runtime-down-cleanup.jsonl](../../evidence/linuxpod-stage5-backend-smoke/20260612T110105Z-stage5-backend-smoke-runtime-down-cleanup.jsonl)

Functional results from the single `up` run (all 16 actions `executed`):

- `db` Postgres started from image defaults; healthcheck readiness passed;
  on-disk `db.stderr.log` ended with `database system is ready to accept
  connections`.
- `migrate` one-off job exited `0` after `db:service_healthy`; `CREATE TABLE`
  captured in `migrate.stdout.log` over service DNS host `db`.
- `seed` one-off job exited `0` after
  `migrate:service_completed_successfully`; `INSERT 0 1` captured in
  `seed.stdout.log`.
- `api` started after `db:service_healthy` and
  `seed:service_completed_successfully`; HTTP `/ready` healthcheck readiness
  passed.
- `db-data` named volume existed as adapter-owned `volumes/db-data/volume.ext4`
  during the run.
- Per-service stdout/stderr log files existed for all four services under the
  adapter-owned `runtime/logs/` directory.
- Secrets stayed redacted in recorded evidence (`<redacted>`, no
  `dev_password`).

Cleanup and zero-leftover proof after `down --volumes`
(`stopProjectRuntime`, `deleteProjectRuntime`, `cleanupNamedVolume` all
`executed`):

- `.container-compose-adapter/` removed entirely, including runtime state,
  image store, rootfs caches, logs, and the `db-data` volume.
- Host ports `15432` and `18081` closed (`lsof` empty).
- No leftover adapter or VM processes.
- No `/tmp` store-root state was created.
- Intended preserved cache state: only the pre-existing Apple `container`
  kernel cache under
  `~/Library/Application Support/com.apple.container/kernels` (not
  adapter-owned) remained untouched.

This closes the Stage 5 runtime evidence gap. The smoke proves functional
product shape only; it does not justify replacement or performance claims, and
the Phase 6 `linuxpod-not-promising` benchmark decision stands.

## Verification

Completed across the dry-run task and the approved runtime smoke task:

- `swift test --filter Stage5BackendSmokeTests`
- `swift run container-compose-stage5-backend-smoke ... --validate-evidence`
  (pre-runtime regeneration matched the committed dry-run JSONL byte-for-byte
  and passed all 12 capability checks)
- `swift test` (82 tests, 0 failures) and `git diff --check` before any
  runtime mutation
- Signed runtime smoke: one `up`, one `status`, one `down --volumes` with
  runtime execution JSONL validated for project naming, approval gating, job
  exit codes, readiness coverage, secret redaction, and cleanup action order
- Zero-leftover inspection after cleanup (state directory, ports, processes,
  `/tmp` store root)
- Full `swift test` and `git diff --check` after the runtime smoke
