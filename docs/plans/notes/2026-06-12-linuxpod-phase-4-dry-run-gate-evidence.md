# LinuxPod Phase 4 Dry-run Gate Evidence

**Date:** 2026-06-12
**Linked plan:** [LinuxPod Compose Runtime Backend Implementation Plan](../2026-06-12-linuxpod-compose-runtime-backend-plan.md)
**Decision:** `phase-4-backend-shaped-runtime-smoke-passed`
**Runtime mutation:** Approved Phase 4 `up` smoke executed end to end; cleanup verified.

## Decision

Phase 4 has dry-run evidence for the public backend-shaped DB -> migrate ->
seed -> API fixture. The adapter renders one project LinuxPod, pod-level
adapter-managed hosts entries, dependency-ordered service and job actions,
readiness conditions, and dry-run coverage for `up`, `down`, `logs`, `status`,
and `run`.

The approved signed Phase 4 backend-shaped LinuxPod runtime `up` smoke remains
blocked. The retry proved the entitlement and VM boot path are working: the DB
managed process started, then exited before readiness. The later LinuxPod
`vmexec` `No such process` error happens when the second readiness probe targets
the already-exited DB process. Do not proceed to Phase 5 host footprint work or
Phase 6 benchmark repeats until the backend applies the required image process
defaults, the public fixture starts successfully, and cleanup is reproven.

Update after the OCI-defaults implementation: the code-side missing-defaults
blocker has been addressed and fresh dry-run evidence exists. A later
runtime-approved smoke failed with `VZErrorDomain Code=2`
(`Virtualization is not available on this hardware`), but that diagnosis was
reclassified: the host supports VM creation (`kern.hv_support=1` on
`Mac14,7` Apple M2, native arm64), and the same signed binary created and
booted the project LinuxPod when the smoke was re-run outside the sandboxed
shell. The VZ failure came from sandbox-denied Hypervisor access, corroborated
by `sysmond` being unavailable to `pgrep` in the same sandboxed context. The
escalated re-run was blocked again by the DB managed process exiting with
status `1` before readiness even with OCI image process defaults applied. The
LinuxPod executor did not capture service container stdout/stderr, so the
postgres startup error was not yet observable; service-level log capture was
the next prerequisite.

Final update: service log capture was implemented and the captured postgres
stderr identified the real blockers in volume and pod semantics, which were
fixed in the LinuxPod executor and planner. The approved signed Phase 4
backend-shaped runtime `up` smoke then passed end to end: the DB became
healthy, the migrate and seed jobs exited `0` with captured psql output, the
API service started and passed readiness through the `db` hosts entry, and the
approved `down --volumes` cleanup was reproven. Phase 5 host footprint work is
unblocked.

## Dry-run Evidence

Commands:

```bash
swift run container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T020100-phase4-backend-shaped-dry-run.jsonl up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --volumes --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-down-dry-run.jsonl down
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-logs-dry-run.jsonl logs
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-status-dry-run.jsonl status
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-run-dry-run.jsonl run
```

Evidence:

- Up JSONL: [Phase 4 backend-shaped up dry-run](../../evidence/linuxpod-compose-runtime/20260612T020100-phase4-backend-shaped-dry-run.jsonl)
- Down JSONL: [Phase 4 backend-shaped down dry-run](../../evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-down-dry-run.jsonl)
- Logs JSONL: [Phase 4 backend-shaped logs dry-run](../../evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-logs-dry-run.jsonl)
- Status JSONL: [Phase 4 backend-shaped status dry-run](../../evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-status-dry-run.jsonl)
- Run JSONL: [Phase 4 backend-shaped run dry-run](../../evidence/linuxpod-compose-runtime/20260612T020200-phase4-backend-shaped-run-dry-run.jsonl)
- Record count: `1` per file.
- Project resource: `cca-linuxpod-phase4-backend`.
- Hosts entry: `127.0.0.1 db migrate seed api`.
- Ordered `up` service flow:
  `db -> migrate -> seed -> api`.
- Readiness conditions:
  `db:service_healthy`, `migrate:service_completed_successfully`,
  `seed:service_completed_successfully`, `api:service_started`.
- Secret redaction: `POSTGRES_PASSWORD=<redacted>`.
- Cleanup proof: `runtimeMutation=not-run`, `globalCleanup=not-run`,
  `ownedPrefix=cca-linuxpod-`.
- `.container-compose-adapter` state directory: absent after all dry-runs.

## Approved Runtime Smoke Attempt

Approval:

```text
I approve the signed Phase 4 backend-shaped LinuxPod runtime up smoke and cleanup verification using only cca-linuxpod-phase4-backend resources.
```

Commands:

```bash
swift build
scripts/sign-debug-runtime.sh
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod doctor
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T023700-phase4-backend-shaped-runtime-up.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --volumes --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T024700-phase4-backend-shaped-runtime-down-cleanup-emptydirs.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION down
```

Evidence:

- Blocker JSONL: [Phase 4 backend-shaped up blocker](../../evidence/linuxpod-compose-runtime/20260612T023700-phase4-backend-shaped-runtime-up-blocked.jsonl)
- Cleanup JSONL: [Phase 4 backend-shaped cleanup after blocker](../../evidence/linuxpod-compose-runtime/20260612T024700-phase4-backend-shaped-runtime-down-cleanup-emptydirs.jsonl)

Result:

- Signed binary entitlement was present before runtime mutation.
- `up` failed at `startContainer.db` with LinuxPod `vmexec` process-start
  failure:
  `NSPOSIXErrorDomain Code=3`, `No such process`, `no PID data from sync pipe`.
- The command failed before execution JSONL could be written by the CLI, so a
  blocker JSONL record captures the failure.
- Runtime state was partially created under
  `.container-compose-adapter/cca-linuxpod-phase4-backend` before cleanup.
- Approved cleanup executed `stopProjectRuntime` and `deleteProjectRuntime`.
- After the cleanup fix, `.container-compose-adapter` is absent.
- A filtered command-name process check found no `container-compose-adapter`,
  `vmexec`, or `vminit` process remaining.
- No private EMSI workload, registry login, prune, global cleanup, Docker Hub
  credential change, Keychain change, host DNS mutation, branch operation,
  commit, push, or parent monorepo pointer update was performed.

## Approved Runtime Retry

Approval:

```text
tekrar dene sorun ne niye olmuyor
```

Commands:

```bash
scripts/sign-debug-runtime.sh
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod doctor
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T030500-phase4-backend-shaped-retry-dry-run.jsonl up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T030600-phase4-backend-shaped-runtime-up-retry.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --volumes --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T031000-phase4-backend-shaped-runtime-down-cleanup-retry.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION down
```

Evidence:

- Retry dry-run JSONL: [Phase 4 backend-shaped retry up dry-run](../../evidence/linuxpod-compose-runtime/20260612T030500-phase4-backend-shaped-retry-dry-run.jsonl)
- Retry blocker JSONL: [Phase 4 backend-shaped retry up blocker](../../evidence/linuxpod-compose-runtime/20260612T030600-phase4-backend-shaped-runtime-up-retry-blocked.jsonl)
- Retry cleanup JSONL: [Phase 4 backend-shaped retry cleanup](../../evidence/linuxpod-compose-runtime/20260612T031000-phase4-backend-shaped-runtime-down-cleanup-retry.jsonl)

Result:

- Signed binary entitlement was present before runtime mutation; `doctor`
  reported `virtualization entitlement: present`.
- The project LinuxPod booted and `vminitd` served gRPC.
- The Postgres rootfs mounted successfully.
- The DB managed process started with a PID, then exited with status `1`.
- The first readiness probe exited with status `2`.
- The second readiness probe failed with `NSPOSIXErrorDomain Code=3`,
  `No such process`, and `no PID data from sync pipe` because the DB process
  had already exited.
- The retry command failed before execution JSONL could be written by the CLI,
  so a blocker JSONL record captures the failure.
- The retry's public Postgres image config requires image process defaults:
  `Entrypoint=["docker-entrypoint.sh"]`, `Cmd=["postgres"]`,
  `WorkingDir="/"`, default environment including `PGDATA`, and declared data
  volume metadata. The current LinuxPod executor launches only the Compose
  service command (`postgres`) and service environment, so it skips the image
  entrypoint/init path that Docker Compose would apply.
- Approved cleanup executed `stopProjectRuntime` and `deleteProjectRuntime`.
- After cleanup, `.container-compose-adapter` is absent.
- Exact process-name checks for `container-compose-adapter`, `vmexec`, and
  `vminit` returned no matches.

## Implementation Notes

- The public backend-shaped sample is selected by `--sample backend-shaped`.
- Pod-level hosts metadata is added to the `createProjectRuntime` action and
  service-level dry-run metadata. The concrete LinuxPod executor translates the
  metadata into `Containerization.Hosts` pod configuration.
- The runtime executor now handles job start/wait, supported readiness checks,
  log/status event validation, and explicit adapter-owned cleanup actions.
- `ExecutionResult` now preserves action-level runtime results. Backend-shaped
  tests prove that `runJob` result metadata can carry job exit status and log
  capture evidence through the backend boundary. The concrete LinuxPod executor
  reports job exit codes from `waitContainer` and attaches stdout/stderr writers
  to one-off job containers so captured output can be summarized in runtime
  evidence metadata. Runtime proof still requires the approved Phase 4 smoke.
- Execution results now render action-level metadata through the CLI in text
  and JSON, so `run`, `logs`, `status`, and cleanup commands can expose backend
  evidence instead of only printing a generic `executed` status.
- The LinuxPod `run` command now plans a fresh project runtime path for
  one-off jobs: create/reuse the project LinuxPod, prepare only required image
  rootfs state, start dependency services and readiness gates, run jobs in
  dependency order, and avoid starting unrelated services such as the API.
- A durable signing remediation is now encoded in code and docs. Missing
  `com.apple.security.virtualization` entitlement errors point to
  `scripts/sign-debug-runtime.sh`, the LinuxPod `doctor` command reports the
  current process entitlement status, and the README documents that rebuilds
  can replace the binary and require re-signing before runtime mutation.
- Runtime cleanup now removes empty adapter-owned project/root directories after
  deleting the `runtime` directory. This closes the cleanup gap observed after
  the failed Phase 4 smoke left an empty
  `.container-compose-adapter/cca-linuxpod-phase4-backend` directory.
- The Phase 4 retry narrowed the blocker from an entitlement or VM boot problem
  to missing OCI image process defaults in the LinuxPod backend. That code-side
  blocker is now addressed: `prepareImageRootfs` resolves image
  `Entrypoint`, `Cmd`, default `Env`, `WorkingDir`, user, and declared volume
  metadata from the pulled public image; `addContainer` uses image defaults for
  services without a Compose command override and merges service environment
  overrides. Runtime action metadata records process source, arguments,
  working directory, image default environment count, and declared volumes.
- Cross-command runtime state is still not durable across separate CLI process
  invocations. The first Phase 4 runtime smoke should therefore prove the
  ordered `up` path in one signed process, then run the approved cleanup command.
  Broader runtime `logs`, `status`, and standalone `run` proof should be a
  follow-up after durable runtime state or an in-process smoke harness exists.

## OCI Defaults Dry-run Refresh

Commands:

```bash
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T062300-phase4-backend-shaped-oci-defaults-up-dry-run.jsonl up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T062300-phase4-backend-shaped-oci-defaults-run-dry-run.jsonl run
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --dry-run --sample backend-shaped --project-name phase4-backend --volumes --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T062300-phase4-backend-shaped-oci-defaults-down-dry-run.jsonl down
```

Evidence:

- OCI-defaults `up` dry-run JSONL: [20260612T062300-phase4-backend-shaped-oci-defaults-up-dry-run](../../evidence/linuxpod-compose-runtime/20260612T062300-phase4-backend-shaped-oci-defaults-up-dry-run.jsonl)
- OCI-defaults `run` dry-run JSONL: [20260612T062300-phase4-backend-shaped-oci-defaults-run-dry-run](../../evidence/linuxpod-compose-runtime/20260612T062300-phase4-backend-shaped-oci-defaults-run-dry-run.jsonl)
- OCI-defaults `down --volumes` dry-run JSONL: [20260612T062300-phase4-backend-shaped-oci-defaults-down-dry-run](../../evidence/linuxpod-compose-runtime/20260612T062300-phase4-backend-shaped-oci-defaults-down-dry-run.jsonl)

Dry-run result:

- Project resource remains `cca-linuxpod-phase4-backend`.
- The DB add-container action now records `process=image-defaults` and
  `imageDefaults=Entrypoint+Cmd+Env+WorkingDir+DeclaredVolumes resolved during
  prepareImageRootfs`.
- The DB named volume `db-data` maps to the adapter-owned path
  `.container-compose-adapter/cca-linuxpod-phase4-backend/volumes/db-data`.
- Public image rootfs actions are planned for
  `mirror.gcr.io/library/postgres:16-alpine` and
  `mirror.gcr.io/library/python:3.12-alpine`.
- Service hosts remain `127.0.0.1 db migrate seed api`.
- Secret redaction remains active for `POSTGRES_PASSWORD=<redacted>`.
- `down --volumes` plans only adapter-owned project runtime deletion and
  `db-data` named-volume cleanup.
- `.container-compose-adapter` was absent after the dry-runs, proving no
  runtime state was created by the dry-run refresh.

## Signed Runtime Preflight Refresh

Timestamp: `2026-06-12T03:26:49Z`.

Commands:

```bash
swift build
scripts/sign-debug-runtime.sh
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod doctor
```

Result:

- The sandboxed `swift build` attempt failed with `sandbox_apply: Operation not
  permitted`, then the same command passed when rerun with sandbox escalation.
- `scripts/sign-debug-runtime.sh` replaced the debug binary signature and
  confirmed `com.apple.security.virtualization` was present.
- Signed-binary `doctor` printed `runtime: linuxpod`, `runtime mutation:
  requires explicit approval`, and `virtualization entitlement: present`.
- `.container-compose-adapter` was absent after the preflight, so no LinuxPod
  runtime state was created.

## Approved OCI Defaults Runtime Smoke Attempt

Approval:

```text
Evet onaylıyorum
```

The approval was given in response to the exact prompt asking whether to run
the signed Phase 4 LinuxPod runtime smoke and cleanup.

Commands:

```bash
swift build
scripts/sign-debug-runtime.sh
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod doctor
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T033000-phase4-backend-shaped-oci-defaults-runtime-up.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --volumes --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T033200-phase4-backend-shaped-oci-defaults-runtime-down-cleanup-after-vz-unavailable.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION down
```

Evidence:

- Runtime blocker JSONL: [20260612T033000-phase4-backend-shaped-oci-defaults-runtime-up-vz-unavailable-blocked](../../evidence/linuxpod-compose-runtime/20260612T033000-phase4-backend-shaped-oci-defaults-runtime-up-vz-unavailable-blocked.jsonl)
- Cleanup JSONL: [20260612T033200-phase4-backend-shaped-oci-defaults-runtime-down-cleanup-after-vz-unavailable](../../evidence/linuxpod-compose-runtime/20260612T033200-phase4-backend-shaped-oci-defaults-runtime-down-cleanup-after-vz-unavailable.jsonl)

Result:

- `swift build` passed after sandbox escalation, and signing confirmed
  `com.apple.security.virtualization`.
- Signed-binary `doctor` reported `virtualization entitlement: present`.
- The `up` command failed during `createProjectRuntime` before service
  containers were added:
  `VZErrorDomain Code=2`, `Virtualization is not available on this hardware`.
- The CLI did not write the requested runtime `up` JSONL because execution
  failed before it could emit execution evidence, so a manual blocker JSONL
  record captures the error.
- Approved `down --volumes` cleanup executed `stopProjectRuntime`,
  `deleteProjectRuntime`, and `cleanupNamedVolume` for `db-data`.
- `.container-compose-adapter` was absent after cleanup.
- `pgrep` could not inspect processes because local `sysmond` was unavailable;
  an escalated `ps` fallback with a self-filtering pattern found no lingering
  `container-compose-adapter`, `vmexec`, or `vminit` processes.
- No private EMSI workload, registry login, prune, global cleanup, Docker Hub
  credential change, Keychain change, host DNS mutation, branch operation,
  commit, push, or parent monorepo pointer update was performed.

## Escalated Runtime Smoke Re-run And Blocker Reclassification

Approval: re-run of the already-approved Phase 4 runtime smoke from the
current task, after host capability evidence contradicted the
`blocked-virtualization-unavailable-on-hardware` diagnosis. The smoke and
cleanup were executed escalated outside the sandboxed shell, the same way
`swift build` required escalation.

Host capability evidence:

```text
kern.hv_support: 1
hw.model: Mac14,7
machdep.cpu.brand_string: Apple M2
hw.optional.arm64: 1
sysctl.proc_translated: 0
```

Commands:

```bash
codesign -d --entitlements - .build/arm64-apple-macosx/debug/container-compose-adapter
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod doctor
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T033600-phase4-backend-shaped-oci-defaults-runtime-up-escalated.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --volumes --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T033900-phase4-backend-shaped-oci-defaults-runtime-down-cleanup-after-escalated-db-exit.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION down
```

Evidence:

- Runtime blocker JSONL: [20260612T033800-phase4-backend-shaped-oci-defaults-runtime-up-escalated-db-exit-blocked](../../evidence/linuxpod-compose-runtime/20260612T033800-phase4-backend-shaped-oci-defaults-runtime-up-escalated-db-exit-blocked.jsonl)
- Cleanup JSONL: [20260612T033900-phase4-backend-shaped-oci-defaults-runtime-down-cleanup-after-escalated-db-exit](../../evidence/linuxpod-compose-runtime/20260612T033900-phase4-backend-shaped-oci-defaults-runtime-down-cleanup-after-escalated-db-exit.jsonl)

Result:

- The signed binary still carried `com.apple.security.virtualization` and
  `doctor` reported `virtualization entitlement: present`.
- Escalated execution got past `createProjectRuntime`: both public images were
  pulled, rootfs ext4 images were built, the project LinuxPod booted, and
  `vminitd` served gRPC on vsock. This disproves the hardware diagnosis for
  the `VZErrorDomain Code=2` blocker; the sandboxed shell denying Hypervisor
  access explains it, corroborated by `sysmond` being unavailable to `pgrep`
  during the sandboxed cleanup of the failed attempt.
- The DB managed process `cca-linuxpod-phase4-backend-db` started with
  pid `103` and exited with status `1` within the same second, per
  `runtime/boot.log`.
- `readiness-db-1` `startProcess` then failed with `NSPOSIXErrorDomain
  Code=3`, `No such process`, and `no PID data from sync pipe` because the DB
  process was already gone — the same blocker class as the earlier retry, now
  persisting with OCI image process defaults applied.
- The CLI did not write the requested runtime `up` JSONL because execution
  failed before it could emit execution evidence, so a manual blocker JSONL
  record captures the error and supersedes the VZ-unavailable blocker record.
- The DB service stdout/stderr was not captured anywhere in the runtime state
  directory, so the postgres startup error is not yet observable. Service-level
  log capture in the LinuxPod executor is required to diagnose the exit.
- Approved `down --volumes` cleanup executed `stopProjectRuntime`,
  `deleteProjectRuntime`, and `cleanupNamedVolume` for `db-data`, and the CLI
  wrote the cleanup execution JSONL.
- `.container-compose-adapter` was absent after cleanup, and an escalated `ps`
  command-name check found no lingering `container-compose-adapter`, `vmexec`,
  or `vminit` processes.
- No private EMSI workload, registry login, prune, global cleanup, Docker Hub
  credential change, Keychain change, host DNS mutation, branch operation,
  commit, push, or parent monorepo pointer update was performed.

## Service Log Capture, Volume Semantics Fixes, And Passing Runtime Smoke

Approval: continuation of the already-approved Phase 4 runtime smoke from the
current task. All runtime commands ran escalated outside the sandboxed shell.

After service-level log capture was implemented, three runtime blockers were
diagnosed from captured service stderr and fixed in order:

1. **virtiofs named volume rejected chown/chmod.** With log capture attached,
   the DB stderr showed
   `chown: /var/lib/postgresql/data: Operation not permitted` from the
   postgres entrypoint. Named volumes were virtiofs `Mount.share` directories,
   which reject guest ownership changes. Fix: named volumes are now guest-local
   ext4 block images (`volumes/<name>/volume.ext4`) created with
   `EXT4.Formatter` and mounted with `Mount.block`, matching Docker's
   VM-local named-volume semantics. This closes the known
   "direct Postgres volume parity" gap from the pilot Phase 3 note.
2. **`lost+found` broke initdb.** The formatter-created `/lost+found` made
   initdb fail with `directory "/var/lib/postgresql/data" exists but is not
   empty`. Fix: the adapter unlinks `/lost+found` while formatting the volume
   image.
3. **LinuxPod rejects addContainer after pod creation.** With the DB healthy,
   adding the migrate container failed with
   `pod must be initialized to add container`. LinuxPod only accepts container
   registration before the pod VM is created. Fix: the planner now emits all
   `addContainer` actions before the first `startContainer`/`runJob` in `up`
   and `run` plans; start, job, and readiness ordering still follows
   `depends_on` dependency order.

A fourth correctness fix shipped with the registration-ordering change:
containers sharing one image (migrate, seed, api on the python image) no
longer attach the same ext4 block image read-write; each container gets a
private APFS clone of the prepared base rootfs under
`runtime/rootfs/containers/<containerID>.ext4`.

Commands:

```bash
swift build
swift test
scripts/sign-debug-runtime.sh
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod doctor
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T040900-phase4-backend-shaped-ordered-runtime-up.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION up
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --sample backend-shaped --project-name phase4-backend --volumes --format json --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T041100-phase4-backend-shaped-ordered-runtime-down-cleanup.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION down
```

Evidence:

- Passing runtime `up` JSONL (CLI-written execution record):
  [20260612T040900-phase4-backend-shaped-ordered-runtime-up](../../evidence/linuxpod-compose-runtime/20260612T040900-phase4-backend-shaped-ordered-runtime-up.jsonl)
- Cleanup JSONL after the passing smoke:
  [20260612T041100-phase4-backend-shaped-ordered-runtime-down-cleanup](../../evidence/linuxpod-compose-runtime/20260612T041100-phase4-backend-shaped-ordered-runtime-down-cleanup.jsonl)
- Cleanup JSONLs bracketing the intermediate diagnostic attempts:
  [20260612T035600 before the block-volume retry](../../evidence/linuxpod-compose-runtime/20260612T035600-phase4-backend-shaped-runtime-down-cleanup-before-blockvolume-retry.jsonl),
  [20260612T040000 before the lost+found retry](../../evidence/linuxpod-compose-runtime/20260612T040000-phase4-backend-shaped-runtime-down-cleanup-before-lostfound-retry.jsonl),
  [20260612T040800 before the ordered retry](../../evidence/linuxpod-compose-runtime/20260612T040800-phase4-backend-shaped-runtime-down-cleanup-before-ordered-retry.jsonl)
- The intermediate failed `up` attempts exited before the CLI could write
  execution JSONL; their diagnostic stderr is quoted above and the new
  readiness errors embed captured service log tails.

Result:

- The full backend-shaped `up` executed: project LinuxPod created, both public
  image rootfs prepared, `db-data` block volume created, all four containers
  registered before VM creation, DB started and passed `pg_isready`
  readiness, migrate exited `0` with `CREATE TABLE` captured, seed exited `0`
  with `INSERT 0 1` captured, API started and passed readiness by connecting
  to `db:5432` through the pod hosts entry.
- Service-name connectivity through adapter-managed pod `Hosts` entries is now
  runtime-proven: migrate and seed used `psql -h db`, and the API readiness
  connected to `("db", 5432)`.
- One-off job execution with captured exit status and logs is runtime-proven
  through the CLI-written execution JSONL action metadata.
- Service containers now write stdout/stderr to in-memory capture plus
  `runtime/logs/<service>.<stream>.log`, and readiness/job failures embed the
  captured log tails in error messages.
- Approved `down --volumes` cleanup executed `stopProjectRuntime`,
  `deleteProjectRuntime`, and `cleanupNamedVolume` for `db-data`;
  `.container-compose-adapter` was absent afterwards and exact process-name
  checks found no `container-compose-adapter`, `vmexec`, or `vminit`
  processes.
- `.container-compose-adapter/` is now ignored in `.gitignore` so editor git
  integrations cannot stage transient runtime state.
- No private EMSI workload, registry login, prune, global cleanup, Docker Hub
  credential change, Keychain change, host DNS mutation, branch operation,
  commit, push, or parent monorepo pointer update was performed.

## Verification

Passed:

- `swift test` (`23` tests)
- `swift test` after the OCI defaults implementation (`23` tests)
- `git diff --check` after the OCI defaults implementation and dry-run refresh
- OCI-defaults backend-shaped `up`, `run`, and `down --volumes` dry-runs with
  JSONL evidence output and no `.container-compose-adapter` state created
- `swift build` after the OCI defaults implementation; the first sandboxed
  attempt hit `sandbox_apply: Operation not permitted`, and the escalated retry
  passed
- `scripts/sign-debug-runtime.sh` after the fresh build, confirming
  `com.apple.security.virtualization`
- Signed-binary `doctor`, reporting `virtualization entitlement: present`
- Approved OCI-defaults runtime `up` smoke attempted and blocked at VM creation
  by `VZErrorDomain Code=2` when run inside the sandboxed shell
- Approved `down --volumes` cleanup JSONL after the VM-creation blocker;
  `.container-compose-adapter` absent after cleanup and escalated filtered
  `ps` check found no lingering adapter/vmexec/vminit processes
- Host capability check (`kern.hv_support=1`, `Mac14,7` Apple M2, native
  arm64) contradicting the hardware diagnosis for `VZErrorDomain Code=2`
- Escalated re-run of the approved OCI-defaults runtime `up` smoke: VM
  creation and LinuxPod boot succeeded, then the DB managed process exited
  with status `1` before readiness; blocker JSONL recorded and validated with
  `jq -e`
- Approved escalated `down --volumes` cleanup with CLI-written execution
  JSONL; `.container-compose-adapter` absent after cleanup and an escalated
  `ps` command-name check found no lingering adapter/vmexec/vminit processes
- `swift test` after service log capture, block named volumes, per-container
  rootfs clones, and registration-ordering changes (`24` tests)
- Approved escalated Phase 4 backend-shaped runtime `up` smoke passed end to
  end with CLI-written execution JSONL validated by `jq -e`
- Approved escalated `down --volumes` cleanup after the passing smoke;
  `.container-compose-adapter` absent and exact process-name checks clean
- `scripts/sign-debug-runtime.sh`, with
  `com.apple.security.virtualization` present in the signed debug binary
- Signed-binary `doctor` for `--runtime linuxpod`, reporting
  `virtualization entitlement: present`
- Signed-binary backend-shaped `up` and `run` dry-runs without runtime mutation
- Backend-shaped `up`, `down`, `logs`, `status`, and `run` dry-runs with JSONL
  evidence output.
- Approved Phase 4 cleanup after the blocked runtime smoke; final
  `.container-compose-adapter` state directory is absent.
- Approved Phase 4 retry cleanup after the DB-exit blocker; final
  `.container-compose-adapter` state directory is absent and exact process-name
  checks found no `container-compose-adapter`, `vmexec`, or `vminit` processes.

Phase 5 gate: cleared. Service log capture, the volume-semantics fixes, the
registration-ordering fix, the passing signed runtime `up` smoke, and the
approved cleanup proof are all recorded above.

Still open as follow-ups (not Phase 5 blockers):

- A design or implementation for durable cross-command runtime state before
  claiming runtime `logs`, `status`, or standalone `run` behavior across
  separate CLI invocations.
- Sizing policy for named-volume block images (currently a fixed 1 GiB
  default per volume).

Not run:

- Phase 5 host footprint research
- Phase 6 backend-shaped benchmark repeats
- private EMSI workloads
- registry login
- prune or global cleanup
- Docker Hub credential changes
- Keychain changes
- host DNS mutation
- branch operation
- commit or push
- parent monorepo submodule pointer update
