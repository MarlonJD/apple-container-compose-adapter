# Pilot Phase 1 Harness Design

**Date:** 2026-06-11
**Linked plan:** [Efficiency And Shared Runtime Pilot Plan](../completed/2026-06-11-efficiency-and-shared-runtime-pilot-plan.md)
**Scope:** Measurement evidence schema, command wrapper contract, redaction rules, resource snapshot strategy, evidence statuses, and dry-run/no-mutation rules for later Docker/OrbStack and Apple `container` runtime measurements.

## Phase 1 Verdict

The pilot can proceed only with a dry-run-first measurement harness. The harness contract below is intentionally runtime-neutral: it can describe Docker Compose, Apple `container`, local host probes, and skipped evidence without implying that a mutating runtime command is safe to run.

No runtime resources were created, started, stopped, pulled, built, removed, pruned, or cleaned up during this phase.

## Evidence Statuses

Use one of these statuses for every evidence row.

| Status | Meaning | Required fields |
| --- | --- | --- |
| `measured` | The command or probe ran and produced usable evidence. | Command, timestamps, exit code, redacted output summary, resource snapshots where applicable, versions, and machine context. |
| `skipped-runtime-unavailable` | The required runtime binary or service is unavailable and the command cannot run. | Missing runtime detail, detection command, and next unblock. |
| `cli-available-service-stopped` | The CLI is installed, but its service or API backend is stopped/unregistered. | CLI version, status command output, and the explicit start command that was not run. |
| `skipped-approval-not-granted` | The command would mutate runtime state and explicit approval was not provided in the current task. | Command plan, mutation category, expected resources, and approval needed. |
| `blocked` | Evidence cannot be collected safely or truthfully in this phase. | Blocking reason, owner decision needed, and whether fallback evidence exists. |

## Evidence Schema

Each benchmark run should be recorded as a Markdown table row and, once a CLI harness exists, as JSON with the same field names.

| Field | Description |
| --- | --- |
| `run_id` | Stable ID such as `2026-06-11-simple-web-docker-cold-01`. |
| `phase` | Pilot phase number and name. |
| `workload` | `simple-web`, `backend-shaped`, or another documented fixture. |
| `runtime` | `docker-orbstack`, `apple-container-cli`, `apple-containerization-api`, or `host-probe`. |
| `operation` | Cold up, warm up, rebuild, readiness probe, status, logs, down, down-volumes, snapshot, or cleanup. |
| `status` | One of the statuses above. |
| `mutation_kind` | `none`, `pull`, `build`, `create`, `start`, `stop`, `delete`, `prune`, `volume-delete`, or `network-delete`. |
| `approval_gate` | `not-required`, `required-not-granted`, or `granted-in-thread`. |
| `argv` | Argument array. Never store shell-concatenated command strings as execution truth. |
| `dry_run_argv` | Argument array that would be rendered before mutation, when applicable. |
| `started_at` / `ended_at` | ISO-8601 local timestamps with timezone. |
| `duration_ms` | Wall-clock duration. |
| `exit_code` | Exit status, or `not-run`. |
| `stdout_summary` / `stderr_summary` | Redacted summaries, capped to the minimum needed for evidence. |
| `readiness_probe` | URL, TCP target, command, timeout, interval, and observed result. |
| `resource_snapshot_before` / `resource_snapshot_after` | Snapshot IDs or embedded compact metrics. |
| `versions` | macOS, architecture, Docker, Compose, OrbStack if available, Apple `container`, and fixture digest or commit. |
| `notes` | Factual caveats only; no inferred performance claims. |

## Command Wrapper Contract

The future harness must execute commands through an argv-array boundary:

- Store command identity as `[executable, arg1, arg2, ...]`.
- Do not execute shell strings or interpolate Compose values into a shell command.
- Capture start time, end time, duration, exit code, stdout, stderr, and cancellation reason.
- Redact stdout, stderr, env, and argv before writing evidence.
- Record whether the command is no-side-effect or mutating before execution.
- Refuse mutating commands unless the phase has a dry-run record and the user explicitly approved the mutation in the current task.
- Write a structured failure row instead of retrying repeatedly.

## Dry-run And No-mutation Rules

Before any runtime mutation, the harness must produce a dry-run record containing:

- Fixture path and workload name.
- Project/resource prefix such as `cca-pilot-simple` or `cca-pilot-backend`.
- Planned containers, networks, volumes, images, labels, ports, mounts, readiness probes, and cleanup targets.
- Rendered Docker Compose or Apple `container` argv arrays.
- Resource ownership labels/names.
- Explicit cleanup plan for `down` and `down --volumes`.
- Secret redaction preview.

Commands classified as mutating include runtime service start/stop, image pull, image build, container create/run/start/stop/delete, network create/delete/prune, volume create/delete/prune, and Docker/Apple cleanup. These require explicit approval in the active thread before they run.

## Resource Snapshot Strategy

Use the narrowest read-only probe that answers the metric.

| Snapshot | Docker/OrbStack probe | Apple `container` probe | Fallback / caveat |
| --- | --- | --- | --- |
| Runtime availability | `docker context show`, `docker version`, `docker compose version` | `container --version`, `container system status` | If Apple apiserver is stopped, mark runtime rows `cli-available-service-stopped`. |
| Disk/resource counts | `docker system df`, project-scoped `docker compose ps` | `container system df`, `container list --all`, `container network list`, `container volume list` | Apple probes need the service running; do not start it without approval. |
| CPU/memory | `docker stats --no-stream` for project containers | `container stats` for named containers | Host-level totals can be noisy; capture before/after and label them advisory. |
| Readiness | HTTP `localhost` probe and service health status | HTTP `localhost` probe and container/process status | Do not compare across runtimes unless both were measured on the same machine. |
| Cleanup | Project-scoped container/network/volume lists before and after `down` | Project-scoped container/network/volume lists before and after cleanup | Cleanup commands are mutating and need approval. |

## Redaction Rules

Redact values, not keys, when keys contain:

`PASSWORD`, `PASS`, `TOKEN`, `SECRET`, `KEY`, `CREDENTIAL`, `PRIVATE`, `AUTH`, `SESSION`, `COOKIE`, `DSN`, `DATABASE_URL`, `PGPASSWORD`, `AWS_`, `GCP_`, `AZURE_`, or `SSH`.

Also redact:

- URL userinfo such as `scheme://user:password@host`.
- Registry credentials and bearer tokens.
- Absolute paths under credential directories such as `.ssh`, `.docker`, `.kube`, cloud SDK config, and Keychain-related exports.
- Private hostnames or paths if a future EMSI backend validation is explicitly requested.

Dummy fixture secrets such as `POSTGRES_PASSWORD=dev_password` should still be redacted in command previews to prove the rule works.

## Phase 1 Follow-up

Use the fixture docs in Phase 2 to exercise this schema without running mutating commands. Runtime baseline rows should remain `skipped-approval-not-granted` until the user approves Docker/OrbStack and Apple `container` mutations.
