# Stage 9B LinuxPod Hotplug Capability

**Date:** 2026-06-13
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

Stage 9B added a narrow LinuxPod lifecycle capability probe. This is not a
Compose feature, not a product benchmark, and not Docker/OrbStack viability
evidence. The probe asks whether `apple/containerization` `LinuxPod`
`addContainer` works after `pod.create()` in this runtime/package/config.

Implemented:

- `--stage9b-hotplug-probe` mode on `container-compose-phase6-benchmark`.
- Stage 9B JSONL schema and validator for five records:
  - pre-create registration control;
  - empty pod then post-create add;
  - non-empty pod then post-create add;
  - duplicate container ID guard;
  - final cleanup proof.
- A signed runtime probe that uses only adapter-owned project runtime
  directories under `.container-compose-adapter/cca-linuxpod-stage9b-*`.
- XCTest coverage for the schema, option parsing, validator, and checked-in
  Stage 9B evidence files.

## Runtime Evidence: 0.26.5 Baseline

Evidence file:
`docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T000136Z-stage9b-hotplug-capability.jsonl`

Runtime command:

```bash
.build/arm64-apple-macosx/debug/container-compose-phase6-benchmark --stage9b-hotplug-probe --evidence-jsonl docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T000136Z-stage9b-hotplug-capability.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION --project-prefix stage9b --run-label hotplug-capability --docker-hub-mirror mirror.gcr.io
```

The first sandboxed runtime attempt cleaned up but failed with
`VZErrorDomain Code=2` (`Virtualization is not available on this hardware`).
The same signed command was rerun outside the tool sandbox and passed the
Stage 9B evidence validator.

| Case | Result | Interpretation | Cleanup |
| --- | --- | --- | --- |
| Pre-create registration control | `pod.create()` succeeded and the initial container started. | Registering a container before `pod.create()` is valid. | `clean`, `leftoverPathsCount=0` |
| Empty pod then post-create add | `addContainer` failed with `invalidState: "pod must be initialized to add container"`. | Empty-pod post-create add is not a valid model. | `clean`, `leftoverPathsCount=0` |
| Non-empty pod then post-create add second container | Initial container registered and started, then second `addContainer` failed with the same `invalidState`. | Post-create hotplug is unavailable even when the pod was initialized with one container. | `clean`, `leftoverPathsCount=0` |
| Duplicate container ID guard | Duplicate add failed with `invalidArgument` and `duplicateContainerDetected=true`. | Duplicate state is detected separately from the hotplug failure. | `clean`, `leftoverPathsCount=0` |
| Cleanup proof | Final namespace scan found zero matching Stage 9B project leftovers. | Adapter-owned cleanup was clean. | `clean`, `leftoverPathsCount=0` |

## Runtime Evidence: 0.33.4 Retest

Evidence file:
`docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T002830Z-stage9b-hotplug-capability-0334-escalated.jsonl`

Runtime command:

```bash
.build/arm64-apple-macosx/debug/container-compose-phase6-benchmark --stage9b-hotplug-probe --project-prefix s9b0334 --run-label hp --docker-hub-mirror mirror.gcr.io --evidence-jsonl docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T002830Z-stage9b-hotplug-capability-0334-escalated.jsonl --approval-token I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION
```

This retest runs against `apple/containerization` `0.33.4` and
`ghcr.io/apple/containerization/vminit:0.33.4`. The runtime resource names were
shortened to avoid the `LinuxPod` 64-character ID limit introduced in the newer
package. The signed command was run outside the tool sandbox because
Virtualization.framework is blocked inside the sandbox.

| Case | Result | Interpretation | Cleanup |
| --- | --- | --- | --- |
| Pre-create registration control | `pod.create()` succeeded and the initial container started. | Registering a container before `pod.create()` is still valid on `0.33.4`. | `clean`, `leftoverPathsCount=0` |
| Empty pod then post-create add | `addContainer` failed with `unsupported: "hotplug not supported"`. | The public `0.33.4` package/config exposes the hotplug call path but does not install a `HotplugProvider`. | `clean`, `leftoverPathsCount=0` |
| Non-empty pod then post-create add second container | Initial container registered and started, then second `addContainer` failed with `unsupported: "hotplug not supported"`. | Post-create hotplug remains unavailable even when the pod was initialized with one container. | `clean`, `leftoverPathsCount=0` |
| Duplicate container ID guard | Duplicate add failed with `invalidArgument` and `duplicateContainerDetected=true`. | Duplicate state is detected separately from the hotplug-provider failure. | `clean`, `leftoverPathsCount=0` |
| Cleanup proof | Final namespace scan found zero matching Stage 9B project leftovers. | Adapter-owned cleanup was clean. | `clean`, `leftoverPathsCount=0` |

## Diagnostic Interpretation

Stage 9A F was not caused by marker-only reuse, missing duplicate detection, or
an empty-pod-only lifecycle mistake. The `0.26.5` baseline proved that
`LinuxPod.addContainer` was pre-create only in that pinned package. The `0.33.4`
retest changes the failure from `invalidState` to `unsupported`, but it does not
make post-create hotplug usable in this adapter configuration.

The inspected `0.33.4` package includes the `HotplugProvider` protocol and the
`LinuxPod.addContainer` post-create code path, but no default provider
implementation is installed by the public `VZVirtualMachineInstance`
configuration. Current Container Compose Adapter code must therefore still
treat post-create hotplug as unsupported until upstream provides or documents a
working provider setup.

## Verification

Pre-runtime gate:

- `swift test`
- `git diff --check`
- `git diff --cached --check`
- `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name stage9b-dry-run --timestamp 2026-06-13T00:00:00.000Z --evidence-jsonl /tmp/container-compose-stage9b-dry-run-validation.jsonl --store-root /tmp/container-compose-stage9b-backend-smoke --validate-evidence`
  - passed with `5` no-runtime dry-run surfaces and `12` capability checks.

Runtime gate:

- `swift build --product container-compose-phase6-benchmark`
- `scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark`
- signed Stage 9B runtime probe listed above
- Stage 9B evidence validator passed in the harness
- zero `.container-compose-adapter/cca-linuxpod-stage9b*` project leftovers
- `apple/containerization` package bumped to `0.33.4` and
  `vminit:0.33.4`
- signed Stage 9B `0.33.4` runtime retest listed above
- zero `.container-compose-adapter/cca-linuxpod-s9b0334*` project leftovers

Post-runtime gate:

- `swift test --filter RuntimeContractTests/testStage9B`
- `swift test --filter RuntimeContractTests/testStage9BRuntimeEvidenceFilesValidateHotplugCapabilityProbe`

Crash-recovery verification after the previous agent interruption:

- The existing Stage 9B evidence file was left unchanged and verified as a
  five-record JSONL file.
- `swift test --filter RuntimeContractTests/testStage9B`
- `swift run container-compose-stage5-backend-smoke --compose-file docs/evidence/fixtures/backend-shaped/compose.yaml --project-name stage9b-dry-run --timestamp 2026-06-13T00:00:00.000Z --evidence-jsonl /tmp/container-compose-stage9b-dry-run-validation.jsonl --store-root /tmp/container-compose-stage9b-backend-smoke --validate-evidence`
  - first hit the known SwiftPM `sandbox-exec` manifest failure in the tool
    sandbox, then passed outside the sandbox with `5` no-runtime dry-run
    surfaces and `12` capability checks.
- `swift test`
- `swift build --product container-compose-phase6-benchmark`
  - first hit the known SwiftPM `sandbox-exec` manifest failure in the tool
    sandbox, then passed outside the sandbox.
- `scripts/sign-debug-runtime.sh .build/arm64-apple-macosx/debug/container-compose-phase6-benchmark`
  - confirmed the debug binary carries the
    `com.apple.security.virtualization` entitlement.
- `find .container-compose-adapter -maxdepth 3 -type d -name 'cca-linuxpod-stage9b*' -print`
  - returned no leftovers.
- `rg '/Users/|marlonjd|/private/|dev_password|POSTGRES_PASSWORD|PGPASSWORD|Keychain|docker/config' docs/evidence/linuxpod-stage9b-hotplug-capability docs/evidence/linuxpod-stage9a-benchmark`
  - returned no leakage matches.
- `git diff --check`
- `git diff --cached --check`

## Next Todo

Do not implement warm service hotplug on the current LinuxPod API path. The next
runtime direction should be one of:

- fast pod recreate without hotplug;
- host-side daemon/session manager that owns a long-lived initialized lifecycle
  only if it can avoid post-create add;
- in-guest `cca-agent` only if it can create a real service lifecycle without
  relying on `LinuxPod.addContainer` after `pod.create()`;
- upstream issue documenting that `0.33.4` exposes the hotplug interfaces but
  the public VZ path returns `unsupported: "hotplug not supported"` without a
  `HotplugProvider`;
- rootfs COW/writable-layer investigation.

LinuxPod still misses the Docker/OrbStack viability gate. Stage 9B is negative
hotplug capability evidence, not product viability evidence.
