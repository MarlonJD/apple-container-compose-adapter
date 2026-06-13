# Containerization Hotplug Provider Upstream Issue

**Date:** 2026-06-13
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-open`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)
**Upstream issue:** [apple/containerization#767](https://github.com/apple/containerization/issues/767)

## Summary

`apple/containerization` `0.33.4` exposes the post-create `LinuxPod.addContainer`
path and `VZVirtualMachineInstance.hotplugProvider`, but the public package
does not appear to provide or install a `HotplugProvider` implementation by
default. A signed `LinuxPod` probe that reuses a live pod and attempts
post-create `addContainer` fails with:

```text
unsupported: "hotplug not supported"
```

Runtime introspection captured by the adapter shows:

- `containerizationVersion=0.33.4`
- active checkout tag: `0.33.4`
- active checkout commit: `9275f365dd555c8f072e7d250d809f5eb7bdd746`
- `vmConfigExtensionCount=0`
- `vmConfigExtensionTypes=[]`
- `hotplugProviderInstalled=false`
- `hotplugProviderStatus=missing`
- attempted container rootfs: `rootfsMountType=block`,
  `rootfsMountFormat=ext4`, `rootfsMountIsBlock=true`

The public source path for this failure is
`VZVirtualMachineInstance.hotplug(_:, id:)`, which throws
`ContainerizationError(.unsupported, message: "hotplug not supported")` when
`hotplugProvider` is `nil`.

## Local Evidence

Signed runtime evidence:

- F persistent pod hotplug:
  `docs/evidence/linuxpod-stage9a-benchmark/20260613T085301Z-stage9a0334meta-F-persistent-pod-hotplug.jsonl`
- G all-warm control:
  `docs/evidence/linuxpod-stage9a-benchmark/20260613T085301Z-stage9a0334meta-G-all-warm-project-runtime.jsonl`
- Stage 9B capability probe:
  `docs/evidence/linuxpod-stage9b-hotplug-capability/20260613T002830Z-stage9b-hotplug-capability-0334-escalated.jsonl`

Local source inspection:

- `VMConfiguration` and `LinuxPod.Configuration` both expose
  `extensions: [any Sendable]`.
- `VZVirtualMachineInstance.Configuration` calls `configureVZ`, `didCreate`,
  and `willStop` on values conforming to `VZInstanceExtension`.
- `VZVirtualMachineManager` copies `vmConfig.extensions` into the instance
  configuration.
- The public `0.33.4` checkout has `HotplugProvider` and `VZInstanceExtension`
  protocols, but no conforming provider implementation or public extension
  factory was found by source search.

GitHub API checks on 2026-06-13:

- Search for `repo:apple/containerization "hotplug not supported"` returned
  `total_count=0`.
- Search for `repo:apple/containerization HotplugProvider LinuxPod` returned
  `total_count=0`.
- PR [apple/containerization#740](https://github.com/apple/containerization/pull/740)
  is merged and titled `add hotplug interfaces for vmms`.
- Opened upstream issue
  [apple/containerization#767](https://github.com/apple/containerization/issues/767)
  using the local `gh` CLI as `MarlonJD`, not through the ChatGPT Codex
  Connector.

## Draft Issue

Title:

```text
LinuxPod post-create addContainer fails with "hotplug not supported" on 0.33.4; is there a public HotplugProvider extension to enable?
```

Body:

```markdown
### Summary

I'm testing `LinuxPod` post-create `addContainer` on `apple/containerization`
`0.33.4` after PR #740 added hotplug interfaces. The API surface exposes
`LinuxPod.Configuration.extensions`, `VMConfiguration.extensions`,
`VZInstanceExtension`, and `VZVirtualMachineInstance.hotplugProvider`, but I
cannot find a public extension/provider implementation to install. A live-pod
post-create `addContainer` attempt fails with:

```text
unsupported: "hotplug not supported"
```

### Environment

- Package: `apple/containerization`
- Version: `0.33.4`
- Checkout commit: `9275f365dd555c8f072e7d250d809f5eb7bdd746`
- macOS: 26.5.1
- Host architecture: arm64
- VM init image: `ghcr.io/apple/containerization/vminit:0.33.4`

### What I tried

1. Create a `LinuxPod` with `VZVirtualMachineManager`.
2. Add/register an initial container before `pod.create()`.
3. Start the initial container successfully.
4. Reuse the same live pod object.
5. Attempt `pod.addContainer(...)` after `pod.create()` using an ext4 block
   rootfs mount.

The attempted post-create rootfs is a block mount:

```text
rootfsMountType=block
rootfsMountFormat=ext4
rootfsMountIsBlock=true
```

Runtime introspection around VM creation shows:

```text
vmConfigExtensionCount=0
vmConfigExtensionTypes=[]
hotplugProviderInstalled=false
hotplugProviderStatus=missing
```

Source inspection suggests `VZVirtualMachineInstance.hotplug(_:, id:)` throws
`ContainerizationError(.unsupported, message: "hotplug not supported")` when
`hotplugProvider` is nil.

### Question

Is there a public `VZInstanceExtension` / `HotplugProvider` implementation or
configuration step that consumers should append to `LinuxPod.Configuration.extensions`
to enable block-device and virtiofs hotplug for post-create `addContainer`?

If the provider is not public yet, should `LinuxPod.addContainer` post-create be
considered unsupported for public `0.33.4` consumers, despite the public API
surface?

### Expected behavior

Either:

- a documented public extension/provider can be added to `LinuxPod.Configuration`
  so post-create `addContainer` can hotplug an ext4 block rootfs into a running
  VZ-backed pod; or
- the public API/docs clearly state that post-create `LinuxPod.addContainer`
  requires a provider implementation that is not currently included by default.

### Actual behavior

`pod.addContainer(...)` after `pod.create()` fails with:

```text
unsupported: "hotplug not supported"
```

No provider appears to be installed by the default `VZVirtualMachineManager`
path, and I could not find a public provider/extension implementation in the
`0.33.4` source checkout.
```

## Posting Guidance

Do not post this via the ChatGPT Codex Connector. If the user wants this
published, use a user-approved non-connector route or have the user post the
draft manually.
