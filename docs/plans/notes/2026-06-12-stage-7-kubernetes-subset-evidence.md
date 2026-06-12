# Stage 7 Kubernetes Local-dev Subset Evidence

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `note-closed`
**Linked plan:** [Apple-native Orchestrator Roadmap](../2026-06-12-apple-native-orchestrator-roadmap-plan.md)

## Scope Delivered

`KubernetesSubsetFrontend` translates rendered Kubernetes YAML (kubectl, Helm
template, or Kustomize output) into `LocalDevProject`, feeding the same
`AppleNativePlanner` and dry-run surfaces as the Compose frontend. The
implemented object subset matches `docs/kubernetes-input-subset.md`:

- Deployment and StatefulSet -> long-running `LocalDevService` (single
  replica, single container).
- Job -> `LocalDevJob` run-to-completion.
- Service -> internal DNS intent; deterministic host ports only through
  `cca.local/host-port` (+ optional `cca.local/host-ip`) annotations.
- ConfigMap/Secret -> resolved env values via `valueFrom`/`envFrom`
  (base64 `data` and `stringData` both supported); objects preserved as
  `LocalDevConfig`/`LocalDevSecret` intent.
- PersistentVolumeClaim -> adapter-owned `LocalDevVolume` with parsed
  storage size.
- Ingress -> `LocalDevRoute` ingress-lite intent.
- Namespace -> single local project scope; multi-namespace renders collapse
  with a diagnostic.
- `cca.local/depends-on` annotation restores Compose-style startup ordering
  (Kubernetes has no `depends_on`); `cca.local/profile` and
  `cca.local/ignore` tune translation.

Unsupported kinds and shapes produce diagnostics with workarounds:
multi-replica controllers, multi-container pods, initContainers, non-exec
probes, non-PVC volume sources, unresolvable secret/config references
(blocking), orphan Service selectors, and unknown kinds.

The shared YAML subset parser gained Kubernetes-style sequence-of-mapping
support (`- key: value` items with continuation pairs two columns past the
dash) and multi-document splitting on `---` lines.

## Graph Equivalence Gate

The Stage 7 gate required the Kubernetes path to produce the same
backend-shaped graph as Compose before any runtime claim. Evidence:

- Fixture: [k8s.yaml](../../evidence/fixtures/backend-shaped/k8s.yaml)
  (hand-rendered manifests mirroring
  [compose.yaml](../../evidence/fixtures/backend-shaped/compose.yaml)).
- `KubernetesSubsetFrontendTests.testBackendShapedKubernetesRenderMatchesComposeRuntimeGraph`
  asserts the Kubernetes-derived `RuntimePlan` equals the Compose-derived plan
  service-by-service (db, api, migrate, seed) including images, commands,
  resolved environment, deterministic host ports `15432`/`18081`,
  named-volume mounts, readiness/healthchecks, and dependency conditions, plus
  equal volume plans and zero blocking diagnostics.
- CLI dry-run evidence from the Kubernetes path (`--k8s-file`), all five
  surfaces, project resource `cca-linuxpod-backend-shaped`, zero blocking
  diagnostics:
  [20260612T114138Z-stage7-k8s-backend-shaped-dry-run.jsonl](../../evidence/linuxpod-stage7-kubernetes-subset/20260612T114138Z-stage7-k8s-backend-shaped-dry-run.jsonl)

No Kubernetes-path runtime benchmark was run: the roadmap allows it only after
graph equivalence, and the Stage 6 decision keeps further LinuxPod runtime
benchmarking gated. Because the Kubernetes path compiles into the identical
runtime plan, the Stage 5 signed runtime smoke and Stage 6 measurements apply
to it unchanged.

## Verification

- `swift test --filter KubernetesSubsetFrontendTests` (4 tests, 0 failures).
- Full `swift test` green.
- `git diff --check` clean.
- Stage 7 dry-run JSONL rendered with no runtime mutation.
