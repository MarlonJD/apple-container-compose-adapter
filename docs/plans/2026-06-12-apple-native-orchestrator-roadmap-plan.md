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

Most recent completed implementation task:

- [Compose Frontend To LocalDevProject Plan](completed/2026-06-12-compose-frontend-localdevproject-plan.md).

Next roadmap task:

- Create or execute the Stage 2 AppleNativePlanner compatibility contract only
  after an explicit task asks for it.

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

### Stage 6: Cold/Warm Comparative Benchmark

Prepare:

- Stable fixture-derived backend-shaped runtime path.
- Repeatable cleanup proof.
- Docker/OrbStack baseline command plan.
- JSONL schema with cache/lifecycle/environment metadata.
- Clear host-memory limitation wording.

Benchmark:

- Run cold and warm LinuxPod measurements.
- Compare against Docker/OrbStack only after LinuxPod has zero failures across
  repeated warm runs.
- Treat Docker Desktop, OrbStack, Colima, Podman, Lima, Rancher Desktop, and
  Finch as baselines or optimization references, not implementation backends.

Why:

- This is the first point where performance numbers can say something about
  product viability.

### Stage 7: Kubernetes Local-dev Subset

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
6. **After backend-shaped fixture is stable:** cold/warm product benchmarks.
7. **After zero-failure repeated warm runs:** compare against Docker/OrbStack
   and write a decision note.

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
- Can LinuxPod safely support persistent project lifecycle and hotplug?
- Which rootfs strategy gives correct behavior with acceptable warm-loop cost?
- Which host-memory source, if any, can support host RAM claims?

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

Use docs/plans/2026-06-12-apple-native-orchestrator-roadmap-plan.md as the roadmap. Stage 1, the ComposeFrontend -> LocalDevProject -> RuntimePlan dry-run slice, is completed and archived at docs/plans/completed/2026-06-12-compose-frontend-localdevproject-plan.md.

Prepare the next gated roadmap step only: create or execute a Stage 2 AppleNativePlanner compatibility contract plan after reading AGENTS.md, README.md, docs/apple-native-local-dev-orchestrator.md, docs/localdevproject-ir.md, docs/benchmark-and-metrics-plan.md, docs/plans/index.md, Sources/ContainerComposeAdapter/ComposeFrontend.swift, Sources/ContainerComposeAdapter/LocalDevProject.swift, Sources/ContainerComposeAdapter/SamplePlans.swift, and the relevant tests.

Keep runtime mutation, Kubernetes parsing, persistent LinuxPod hotplug, rootfs-cache optimization, writable layers, Docker-compatible backends, registry login, host DNS mutation, and product benchmarks out of scope unless a new explicit task approves one of those surfaces.

Verification required for planning-only changes: git diff --check. Verification required for implementation changes: swift test, git diff --check, targeted tests for the affected planner contract, and docs/plans/index.md updated to the actual final state. Do not create/switch branches. Commit and push child repo changes before any parent submodule pointer update, and do not update the parent unless explicitly asked.
```
