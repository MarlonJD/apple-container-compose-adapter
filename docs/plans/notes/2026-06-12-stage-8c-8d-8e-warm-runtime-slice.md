# Stage 8C-8E Warm Runtime Slice

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

Stage 8C through 8E completed the no-runtime-mutation code and evidence
surface needed to distinguish the remaining warm lifecycle modes:

- Stage 8C: named volumes now expose reusable `volume.ext4` paths and
  create/reuse metadata so warm preserved volume runs can be identified.
- Stage 8D: project runtime metadata now exposes a pod marker, pod lifecycle,
  and hotplug/reuse policy; executor state no longer overwrites an already
  initialized project runtime in the same process.
- Stage 8E: benchmark policy now uses a shared project name for warm-volume,
  persistent-pod, and all-warm modes, preserves the right state between
  intermediate iterations, and requires a final full cleanup.
- Stage 8E: Stage 8 JSONL validation now accepts intermediate warm-reuse
  cleanup results only when the same evidence set also contains a final clean
  cleanup proof.
- Runtime action results now carry per-action `durationSeconds` metadata so
  Stage 8 benchmark records can preserve rootfs, initfs, volume, pod,
  container-start, and healthcheck duration slots.
- Benchmark records now snapshot project data footprint before cleanup.

No Docker-compatible, Colima, Podman, Lima, Rancher Desktop, Docker Desktop,
OrbStack, or container-compose backend was added. No registry credentials,
Keychain entries, host DNS, global caches, or global prune behavior were
mutated.

## Verification

Completed without LinuxPod runtime mutation:

- `swift test --filter LinuxPodBackendTests/testDryRunPlansWarmPreservedVolumeReuseMetadata`
- `swift test --filter LinuxPodBackendTests/testDryRunPlansPersistentPodHotplugMetadata`
- `swift test --filter RuntimeContractTests/testStage8AllWarmBenchmarkPolicyReusesProjectUntilFinalCleanup`
- `swift test --filter RuntimeContractTests/testStage8BenchmarkEvidenceValidatorAcceptsWarmReuseWithFinalCleanCleanup`
- `swift test`
- `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name backend-shaped --timestamp 2026-06-12T17:42:00.000Z --evidence-jsonl /tmp/container-compose-stage8cde-dry-run-validation.jsonl --store-root /tmp/container-compose-stage8cde-backend-smoke --validate-evidence`
- `git diff --check`

Runtime speedup evidence for E/F/G remains an explicit approval gate. This
note does not claim persistent pod hotplug works on the host or that all-warm
runtime performance is acceptable.

## Next Todo

With explicit runtime approval, run the signed Stage 8 E/F/G evidence path,
validate JSONL with `Stage8BenchmarkEvidenceValidator`, and prove final cleanup
has zero adapter-owned project runtime leftovers.
