# Stage 10A Rootfs Materialization Feasibility

**Status:** `note-closed`
**Owner:** `tools/apple-container-compose-adapter`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Why This Exists

Stage 10A follows Stage 9D because the hotplug provider path remained
diagnostic-only. Stage 9D proved that a custom public extension/provider can be
installed and reached, but real second-container rootfs hotplug still stopped at
`unsupportedRootfsBlockHotplug`.

That leaves fast pod recreate as the main product path. Within that path, the
dominant controllable cost is still rootfs materialization: the current runtime
avoids repeated image unpack on rootfs-cache hits, but still performs full file
copies from the cached base rootfs into the project rootfs and from the project
rootfs into each per-container ext4 rootfs.

## Diagnostic Scope

Stage 10A tests whether APFS clone/COW style rootfs materialization can safely
avoid byte-for-byte copies using public macOS APIs:

- `fullCopy`
- `fileManagerCopy`
- `apfsClone`
- `clonefile`
- `copyfileClone`
- `auto`
- `unsupported`
- `unknown`

The probe is enabled only by `--stage10a-rootfs-materialization-probe` and
`--rootfs-materialization-strategy`. The normal runtime default remains the
existing copy behavior unless the diagnostic flag is used.

## Product Boundary

Stage 10A is diagnostic feasibility, not product rewrite.

Hotplug remains an upstream/research track. The product path should continue to
prefer fast pod recreate plus rootfs copy avoidance, APFS clone/COW or writable
layer investigation, and warm ext4 volumes until runtime evidence proves a safer
option.

No host memory savings claim is made.

No Docker/OrbStack viability claim is made.

Do not claim Docker/OrbStack gate passed from Stage 10A evidence.

## Evidence Expectations

Stage 10A evidence must record:

- requested and actual rootfs materialization strategy;
- whether clone APIs were attempted, returned success, and were verified;
- whether byte-for-byte copy work was avoided;
- project/container rootfs existence and readability;
- proof that the cached base rootfs was not mutated;
- whether block I/O attribution is phase measured, whole-run only, or not
  measured;
- redacted adapter-owned paths only;
- cleanup proof with zero adapter-owned leftovers.

The validator rejects unsafe product-ready claims, dirty cleanup, path leaks,
unverified clone success, and clone/copy-avoidance contradictions.

## Current Implementation

The Stage 10A harness writes `stage10aRootfsMaterializationProbe` JSONL records
with schema
`container-compose-adapter/linuxpod-stage10a-rootfs-materialization-probe/v1`.
It materializes the real cached rootfs into a temporary adapter-owned project
runtime, then materializes that project rootfs into a temporary per-container
ext4 path. It does not create a LinuxPod VM, does not start services, and does
not change the normal Compose/LinuxPod runtime path.

The `auto` probe records a baseline `fullCopy` record and a clone-attempt
record, so the evidence can compare the current copy behavior with the clone
candidate in the same diagnostic run.

## Runtime Evidence

- Evidence: `docs/evidence/linuxpod-stage10a-rootfs-materialization/20260613T101706Z-stage10a-rootfs-materialization.jsonl`
- Command:
  `container-compose-phase6-benchmark --stage10a-rootfs-materialization-probe --rootfs-materialization-strategy auto --project-prefix stage10a --run-label rootfs-materialization --docker-hub-mirror mirror.gcr.io --approval-token <approval-token>`
- Records: `2`
- `containerizationVersion`: `0.33.4`
- `containerizationRevision`: `9275f365dd555c8f072e7d250d809f5eb7bdd746`
- macOS: `Version 26.5.1 (Build 25F80)`
- host architecture: `arm64`
- image: `mirror.gcr.io/library/postgres:16-alpine`
- rootfs cache hit: `baseRootfsUnpack=0`
- path redaction: passed; evidence paths use `<repo>`
- leakage scan: passed for local paths, approval token, and common secret names
- cleanup proof: both records have `cleanupResult=clean`,
  `zeroAdapterOwnedLeftovers=true`, and `leftoverPathsCount=0`

Full-copy baseline:

- `requestedStrategy=fullCopy`
- `actualStrategy=fullCopy`
- `cloneAttempted=false`
- `copyAttempted=true`
- `rootfsWorkAvoided=false`
- `byteForByteCopyAvoided=false`
- `bytesCopiedIfKnown=4294967296`
- `projectRootfsMaterialize=0.00022494792938232422`
- `containerRootfsMaterialize=0.00020694732666015625`
- `ext4ImageLooksValid=true`
- `baseRootfsUnchanged=true`
- `productReady=false`
- `nextRecommendedPath=keepFullCopy`

Auto/clone candidate:

- `requestedStrategy=auto`
- `actualStrategy=clonefile`
- `cloneAttempted=true`
- `cloneReturnedSuccess=true`
- `cloneVerified=true`
- `cloneVerificationStrength=strong`
- `cloneSucceeded=true`
- `copyAttempted=false`
- `rootfsWorkAvoided=true`
- `byteForByteCopyAvoided=true`
- `bytesCopiedIfKnown=null`
- `projectRootfsMaterialize=0.0002090930938720703`
- `containerRootfsMaterialize=0.0002560615539550781`
- `ext4ImageLooksValid=true`
- `baseRootfsUnchanged=true`
- `productReady=false`
- `nextRecommendedPath=useClonefileForRootfs`

## Decision

Stage 10A is closed as a positive diagnostic feasibility result: public
`clonefile` rootfs materialization succeeded on this macOS/APFS host, kept the
cached base rootfs unchanged, produced readable ext4 rootfs artifacts, avoided
byte-for-byte copy work, and cleaned up the temporary adapter-owned project
state.

This is not a product-ready runtime switch. The normal runtime default remains
full-copy materialization. The next concrete task is a guarded Stage 10B plan or
implementation slice that wires `clonefile`/`auto` into the runtime behind an
explicit opt-in or tightly validated integration path, then measures a
backend-shaped fast pod recreate flow. If that integration exposes correctness,
mutation, or cleanup risk, keep full copy as the product path and investigate a
writable layer or upstream rootfs reuse instead.
