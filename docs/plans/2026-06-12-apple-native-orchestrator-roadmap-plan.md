# Apple-native Orchestrator Roadmap

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `active`

## Objective

Define the next product roadmap for Container Compose Adapter after the
Apple-native local development orchestrator repositioning.

The roadmap answers three questions:

- what we prepare next;
- when benchmarks are meaningful;
- how the project moves from docs and IR scaffold to a credible
  Compose/Kubernetes local-development orchestrator on Apple runtime surfaces.

## Scope

This roadmap covers the sequence from the current state to the first credible
product benchmark:

```text
ComposeFrontend
        -> LocalDevProject IR
        -> AppleNativePlanner
        -> LinuxPodProjectRuntime research
        -> benchmark evidence
```

It includes milestone gates, benchmark timing, verification expectations, and
the first concrete implementation task. It does not implement code by itself.

## Current State

Already prepared:

- Product positioning: experimental Apple-native local-dev orchestrator.
- `LocalDevProject` IR scaffold.
- RuntimePlan bridge from IR scaffold.
- LinuxPod runtime experiments and safety checks.
- Benchmark metadata scaffold.
- Documentation for Compose/Kubernetes inputs, LinuxPod runtime direction, and
  benchmark metrics.
- Phase 6B root-cause plan archived so it does not confuse the new direction.

Most recent completed implementation tasks:

- Stage 5 backend-shaped product smoke is complete. Fixture-derived dry-run
  evidence passed, explicit runtime approval was granted, and one signed
  backend-shaped fixture runtime smoke ran through the CLI `--compose-file`
  fixture-derived path: db healthy, migrate/seed exited `0`, api ready,
  `down --volumes` cleanup proven with zero adapter-owned leftovers. Evidence
  note: `docs/plans/notes/2026-06-12-stage-5-backend-smoke-evidence.md`
  (`note-closed`).
- Stage 6 cold/image-store-seeded comparative benchmark is complete. Cold
  measured `3/5` before two Docker Hub `429` registry failures; the final
  image-store-seeded fresh runtime run measured `5/5` with mirror-backed
  `linux/arm64` seed image-store, zero failures, and clean cleanup. This did
  not measure persistent project LinuxPod reuse: rootfs/initfs/volume/pod
  lifecycle stayed cold. The Docker/OrbStack viability gate still failed on
  startup/readiness, guest cgroup memory, and block reads. Evidence note:
  `docs/plans/notes/2026-06-12-stage-6-cold-warm-benchmark-decision.md`
  (`note-closed`).
- Stage 7 Kubernetes local-dev subset is complete. Rendered Kubernetes YAML
  for the backend-shaped fixture produces the same `RuntimePlan` as Compose,
  and all five dry-run surfaces are covered by JSONL evidence. Evidence note:
  `docs/plans/notes/2026-06-12-stage-7-kubernetes-subset-evidence.md`
  (`note-closed`).

Next roadmap task:

- Stage 8, if explicitly approved, should isolate persistent project LinuxPod
  + rootfs/initfs/volume cache + service hotplug/reuse. Do not start runtime
  execution until that hypothesis is approved in the current task.

## Roadmap Summary

### Stage 1: Compose Frontend, No Runtime Mutation

Prepare:

- Parse public Compose fixtures.
- Normalize services, jobs, volumes, ports, environment, healthchecks,
  `depends_on`, profiles, and mounts into `LocalDevProject`.
- Bridge parsed projects into existing dry-run planning.
- Keep hand-authored `SamplePlans` until parser-derived plans match the
  essential action shape.

Benchmark:

- Do not run runtime benchmarks in this stage.
- Run parser/planner tests and dry-run rendering checks only.

Why:

- A runtime benchmark before parser/planner correctness would measure a
  hand-built sample, not the product path.

### Stage 2: AppleNativePlanner Compatibility Contract

Prepare:

- Introduce an `AppleNativePlanner` boundary between `LocalDevProject` and
  backend-specific actions.
- Produce structured compatibility diagnostics for unsupported Compose fields.
- Add a support matrix for the first Compose subset.
- Keep all output inspectable in dry-run form.

Benchmark:

- Still no performance benchmark.
- Use no-side-effect fixture-derived dry-run evidence to prove command shape,
  dependencies, readiness ordering, cleanup scope, and redaction.

Why:

- This makes the measured execution path stable and explains unsupported
  behavior before the runtime is touched.

### Stage 3: Runtime Store And Persistent LinuxPod Research Spike

Prepare:

- Test whether one project can safely map to one persistent LinuxPod runtime.
- Probe add-container/hotplug behavior.
- Keep adapter-owned runtime state checks strict.
- Separate project runtime state from reusable cache state.
- Define cleanup proof for runtime, volumes, ports, logs, and cache.

Benchmark:

- Run only small signed smoke checks with explicit runtime approval.
- Do not compare against Docker/OrbStack yet.

Why:

- First prove the lifecycle is safe and observable. Competitive benchmarks are
  not useful until the runtime path can survive repeated clean runs.

### Stage 4: Rootfs, Volume, And Healthcheck Microbenchmarks

Prepare:

- Rootfs unpack baseline.
- Rootfs copy vs APFS clone.
- Image digest keyed rootfs cache proof.
- Initfs/kernel/vminit cache metadata.
- Ext4 named volume fresh vs warm behavior.
- Healthcheck exec overhead measurement.

Benchmark:

- Run microbenchmarks, not product benchmarks.
- Record JSONL with cold/warm lifecycle, cache hit/miss, block I/O, timing,
  guest cgroup metrics, cleanup result, and host-memory status.

Why:

- This identifies bottlenecks before spending time on a full backend-shaped
  product benchmark.

### Stage 5: Backend-shaped Product Smoke

Prepare:

- Fixture-derived Compose path runs:
  - Postgres;
  - named volume;
  - migrate job;
  - seed job;
  - API service;
  - internal service DNS or managed hosts;
  - deterministic host port;
  - healthchecks;
  - logs/status;
  - safe cleanup.

Benchmark:

- Run one signed LinuxPod smoke only after dry-run evidence is reviewed and
  runtime approval is explicit.
- Require zero cleanup leftovers before repeating.

Why:

- This proves functional product shape. It still does not justify replacement
  claims.

### Stage 6: Cold/Image-store-seeded Comparative Benchmark

Status: complete. See
`docs/plans/notes/2026-06-12-stage-6-cold-warm-benchmark-decision.md`.

Prepare:

- Stable fixture-derived backend-shaped runtime path.
- Repeatable cleanup proof.
- Docker/OrbStack baseline command plan.
- JSONL schema with cache/lifecycle/environment metadata.
- Clear host-memory limitation wording.

- Run cold and image-store-seeded fresh-runtime LinuxPod measurements.
- Compare against Docker/OrbStack only after LinuxPod has zero failures across
  repeated measured runs with accurately labeled cache/lifecycle metadata.
- Treat Docker Desktop, OrbStack, Colima, Podman, Lima, Rancher Desktop, and
  Finch as baselines or optimization references, not implementation backends.

Why:

- This is the first point where performance numbers can say something about
  product viability, but Stage 6 proved only that image-store-only warming is
  insufficient. It did not measure persistent project LinuxPod reuse.

### Stage 7: Kubernetes Local-dev Subset

Status: complete. See
`docs/plans/notes/2026-06-12-stage-7-kubernetes-subset-evidence.md`.

Prepare:

- Add KubernetesSubsetFrontend after Compose path proves the IR.
- Consume rendered YAML from Kubernetes manifests, Helm, or Kustomize.
- Translate Deployment, StatefulSet, Service, ConfigMap, Secret, Job, PVC,
  Ingress, and Namespace into `LocalDevProject`.

Benchmark:

- Start with parser/planner and dry-run checks.
- Runtime benchmark only after the Kubernetes path produces the same
  backend-shaped graph as Compose.

Why:

- Kubernetes is an input frontend, not a runtime product by itself.

### Stage 8: Persistent Project LinuxPod Cache Experiment

Status: in progress. Stage 8A instrumentation/classification is complete; see
`docs/plans/notes/2026-06-12-stage-8a-instrumentation-classification.md`.
Stage 8B rootfs/initfs cache code is complete; see
`docs/plans/notes/2026-06-12-stage-8b-rootfs-initfs-cache-slice.md`.
Stage 8C-8E warm volume, persistent pod/hotplug, and all-warm benchmark
policy code is complete; see
`docs/plans/notes/2026-06-12-stage-8c-8d-8e-warm-runtime-slice.md`.
Signed E/F/G runtime validation remains the next approval-gated task.

Prepare:

- Keep LinuxPod as the runtime research target.
- Do not add Docker-compatible, Colima, Podman, Lima, Rancher Desktop, Docker
  Desktop, OrbStack, or container-compose backends.
- Preserve adapter-owned cleanup boundaries and seed image-store safety.
- Make lifecycle metadata unambiguous: image store, rootfs, initfs, volume, pod,
  and service reuse must be reported separately.
- Preserve explicit `notMeasured` host-port and load-window metadata when
  those metrics are missing.

Experiment matrix:

| Mode | Purpose |
| --- | --- |
| A. cold runtime | Baseline with no prepared cache or reusable state. |
| B. image-store-seeded fresh runtime | Confirms Stage 6 result with corrected metadata. |
| C. rootfs-cache hit runtime | Isolates rootfs preparation cost. |
| D. initfs-cache hit runtime | Isolates initfs preparation cost. |
| E. warm preserved volume | Isolates named-volume reuse cost and correctness. |
| F. persistent pod / hotplug | Isolates pod create/reuse and service registration behavior. |
| G. all-warm project runtime | Measures persistent project LinuxPod + rootfs/initfs/volume cache + service hotplug/reuse together. |

Metrics:

- startup/readiness
- rootfs prep duration
- initfs prep duration
- volume create/reuse duration
- pod create/reuse duration
- container start duration
- healthcheck attempts/duration
- cgroup current/peak
- process RSS
- block read/write
- data footprint
- host port TTFB
- completed work per load window
- cleanup result

Acceptance criteria:

- `swift test` passes.
- Existing LinuxPod functionality remains intact.
- No Docker-compatible backend is added.
- No Colima/Podman/Lima/Rancher/Docker Desktop/OrbStack backend is added.
- No container-compose backend is added.
- Stage 6 docs do not imply persistent project LinuxPod was measured.
- Seed image-store failures are recorded in JSONL and cleanup runs.
- Seed image-store safety keeps adapter-owned/sentinel boundaries.
- `linux/arm64` platform validation is not skipped just because an image
  reference exists.
- `imageCacheStatus` is verified or explicitly marked unverified/partial.
- Cgroup memory unlimited/overflow evidence does not emit bogus UInt64 values.
- Readiness dry-run evidence is regenerated or marked stale/pre-fix.
- Host port/load-window gaps are measured or explicitly marked not measured.
- No host-memory savings claims are added.
- No global prune command is added.
- Cleanup remains adapter-owned and safe.

## Benchmark Timing

Do not benchmark everything immediately. Use these gates:

1. **Now:** parser/planner tests and dry-run output only.
2. **After ComposeFrontend passes:** no-side-effect fixture-derived dry-run
   evidence.
3. **After AppleNativePlanner contract:** dry-run compatibility matrix and
   diagnostics evidence.
4. **After persistent runtime spike:** one signed smoke with explicit runtime
   approval.
5. **After rootfs/volume microbenchmarks:** targeted microbenchmark reports.
6. **Completed after backend-shaped fixture was stable:** cold and
   image-store-seeded fresh-runtime product benchmarks.
7. **Completed after Kubernetes graph equivalence:** local-dev manifest
   translation evidence without runtime benchmark claims.
8. **Current proposed runtime hypothesis:** persistent project LinuxPod +
   rootfs/initfs/volume cache + service hotplug/reuse, only after explicit
   approval.

## Assumptions And Open Questions

Assumptions:

- Compose remains the first-class input.
- `LocalDevProject` remains the shared IR for Compose and Kubernetes.
- Docker Compose behavior is the compatibility reference.
- LinuxPod is the primary Apple-native runtime research target.
- Apple `container` CLI is a probe/reference/repro helper, not the main
  implementation target.

Open questions:

- Which YAML parser dependency is acceptable for AGPL-compatible distribution?
- What is the least surprising rule for classifying Compose services as jobs?
- Can LinuxPod safely support persistent project lifecycle and service
  hotplug/reuse?
- Which rootfs strategy gives correct behavior with acceptable warm-loop cost?
- Which host-memory source, if any, can support host RAM claims?
- Which host-port publishing path, if any, can prove localhost developer access
  from macOS for the backend-shaped fixture?

## Explicit Out Of Scope

- Docker Engine clone.
- Full Kubernetes distribution.
- Docker-compatible backend switching.
- Host RAM savings claims without host-level evidence.
- Global prune or destructive host cleanup.
- Registry, Keychain, Docker Hub, or host DNS mutation.
- Private EMSI workloads in benchmark evidence.

## Verification Gates

Roadmap tracking changes must pass:

- `git diff --check`.

Implementation plans under this roadmap must pass their own gates, usually:

- `swift test`;
- fixture parser tests;
- dry-run rendering checks;
- JSONL validation for benchmark work;
- signed runtime smoke only when explicit approval is given.

## Risks And Mitigations

Risk: benchmarking too early produces misleading numbers.

Mitigation: benchmark only after the measured path is parser-derived,
planner-derived, and cleanup-safe.

Risk: runtime research overwhelms product direction.

Mitigation: keep runtime research behind gates and always connect it back to
Compose/Kubernetes local-development graphs.

Risk: Kubernetes scope expands into a cluster project.

Mitigation: treat Kubernetes as a frontend that compiles into `LocalDevProject`
and reject production cluster semantics.

Risk: benchmark results are used as marketing claims.

Mitigation: require decision notes, host-memory caveats, and comparison
baselines before any replacement wording.

## Dependencies And Ownership Boundaries

- Owner: `tools/apple-container-compose-adapter`.
- Child repository changes must be committed and pushed before parent submodule
  pointer updates.
- Do not update the parent EMSI monorepo unless explicitly asked.
- Do not create, switch, rename, or delete branches unless explicitly asked.
- Keep source, docs, tests, and plan names in English.

## Affected Files Or Docs

Roadmap tracking touches:

- `docs/plans/index.md`;
- `docs/plans/2026-06-12-apple-native-orchestrator-roadmap-plan.md`;
- active implementation plans such as
  `docs/plans/completed/2026-06-12-compose-frontend-localdevproject-plan.md`.

Future implementation stages may touch:

- `Sources/ContainerComposeAdapter/*`;
- `Tests/ContainerComposeAdapterTests/*`;
- `README.md`;
- `docs/evidence/*`;
- `docs/plans/notes/*`.

## Rollback Or Recovery Notes

If this roadmap becomes too broad, keep Stage 1 as the only active
implementation plan and move later stages into notes. If runtime evidence
contradicts LinuxPod viability again, keep the Compose/Kubernetes frontend and
planner work: those remain useful even if the runtime strategy changes later.

## Execution Prompt

Use this prompt to continue from the roadmap:

```text
You are working in MarlonJD/apple-container-compose-adapter at /Users/marlonjd/Developer/monorepos/emsi_monorepo/tools/apple-container-compose-adapter.

Use docs/plans/2026-06-12-apple-native-orchestrator-roadmap-plan.md as the roadmap. Stage 1 through Stage 7 are complete or documented in the plan indexes. Stage 5 closed with fixture-derived dry-run evidence plus one approved signed backend-shaped runtime smoke and cleanup proof; see docs/plans/notes/2026-06-12-stage-5-backend-smoke-evidence.md. Stage 6 closed with cold plus image-store-seeded fresh-runtime evidence; the final legacy-named warm JSONL measured image-store seeding only, not persistent project LinuxPod reuse; see docs/plans/notes/2026-06-12-stage-6-cold-warm-benchmark-decision.md and docs/evidence/linuxpod-stage6-benchmark/20260612T125100Z-stage6-warm-5-escalated-readiness.jsonl. Stage 7 closed with Kubernetes subset graph-equivalence and dry-run evidence; see docs/plans/notes/2026-06-12-stage-7-kubernetes-subset-evidence.md.

The next runtime hypothesis, if explicitly approved in the current task, is persistent project LinuxPod + rootfs/initfs/volume cache + service hotplug/reuse. Implement the smallest safe Stage 8 slice that can distinguish: A cold runtime, B image-store-seeded fresh runtime, C rootfs-cache hit runtime, D initfs-cache hit runtime, E warm preserved volume, F persistent pod/hotplug, and G all-warm project runtime.

Metrics to preserve in JSONL: startup/readiness, rootfs prep duration, initfs prep duration, volume create/reuse duration, pod create/reuse duration, container start duration, healthcheck attempts/duration, cgroup current/peak, process RSS, block read/write, data footprint, host port TTFB, completed work per load window, and cleanup result. Mark missing host-port/load-window metrics as notMeasured rather than zero.

Do not add Docker-compatible, Colima, Podman, Lima, Rancher Desktop, Docker Desktop, OrbStack, or container-compose backends. Do not mutate registry credentials, Keychain, host DNS, global caches, or use global prune. Keep seed image-store safety adapter-owned/sentinel-bounded unless an explicit external allow flag is provided. Do not claim host memory savings.

Verification before runtime request: swift test, git diff --check, and dry-run/evidence validation. Verification after approved runtime work: JSONL validation, cleanup proof with zero adapter-owned project runtime leftovers, swift test, git diff --check, and docs/plans/index.md updated to the actual final state. Do not create/switch branches. Commit/push child repo changes before any parent submodule pointer update, and do not update the parent unless explicitly asked.
```
