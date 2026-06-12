# Stage 8C-8E Warm Runtime Slice

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

Stage 8C through 8E completed the code, no-runtime validation, and one
approved signed runtime pass needed to distinguish the warm lifecycle modes:

- Stage 8C: named volumes expose reusable `volume.ext4` paths and create/reuse
  metadata so warm preserved volume runs can be identified.
- Stage 8D: project runtime metadata exposes pod lifecycle and hotplug/reuse
  policy, and warm pod reuse evidence is accepted only when the live executor
  state confirms that the pod existed before the measured run.
- Stage 8E: benchmark policy uses a shared project name for warm-volume,
  persistent-pod, and all-warm modes, preserves the right state for warm
  measurement, primes warm state outside the measured iteration, and requires
  a final full cleanup.
- Stage 8 JSONL validation accepts intermediate E/F/G warm-reuse records only
  when the same evidence set contains final clean cleanup proof.
- Runtime action results carry per-action `durationSeconds` metadata so Stage
  8 records preserve startup/readiness, rootfs, initfs, volume, pod,
  container-start, and healthcheck duration slots.
- Benchmark records snapshot project data footprint before cleanup, preserve
  guest cgroup-current and block I/O metrics when the run reaches measurement,
  and mark missing host-port and load-window metrics as `notMeasured`.

No Docker-compatible, Colima, Podman, Lima, Rancher Desktop, Docker Desktop,
OrbStack, or container-compose backend was added. No registry credentials,
Keychain entries, host DNS, global caches, or global prune behavior were
mutated. No host memory savings claim is made.

## Runtime Evidence

Evidence directory:
`docs/evidence/linuxpod-stage8-benchmark/`

| Mode | Evidence | Measured / failed | Up seconds | Rootfs seconds | Initfs seconds | Volume seconds | Pod seconds | Container seconds | Healthcheck seconds | Block read bytes | Block write bytes | Cleanup |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| A cold runtime | `20260612T180000Z-stage8-A-cold-runtime.jsonl` | `1 / 0` | `78.476` | `70.004` | `5.249` | `0.006482` | `5.249` | `0.711` | `2.503` | `110543872` | `53583872` | `clean` |
| B image-store-seeded fresh runtime | `20260612T180000Z-stage8-B-image-store-seeded-fresh-runtime.jsonl` | `1 / 0` | `38.702` | `35.204` | `0.321` | `0.006542` | `0.321` | `0.656` | `2.512` | `110543872` | `53526528` | `clean` |
| C rootfs-cache hit runtime | `20260612T180000Z-stage8-C-rootfs-cache-hit-runtime.jsonl` | `1 / 0` | `37.317` | `28.424` | `5.243` | `0.008127` | `5.243` | `1.036` | `2.598` | `111170560` | `53485568` | `clean` |
| D initfs-cache hit runtime | `20260612T180000Z-stage8-D-initfs-cache-hit-runtime.jsonl` | `1 / 0` | `70.200` | `63.635` | `3.351` | `0.006707` | `3.351` | `0.785` | `2.409` | `110543872` | `53530624` | `clean` |
| E warm preserved volume | `20260612T180000Z-stage8-E-warm-preserved-volume.jsonl` | `1 / 0` | `31.728` | `25.344` | `3.327` | `0.000089` | `3.327` | `0.569` | `2.484` | `81466368` | `1052672` | `clean` |
| F persistent pod/hotplug | `20260612T180000Z-stage8-F-persistent-pod-hotplug.jsonl` | `0 / 1` | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | `clean` after failure |
| G all-warm project runtime | `20260612T180000Z-stage8-G-all-warm-project-runtime.jsonl` | `1 / 0` | `0.108` | `0.015` | `0.000023` | `0.000060` | `0.000023` | `0.000076` | `0.092` | `110543872` | `53555200` | `clean` |

F failed before measurement with
`invalidState: "pod must be initialized to add container"` even though the
recorded warm-reuse metadata says `podExistedBeforeRun=true` and
`podReuseVerificationStatus=liveExecutorState`. That makes the hotplug
hypothesis unproven.

Host-port TTFB and completed-work-per-load-window are `notMeasured` in every
record, not zero. Guest cgroup current and block I/O are recorded for measured
modes, but cgroup peak is not represented in the current schema and process
RSS is not emitted by the LinuxPod statistics path. The strict runtime JSONL
validation therefore records known blockers rather than a pass:
successful A/B/C/D/E/G records validate to `stage8-process-rss-missing`, and F
validates to the expected missing measurement metrics after its hotplug
failure.

## Interpretation

- Rootfs cache hit reduced rootfs prep from A `70.004s` and B `35.204s` to C
  `28.424s`.
- Initfs cache hit reduced initfs/pod prep from A `5.249s` to D `3.351s`, but
  D remained close to cold overall because rootfs stayed expensive.
- Warm preserved volume reduced volume create/reuse from B `0.006542s` to E
  `0.000089s` and cut block writes from B `53526528` bytes to E `1052672`
  bytes. Healthcheck duration did not materially improve: B `2.512s` versus E
  `2.484s`.
- Persistent pod/hotplug did not avoid pod-create cost because F failed before
  measurement.
- All-warm G reduced same-process up/readiness versus B from `38.702s` to
  `0.108s`, but this is not enough for a Docker/OrbStack viability pass while
  F fails and required RSS/peak/host-port/load-window evidence is incomplete.

## Verification

Completed before runtime mutation:

- `swift test --filter LinuxPodBackendTests/testDryRunPlansWarmPreservedVolumeReuseMetadata`
- `swift test --filter LinuxPodBackendTests/testDryRunPlansPersistentPodHotplugMetadata`
- `swift test --filter RuntimeContractTests/testStage8AllWarmBenchmarkPolicyReusesProjectUntilFinalCleanup`
- `swift test --filter RuntimeContractTests/testStage8BenchmarkEvidenceValidatorAcceptsWarmReuseWithFinalCleanCleanup`
- `swift test`
- `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name backend-shaped --timestamp 2026-06-12T17:42:00.000Z --evidence-jsonl /tmp/container-compose-stage8cde-dry-run-validation.jsonl --store-root /tmp/container-compose-stage8cde-backend-smoke --validate-evidence`
- `git diff --check`

Completed after runtime approval:

- `swift build --product container-compose-phase6-benchmark`
- `scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark`
- signed A/B/C/D/E/F/G runtime runs using
  `I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION` and
  `--docker-hub-mirror mirror.gcr.io`
- `swift test --filter RuntimeContractTests/testStage8`
- `swift test --filter RuntimeContractTests/testStage8RuntimeEvidenceFilesValidateToKnownRuntimeBlockers`
- zero-leftover inspection:
  `find /private/tmp/cca-stage8-runtime-{A,B,C,D,E,F,G} -path '*/.container-compose-adapter/cca-linuxpod-*' -print`
  returned no adapter-owned project runtime leftovers.

## Next Todo

Do not treat Stage 8 as a viability pass. The next concrete todo is to decide
whether to implement a real LinuxPod hotplug path or close F as unsupported,
and separately add truthful RSS/cgroup-peak evidence or explicit schema-level
`notMeasured` status for those missing metrics before any further replacement
claim.
