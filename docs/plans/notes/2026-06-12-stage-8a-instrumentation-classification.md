# Stage 8A Instrumentation And Lifecycle Classification

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

Stage 8A added the no-runtime instrumentation layer needed before another
LinuxPod runtime experiment:

- Lifecycle mode metadata now distinguishes the Stage 8 matrix explicitly:
  `A` cold runtime, `B` image-store-seeded fresh runtime, `C` rootfs-cache hit
  runtime, `D` initfs-cache hit runtime, `E` warm preserved volume, `F`
  persistent pod/hotplug, and `G` all-warm project runtime.
- Legacy Stage 6 lifecycle labels remain available for older evidence, while
  new JSONL can carry `lifecycleMode` and `lifecycleModeID`.
- Benchmark records can preserve rootfs prep, initfs prep, volume
  create/reuse, pod create/reuse, container start, healthcheck duration,
  healthcheck attempts, process RSS, data footprint, host-port TTFB, load
  window, guest cgroup, block I/O, and cleanup result fields.
- Missing host-port and load-window measurements remain explicit
  `notMeasured` metadata, not zero-valued measurements.
- `Stage8BenchmarkEvidenceValidator` checks lifecycle mode/cache consistency,
  required metric slots, not-measured markers, and zero adapter-owned project
  runtime leftovers.
- `container-compose-phase6-benchmark` remains backward compatible but now
  accepts `--lifecycle-mode` for the Stage 8 A-G modes.

No runtime mutation was performed for Stage 8A.

## Verification

- `swift test --filter RuntimeContractTests/testStage8`
- Baseline before Stage 8A editing: `swift test` and `git diff --check`

## Next Todo

Stage 8B should implement the smallest rootfs-cache and initfs-cache runtime
optimization slice, then rerun focused and full verification. Runtime execution
still requires the explicit signed-runtime approval path.
