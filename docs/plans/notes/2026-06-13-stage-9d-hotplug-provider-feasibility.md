# Stage 9D Hotplug Provider Feasibility

**Status:** `note-closed`
**Owner:** `tools/apple-container-compose-adapter`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Why This Exists

Stage 9D exists because Stage 9B showed that `apple/containerization` `0.33.4`
reaches the post-create LinuxPod hotplug path but the default VZ-backed VM has
no installed provider:

- `vmConfigExtensionCount=0`
- `hotplugProviderInstalled=false`
- failure message: `"hotplug not supported"`

PR #740 added interfaces for hotplug. It did not prove that the default public
VZ LinuxPod path installs a provider, and it did not prove that block/ext4
container rootfs hotplug works for post-create `LinuxPod.addContainer`.

## Diagnostic Scope

This spike tests whether Container Compose Adapter can install a local
public-extension-based `VZInstanceExtension` and `HotplugProvider` without forking
`apple/containerization`.

The provider is diagnostic-only. It is installed only by the
`--stage9d-hotplug-provider-probe` harness flag and must not be wired into the
normal Compose/LinuxPod runtime path.

## Product Boundary

This must not be treated as product behavior unless the second container actually starts
after post-create `LinuxPod.addContainer`.

If the provider only receives the call but cannot attach the block/ext4 rootfs
using public APIs safely, the product path remains fast pod recreate + rootfs copy avoidance,
APFS clone/COW or writable-layer investigation, and warm ext4 volumes.

No fork decision is made in this task.

No host memory savings claim is made.

No Docker/OrbStack viability claim is made.

## Evidence Expectations

Stage 9D evidence must distinguish:

- provider installation only;
- provider receiving the post-create hotplug request;
- real second-container hotplug, counted only if the second container starts.

The validator rejects fake `AttachedFilesystem` success, unsafe product
availability claims, dirty cleanup, and missing host-port/load-window
`notMeasured` markers.

## Current Implementation

The Stage 9D harness adds `--stage9d-hotplug-provider-probe` and records a
`stage9dHotplugProviderProbe` JSONL record. The local extension installs
`CCAHotplugFeasibilityProvider` only for the diagnostic probe. The normal
Compose/LinuxPod path keeps its provider list empty unless this flag is used.

The probe also uses a Stage 9D-specific runtime naming helper so the approved
human run label (`stage9d-hotplug-provider-feasibility`) does not exceed the
LinuxPod 64-character pod/container ID limit.

## Runtime Evidence

- Final evidence: `docs/evidence/linuxpod-stage9d-hotplug-provider/20260613T093056Z-stage9d-hotplug-provider-feasibility.jsonl`
- Harness fix evidence: `docs/evidence/linuxpod-stage9d-hotplug-provider/20260613T092721Z-stage9d-hotplug-provider-feasibility.jsonl` failed before provider reachability because the first Stage 9D runtime resource name exceeded the LinuxPod ID limit (`66` > `64`).
- `containerizationVersion`: `0.33.4`
- `containerizationRevision`: `9275f365dd555c8f072e7d250d809f5eb7bdd746`
- `provider.extensionInstalled=true`
- `provider.linuxPodConfigExtensionCount=1`
- `provider.vmConfigExtensionCount=1`
- `provider.providerDidCreateCalled=true`
- `provider.hotplugProviderInstalled=true`
- `provider.providerHotplugCalled=true`
- `hotplug.postCreateAddContainerReachedProvider=true`
- `rootfs.rootfsAttachStrategy=vzUSBMassStorage`
- `cleanup.attachedDeviceDetached=true`
- `cleanup.cleanupResult=clean`
- `cleanup.leftoverPathsCount=0`

## Decision

Stage 9D proved that Container Compose Adapter can install a custom public
`VZInstanceExtension`/`HotplugProvider` without forking `apple/containerization`,
and that post-create `LinuxPod.addContainer` reaches that provider.

Stage 9D did not prove product hotplug. The public USB mass-storage attach
succeeded, but the probe could not produce a safe public mapping to the
LinuxPod `AttachedFilesystem` guest block-device path expected for an ext4 rootfs:

`unsupported: "public USB mass-storage attach succeeded, but no safe public mapping to LinuxPod's expected guest block device path was available"`

The exact blocker is `unsupportedRootfsBlockHotplug`. The second container did
not start, `productHotplugAvailable=false`, and `productShouldDependOnHotplug=false`.

The next recommended path is the upstream issue/draft. Product work should
continue on fast pod recreate + rootfs copy avoidance, APFS clone/COW or
writable-layer investigation, and warm ext4 volumes rather than depending on
LinuxPod post-create block-rootfs hotplug.
