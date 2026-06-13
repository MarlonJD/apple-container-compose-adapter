# Stage 9A Diagnostic Slice

**Date:** 2026-06-13
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

Stage 9A added diagnosis-first metadata and validation around the unresolved
Stage 8 runtime questions. This slice does not implement a broad runtime
rewrite and does not claim LinuxPod product viability.

Implemented:

- Rootfs preparation breakdown schema for measured JSONL records, including
  image resolve/config timing, base rootfs cache lookup/hit state, unpack/copy
  timing, materialization strategy, copied bytes when available, source and
  destination paths, mount type/format/block-device status, work-avoidance
  status, and cache-claim type.
- Executor action metadata for the current rootfs path:
  - reusable base rootfs cache lookup;
  - base cache unpack when missing;
  - project rootfs copy from base cache;
  - per-container rootfs copy from the prepared project rootfs.
- Explicit block I/O attribution fields:
  - `blockIOAttribution=wholeRunOnly`;
  - `rootfsBlockIOAttribution=notMeasured`.
- Structured hotplug lifecycle diagnostics for F/G warm pod paths, including
  marker state, live pod state, reuse claim, add-container phase, hotplug
  attempt/success, failure phase/error, duplicate-container flag, and mutation
  state before failure.
- Runtime hotplug-provider introspection for F/G warm pod paths, including
  VM config extension count/types and whether the created
  `VZVirtualMachineInstance` has a `hotplugProvider` installed.
- G all-warm forced-recreate metadata. Because forced service recreate is not
  implemented in this slice, G is emitted as `noOpWarmReconcile` and
  `notProductViabilityEvidence`.
- Validator rules so:
  - marker-only pod reuse is never accepted as real reuse;
  - failed F can validate only as a structured known blocker with clean
    cleanup metadata;
  - measured records require rootfs breakdown and block-I/O attribution;
  - G must include forced service recreate metadata or explicit no-op
    non-viability metadata;
  - old Stage 8 signed files validate to additional known missing Stage 9A
    metadata blockers rather than being silently upgraded.

## Diagnostic Interpretation

The code path explains why the Stage 8 C rootfs-cache hit still spent
`28-35s` and kept block reads near `110MB`: a rootfs cache hit currently avoids
base rootfs unpack, but it does not avoid all rootfs work. The executor still
copies the cached base rootfs into the project runtime rootfs, then copies that
prepared rootfs into each per-container rootfs image before registration.

The F failure now has a narrower provider-wiring explanation on
`apple/containerization` `0.33.4`. The persistent-pod primer creates a pod, then
the measured `up` path tries to register containers against the already-created
pod. The attempted rootfs is an ext4 block mount
(`rootfsMountType=block`, `rootfsMountFormat=ext4`,
`rootfsMountIsBlock=true`), but runtime introspection records
`vmConfigExtensionCount=0`, `vmConfigExtensionTypes=[]`,
`hotplugProviderInstalled=false`, and `hotplugProviderStatus=missing`. The exact
failure is `unsupported: "hotplug not supported"`, matching the public
`VZVirtualMachineInstance.hotplug(_:, id:)` nil-provider branch rather than a
rootfs mount-format rejection. Stage 9A preserves that failure as structured
evidence instead of hiding it behind a full recreate or calling marker-only
state a hotplug success.

## Verification

Completed in this code/test slice:

- `swift test --filter RuntimeContractTests/testStage9A`
- `swift test --filter RuntimeContractTests/testStage8`
- `swift test`
- `swift build --product container-compose-phase6-benchmark`
- `scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark`
- signed Stage 9A `0.33.4` F/G retests listed below
- `swift test --filter RuntimeContractTests/testStage9ARuntimeEvidenceFilesValidateToRemainingKnownRuntimeBlockers`
- `rg '/Users/|marlonjd|/private/|dev_password|POSTGRES_PASSWORD|PGPASSWORD|Keychain|docker/config' docs/evidence/linuxpod-stage9a-benchmark/20260613T085301Z-stage9a0334meta-F-persistent-pod-hotplug.jsonl docs/evidence/linuxpod-stage9a-benchmark/20260613T085301Z-stage9a0334meta-G-all-warm-project-runtime.jsonl`
- `find .container-compose-adapter -maxdepth 3 -type d -name 'cca-linuxpod-stage9a0334meta*' -print`
- `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name stage9a-dry-run --timestamp 2026-06-13T00:00:00.000Z --evidence-jsonl /tmp/container-compose-stage9a-dry-run-validation.jsonl --store-root /tmp/container-compose-stage9a-backend-smoke --validate-evidence`
  - passed with `5` no-runtime dry-run surfaces and `12` capability checks
- `git diff --check`

Completed after explicit runtime approval:

- `swift build --product container-compose-phase6-benchmark`
- `scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark`
- signed F/G runtime runs using
  `I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION`,
  `--compose-file docs/evidence/fixtures/backend-shaped/compose.yaml`, and
  `--docker-hub-mirror mirror.gcr.io`

Runtime evidence directory:
`docs/evidence/linuxpod-stage9a-benchmark/`

| Mode | Evidence | Measured / failed | Up seconds | Rootfs seconds | Healthcheck seconds | Block read bytes | Block write bytes | Stage 9A diagnosis | Cleanup |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| F persistent pod/hotplug | `20260612T233739Z-stage9a-F-persistent-pod-hotplug.jsonl` | `0 / 1` | n/a | n/a | n/a | n/a | n/a | `hotplugUnsupported=true`, `failurePhase=addContainer`, `podReuseClaim=liveObject` | `clean` |
| G all-warm project runtime | `20260612T233739Z-stage9a-G-all-warm-project-runtime.jsonl` | `1 / 0` | `0.115` | `0.013` | `0.100` | `111170560` | `53596160` | `noOpWarmReconcile=true`, `notProductViabilityEvidence=true` | `clean` |

## 0.33.4 F/G Provider-introspection Retest

After bumping `apple/containerization` and `vminit` to `0.33.4`, F/G were
rerun with signed runtime approval and `--project-prefix stage9a0334meta`.

| Mode | Evidence | Measured / failed | Up seconds | Rootfs seconds | Healthcheck seconds | Block read bytes | Block write bytes | Stage 9A diagnosis | Cleanup |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| F persistent pod/hotplug | `20260613T085301Z-stage9a0334meta-F-persistent-pod-hotplug.jsonl` | `0 / 1` | n/a | n/a | n/a | n/a | n/a | `unsupported: "hotplug not supported"`, `failurePhase=addContainer`, `hotplugProviderInstalled=false`, `vmConfigExtensionCount=0`, rootfs `block/ext4/isBlock=true` | `clean` |
| G all-warm project runtime | `20260613T085301Z-stage9a0334meta-G-all-warm-project-runtime.jsonl` | `1 / 0` | `0.118` | `0.011` | `0.106` | `111170560` | `53579776` | `noOpWarmReconcile=true`, `notProductViabilityEvidence=true`, `hotplugProviderInstalled=false` | `clean` |

The retest did not make F viable. It changed the F failure from the old
`invalidState` path to the same public `0.33.4` hotplug-provider failure seen
in Stage 9B: `unsupported: "hotplug not supported"`. The final
provider-introspection evidence shows the cause is not an ext4/block rootfs
shape mismatch; the VZ-backed LinuxPod path simply has no installed
`hotplugProvider` and no configured `VZInstanceExtension`. G remained a
control-plane no-op warm reconcile, not product viability evidence.

A draft upstream issue package is captured in
[Containerization Hotplug Provider Upstream Issue Draft](2026-06-13-containerization-hotplug-upstream-issue-draft.md).

Zero-leftover inspection after both runs found no adapter-owned
`cca-linuxpod-stage9a0334meta*` project runtime directories under
`.container-compose-adapter/`.

The checked-in Stage 9A rootfs breakdown evidence redacts the local repository
root as `<repo>` while preserving the adapter-state-relative source and
destination path suffixes needed for diagnosis.

## Next Todo

Choose the next runtime direction from the signed Stage 9A evidence:

- close LinuxPod post-create hotplug as unsupported by the current API path;
- implement a real forced service recreate strategy before giving G any product
  viability weight;
- pursue a smaller rootfs optimization such as APFS clone or read-only base
  rootfs plus writable layer.

Do not count G as product viability evidence until it performs a forced
service recreate or remains explicitly marked as no-op/non-viability evidence.
