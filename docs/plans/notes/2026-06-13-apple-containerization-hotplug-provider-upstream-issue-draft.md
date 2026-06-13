# Apple Containerization Hotplug Provider Upstream Issue Draft

**Status:** `note-open`
**Owner:** `tools/apple-container-compose-adapter`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

Do not post this issue from Codex. If upstream follow-up is needed, the user
should review and post manually or explicitly approve a non-connector posting
route for that specific action.

## Draft

Title: Clarify public LinuxPod post-create rootfs hotplug provider expectations

0.33.4 active in a downstream feasibility probe:

- SwiftPM package pin: `apple/containerization` `0.33.4`
- resolved revision: `9275f365dd555c8f072e7d250d809f5eb7bdd746`
- `LinuxPod.addContainer` after `pod.create()` reaches the hotplug path
- default VZ config has `vmConfigExtensionCount=0`
- `hotplugProviderInstalled=false`
- observed failure is `"hotplug not supported"`

Follow-up Stage 9D custom-provider evidence:

- evidence: `docs/evidence/linuxpod-stage9d-hotplug-provider/20260613T093056Z-stage9d-hotplug-provider-feasibility.jsonl`
- downstream public `LinuxPod.Configuration.extensions` wiring can install a custom `VZInstanceExtension`
- `linuxPodConfigExtensionCount=1`
- `vmConfigExtensionCount=1`
- `hotplugProviderInstalled=true`
- `providerDidCreateCalled=true`
- post-create `LinuxPod.addContainer` reaches the custom provider (`providerHotplugCalled=true`)
- public `VZUSBMassStorageDevice` attach/detach succeeded in the provider
- second container still did not start because there was no safe public mapping to the LinuxPod `AttachedFilesystem` guest block-device path for the ext4 rootfs
- final blocker: `unsupportedRootfsBlockHotplug`

Questions:

1. Is a public extension/provider expected to be installed by downstream users
   through `LinuxPod.Configuration.extensions`, or should the default VZ-backed
   LinuxPod path eventually provide one?
2. Is block/ext4 rootfs hotplug expected to be supported for post-create
   `LinuxPod.addContainer`, or are current public hotplug interfaces intended
   for other attachment types first?
3. If the default state is intentionally unsupported, should the docs or error
   clarify that public VZ LinuxPod has no default hotplug provider installed?
4. If downstream providers are expected, is there a supported public way to map
   a newly attached public VZ USB mass-storage device to the correct guest
   block-device path and return a valid `AttachedFilesystem` for LinuxPod rootfs
   hotplug without guessing?

This is not a request for private APIs or private entitlements.
