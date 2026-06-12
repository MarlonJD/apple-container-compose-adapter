# LinuxPod Phase 3 Dry-run Gate Evidence

**Date:** 2026-06-12
**Linked plan:** [LinuxPod Compose Runtime Backend Implementation Plan](../2026-06-12-linuxpod-compose-runtime-backend-plan.md)
**Decision:** `runtime-smoke-passed-after-local-signing`
**Runtime mutation:** Approved public-image smoke only.

## Decision

Phase 3 reached the runtime approval gate. The adapter can render a
LinuxPod public-image dry-run plan with adapter-owned `cca-linuxpod-*` state,
rootfs cache evidence, named volume mapping, bind mount validation, redacted
environment output, and lifecycle actions. The project-scoped
`apple/containerization` LinuxPod executor is implemented behind the backend
boundary and approval token.

The first approved runtime attempt showed that `swift run` does not carry the
`com.apple.security.virtualization` entitlement required by
Virtualization.framework. The fix is to build the CLI, ad-hoc sign the debug
executable with `signing/container-compose-adapter.entitlements`, verify the
entitlement with `codesign -d --entitlements :-`, and run the signed executable
directly.

After signing, the approved public-image runtime smoke completed and cleanup
was verified.

## Dry-run Evidence

Up command:

```bash
swift run container-compose-adapter --runtime linuxpod --dry-run --project-name phase3-public-smoke --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T013700-phase3-public-smoke-dry-run.jsonl up
```

Cleanup command:

```bash
swift run container-compose-adapter --runtime linuxpod --dry-run --project-name phase3-public-smoke --volumes --format text --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T014200-phase3-public-smoke-down-dry-run.jsonl down
```

Up evidence:

- JSONL: [Phase 3 public smoke dry-run](../../evidence/linuxpod-compose-runtime/20260612T013700-phase3-public-smoke-dry-run.jsonl)
- Record count: `1`
- Schema: `container-compose-adapter/linuxpod-dry-run/v1`
- Status: `planned-dry-run-no-runtime-mutation`
- Project resource: `cca-linuxpod-phase3-public-smoke`
- Rootfs image: `mirror.gcr.io/library/nginx:alpine`
- Rootfs cache: `miss`
- Rootfs state:
  `.container-compose-adapter/cca-linuxpod-phase3-public-smoke/runtime/rootfs/mirror.gcr.io_library_nginx_alpine.ext4`
- Named volume: `web-cache`
- Bind mount validation: `docs/evidence/fixtures -> /usr/share/nginx/html`
- Service command: `/docker-entrypoint.sh nginx -g daemon off;`
- Secret redaction: `SESSION_TOKEN=<redacted>`
- Cleanup proof: `runtimeMutation=not-run`, `globalCleanup=not-run`,
  `ownedPrefix=cca-linuxpod-`

Cleanup evidence:

- JSONL: [Phase 3 public smoke cleanup dry-run](../../evidence/linuxpod-compose-runtime/20260612T014200-phase3-public-smoke-down-dry-run.jsonl)
- Record count: `1`
- Status: `planned-dry-run-no-runtime-mutation`
- Project resource: `cca-linuxpod-phase3-public-smoke`
- Planned stop/delete state:
  `.container-compose-adapter/cca-linuxpod-phase3-public-smoke/runtime`
- Planned named-volume cleanup:
  `.container-compose-adapter/cca-linuxpod-phase3-public-smoke/volumes/web-cache`
- Cleanup proof: `runtimeMutation=not-run`, `globalCleanup=not-run`,
  `volumeCleanup=planned-only`, `ownedPrefix=cca-linuxpod-`

Planned mutating actions if runtime approval is later granted:

1. Create or reuse project LinuxPod:
   `cca-linuxpod-phase3-public-smoke`.
2. Prepare the public-image rootfs under adapter-owned runtime state.
3. Map the Compose named volume `web-cache` to adapter-owned state.
4. Add service container `cca-linuxpod-phase3-public-smoke-web`.
5. Start service container `cca-linuxpod-phase3-public-smoke-web`.
6. Stop only project LinuxPod `cca-linuxpod-phase3-public-smoke`.
7. Delete only adapter-owned project runtime state.
8. Delete adapter-owned named volume `web-cache` because cleanup verification
   will use `down --volumes`.

## Approved Runtime Attempts

Blocked `swift run` command:

```bash
swift run container-compose-adapter --runtime linuxpod --project-name phase3-public-smoke --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T014700-phase3-public-smoke-runtime-up.jsonl up
```

Result:

- Status: `blocked-runtime-missing-virtualization-entitlement`
- Exit code: `64`
- Blocking message:
  `Process lacks com.apple.security.virtualization entitlement required by Virtualization.framework.`
- Blocker JSONL:
  [Phase 3 runtime smoke blocker](../../evidence/linuxpod-compose-runtime/20260612T014700-phase3-public-smoke-runtime-up-blocked.jsonl)
- Requested success evidence path was not written because the command failed
  before successful execution:
  `docs/evidence/linuxpod-compose-runtime/20260612T014700-phase3-public-smoke-runtime-up.jsonl`
- `.container-compose-adapter` state directory: absent after the attempt.

No runtime mutation was performed in the blocked attempt. The executor performs
entitlement and kernel preflight before creating adapter-owned runtime state, so
this failure happened before pod, rootfs, or volume state creation.

Signing fix:

```bash
codesign --force --sign - --entitlements signing/container-compose-adapter.entitlements .build/arm64-apple-macosx/debug/container-compose-adapter
codesign -d --entitlements :- .build/arm64-apple-macosx/debug/container-compose-adapter
```

Signed runtime `up` command:

```bash
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --project-name phase3-public-smoke --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T015200-phase3-public-smoke-runtime-up.jsonl up
```

Signed runtime cleanup commands:

```bash
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --project-name phase3-public-smoke --volumes --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T015300-phase3-public-smoke-runtime-down.jsonl down
.build/arm64-apple-macosx/debug/container-compose-adapter --runtime linuxpod --project-name phase3-public-smoke --volumes --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION --evidence-jsonl docs/evidence/linuxpod-compose-runtime/20260612T015500-phase3-public-smoke-runtime-down-cleanup.jsonl down
```

Runtime evidence:

- Up JSONL:
  [Phase 3 runtime up](../../evidence/linuxpod-compose-runtime/20260612T015200-phase3-public-smoke-runtime-up.jsonl)
- Cleanup JSONL:
  [Phase 3 runtime cleanup](../../evidence/linuxpod-compose-runtime/20260612T015500-phase3-public-smoke-runtime-down-cleanup.jsonl)
- Status: `executed`
- Project resource: `cca-linuxpod-phase3-public-smoke`
- Runtime state after final cleanup: `.container-compose-adapter` absent.
- Process check: no visible `cca-linuxpod-phase3-public-smoke` process after
  cleanup; only the verification `rg` process matched the search.

The first signed cleanup left an empty project directory. The cleanup helper was
then tightened to remove empty project and adapter root directories, covered by
`testStateStoreRemovesEmptyProjectDirectoriesAfterVolumeCleanup`, and cleanup
was rerun successfully.

## Verification

Passed:

- `swift test`
- `swift run container-compose-adapter --runtime linuxpod --dry-run ... up`
  with JSONL evidence output
- `swift run container-compose-adapter --runtime linuxpod --dry-run
  --volumes ... down` with JSONL evidence output
- approved `swift run container-compose-adapter --runtime linuxpod ... up`
  attempted and blocked at entitlement preflight before runtime state creation
- signed `.build/arm64-apple-macosx/debug/container-compose-adapter --runtime
  linuxpod ... up` executed successfully
- signed `.build/arm64-apple-macosx/debug/container-compose-adapter --runtime
  linuxpod --volumes ... down` cleanup executed successfully
- `git diff --check`
- trailing-whitespace scan over touched tracked and untracked source, test,
  plan, note, README, and evidence files

Implemented before the approval gate:

- Runtime-neutral `RuntimeBackend` contract and `NoopDryRunBackend`
- `LinuxPodBackend` explicit runtime flag, approval gate, and dry-run rendering
- Project-scoped `ContainerizationLinuxPodRuntimeExecutor` using pinned
  `apple/containerization` `0.26.5`
- Public-image rootfs preparation, adapter-owned named volume directories, bind
  mount validation, service add/start, service-started readiness no-op, runtime
  stop, runtime state delete, and explicit `down --volumes` named-volume cleanup
- Entitlement and kernel preflight before runtime state is created

Ready before Phase 4:

- Continue with Phase 4 dry-run and test implementation for multi-service
  semantics before any further runtime mutation.

Skipped:

- private EMSI workloads
- registry login
- prune or global cleanup
- Docker Hub credential changes
- Keychain changes
- host DNS mutation

Not run:

- branch operation
- commit or push
- parent monorepo submodule pointer update
