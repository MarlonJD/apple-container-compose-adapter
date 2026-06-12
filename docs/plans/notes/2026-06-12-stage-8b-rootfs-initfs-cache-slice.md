# Stage 8B Rootfs And Initfs Cache Slice

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

Stage 8B implemented the first runtime optimization slice without adding any
new backend family:

- `LinuxPodStateStore` now separates per-project runtime rootfs/initfs copies
  from reusable adapter cache paths.
- LinuxPod dry-runs report reusable rootfs cache and initfs cache paths plus
  hit/miss metadata.
- Runtime execution events carry rootfs/initfs cache metadata across the narrow
  executor boundary.
- The LinuxPod executor now prepares initfs once into the adapter cache and
  copies it into each project runtime before VM creation.
- The LinuxPod executor now prepares image rootfs once into the adapter cache
  and copies it into each project runtime before per-container APFS clones.
- Benchmark lifecycle classification now reads rootfs/initfs hit state from the
  reusable cache paths, not from per-run runtime copies.
- Dry-run/runtime evidence cache events include the reusable rootfs cache path.

No Docker-compatible, Colima, Podman, Lima, Rancher Desktop, Docker Desktop,
OrbStack, or container-compose backend was added. No registry credentials,
Keychain entries, host DNS, global caches, or global prune behavior were
mutated.

## Verification

Completed without LinuxPod runtime mutation:

- `swift test --filter LinuxPodBackendTests/testDryRunPlansReusableRootfsAndInitfsCacheState`
- `swift test --filter LinuxPodBackendTests/testApprovedUpExecutesProjectLifecycleThroughRuntimeExecutor`
- `swift test`
- `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name backend-shaped --timestamp 2026-06-12T17:25:00.000Z --evidence-jsonl /tmp/container-compose-stage8b-dry-run-validation.jsonl --store-root /tmp/container-compose-stage8b-backend-smoke --validate-evidence`
- `git diff --check`

Runtime smoke for C/D/G lifecycle measurement is still an explicit approval
gate. The code is ready for signed runtime validation, but this note does not
claim rootfs/initfs speedup numbers.

## Next Todo

With explicit runtime approval, run the signed Stage 8 evidence path for the
rootfs-cache and initfs-cache modes, validate JSONL with
`Stage8BenchmarkEvidenceValidator`, and prove cleanup has zero adapter-owned
project runtime leftovers.
