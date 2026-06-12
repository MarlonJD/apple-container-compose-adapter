# Postgres API LinuxPod Boot Probe Observation

**Timestamp:** 2026-06-11T20:47:39Z runner start
**Scenario:** `postgres-api`
**Run ID:** `cca-linuxpod-spike-postgresapi-20260611T204739-1`
**Source observed before cleanup:** `docs/evidence/linuxpod-base-overhead/runtime/cca-linuxpod-spike-postgresapi-20260611T204739-1/boot.log`

## Observation

The runner exited with code `133` before writing JSONL metrics. Before cleanup,
the run's `boot.log` was inspected and showed that the pod had booted, the DB
and API fixture containers had both started, Postgres readiness succeeded on the
second readiness probe, and the SQL probe from the API fixture exited with
status `0`.

Observed boot-log events:

- `id=db ... started managed process`
- `id=api ... started managed process`
- `id=pg-ready-1 status=2`
- `id=pg-ready-2 status=0`
- `id=sql-probe status=0`

## Limitation

No memory, CPU, block I/O, DB footprint, or cleanup metrics were captured for
this run because the runner exited before JSONL recording. The spike-owned
runtime directory was later verified absent, and the final cleanup check showed
only the empty runtime root.
