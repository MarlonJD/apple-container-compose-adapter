# Compose Frontend To LocalDevProject Plan

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `completed`

## Objective

Implement the first test-driven Compose frontend slice for the new
Apple-native local development orchestrator direction.

The goal is to parse a useful local-development subset of Docker Compose YAML
into `LocalDevProject`, then bridge that graph into the existing `RuntimePlan`
dry-run path. This establishes the executable path:

```text
Docker Compose YAML
        -> ComposeFrontend
        -> LocalDevProject IR
        -> RuntimePlan dry-run planning
        -> LinuxPodBackend / NoopDryRunBackend
```

This plan intentionally does not implement persistent LinuxPod hotplug,
rootfs-cache optimization, Kubernetes input parsing, or runtime mutation.

## Scope

Implement a small Compose frontend that supports the repository's public
fixtures and the first practical local-development subset:

- services with `image`;
- `command` and `entrypoint`;
- `environment` map/list forms;
- `env_file` as preserved IR intent;
- `ports` with deterministic host ports;
- service volume mounts for named volumes and bind mounts;
- top-level named volumes;
- `depends_on` short syntax and condition form;
- `healthcheck.test` with timeout/retries/start period preserved where useful;
- `profiles`;
- job classification for Compose services that should be treated as one-off
  jobs in fixture/planner tests.

The first fixtures should be:

- `docs/evidence/fixtures/simple-web/compose.yaml`;
- `docs/evidence/fixtures/backend-shaped/compose.yaml`.

## Assumptions And Open Questions

Assumptions:

- Docker Compose behavior remains the compatibility reference.
- `LocalDevProject` is the stable input-independent IR boundary.
- The current `RuntimePlan` and backend dry-run path should remain usable while
  the richer Apple-native planner is still being designed.
- Unsupported Compose fields should produce diagnostics, not silent behavior.
- Runtime mutation is out of scope for this parser/frontend slice.

Open questions:

- Whether to add a YAML dependency such as `Yams` or use an existing package
  already available in the Swift dependency graph.
- How to classify jobs generically beyond the public backend-shaped fixture.
- Whether `build` should remain a blocking diagnostic or become preserved
  non-executable intent only in this first slice.
- How much Compose interpolation to implement before the first runtime planner
  integration.

## Explicit Out Of Scope

- Kubernetes input parsing.
- Helm or Kustomize execution.
- Docker Engine API compatibility.
- Docker-compatible backend support for Docker Desktop, OrbStack, Colima,
  Podman, Lima, Rancher Desktop, or Finch.
- Persistent LinuxPod hotplug or project runtime reuse.
- Rootfs cache, APFS clone, writable-layer, initfs, kernel, or vminit
  microbenchmark implementation.
- Private EMSI workloads or private registry credentials.
- Runtime mutation, image pulls, registry login, Keychain mutation, host DNS
  mutation, global prune, or destructive cleanup.

## Phases

### Phase 1: Compose Model And Parser Boundary

- Add a narrow `ComposeFrontend` API that accepts a Compose file path or YAML
  bytes and returns `LocalDevProject`.
- Add structured Compose DTOs for only the supported fields.
- Add diagnostics for unsupported fields that matter for local development.
- Keep parser code independent from LinuxPod runtime execution.

### Phase 2: Fixture Normalization

- Add tests for `simple-web` and `backend-shaped` fixture parsing.
- Verify service names, images, commands, environment, ports, named volumes,
  bind mounts, healthchecks, dependencies, profiles, and job intent.
- Verify unsupported or unimplemented fields produce clear diagnostics.
- Ensure secret-looking environment values remain redacted in downstream
  dry-run output.

### Phase 3: RuntimePlan Bridge

- Bridge parsed `LocalDevProject` into the existing `RuntimePlan`.
- Add tests proving fixture-derived plans render the same essential dry-run
  action shape as current hand-written sample plans.
- Preserve current `SamplePlans` as deterministic fixtures until the parser
  path is stable enough to replace them.

### Phase 4: CLI Dry-run Entry Point

- Add a no-side-effect CLI option for Compose input if it fits the existing CLI
  shape without widening scope too much, for example `--file compose.yaml`.
- Support dry-run only in this phase.
- Keep runtime execution from parsed Compose gated until parser and planner
  behavior are covered by tests.

### Phase 5: Documentation And Plan Tracking

- Update README or docs when introducing user-visible CLI flags.
- Add an example or fixture note explaining the supported Compose subset.
- Update `docs/plans/index.md` with the next real todo or completion state.
- Add a note for durable compatibility gaps discovered during implementation.

## Verification Gates

Required before claiming completion:

- `swift test`
- `git diff --check`
- Parser/normalizer tests for `simple-web` and `backend-shaped`.
- Dry-run rendering tests for fixture-derived plans.
- Evidence that no runtime mutation is required for the parser/frontend path.

Runtime smoke is not required for this plan. If runtime smoke is attempted
later, it must be covered by a separate approved runtime task and signed binary
flow.

## Risks And Mitigations

Risk: the parser becomes a partial Compose implementation with unclear
behavior.

Mitigation: document the supported subset and emit diagnostics for unsupported
fields.

Risk: job classification becomes too fixture-specific.

Mitigation: keep classification explicit and tested; do not hide uncertain
semantics behind automatic behavior.

Risk: adding a YAML dependency introduces licensing or maintenance risk.

Mitigation: verify license compatibility with `AGPL-3.0-or-later` and prefer a
small, standard Swift YAML parser if needed.

Risk: dry-run output drifts from current hand-authored sample plans.

Mitigation: compare essential action shape rather than brittle full text, and
keep sample plans until parser-derived plans are proven.

Risk: parser work accidentally grows into runtime mutation.

Mitigation: keep CLI support dry-run only in this plan and do not run commands
that create, start, stop, delete, pull, login, or mutate host state.

## Dependencies And Ownership Boundaries

- Owner: `tools/apple-container-compose-adapter`.
- Do not edit parent EMSI monorepo files in this task.
- Do not update submodule pointers in this task.
- Do not create, switch, rename, or delete branches.
- Treat Compose files as untrusted input.
- Preserve AGPL-compatible dependency requirements.

## Affected Files Or Docs

Expected files:

- `Package.swift` if a YAML dependency is added.
- `Sources/ContainerComposeAdapter/ComposeFrontend.swift`
- `Sources/ContainerComposeAdapter/LocalDevProject.swift`
- `Sources/ContainerComposeAdapter/SamplePlans.swift` only if bridging is
  consolidated carefully.
- `Tests/ContainerComposeAdapterTests/*`
- `docs/evidence/fixtures/*`
- `README.md` only if a user-facing CLI flag is added.
- `docs/plans/index.md`
- `docs/plans/notes/index.md` if a durable compatibility gap is recorded.

## Rollback Or Recovery Notes

If parsing proves too broad for one pass, keep `LocalDevProject` and docs
intact, then narrow the parser to the two public fixtures plus explicit
diagnostics. Do not remove the existing hand-written `SamplePlans` until the
fixture parser path is at least as well covered.

If a YAML dependency is rejected, pause implementation and create a note with
the rejected dependency, license, and alternatives.

## Execution Prompt

Use this prompt to execute the plan:

```text
You are working in MarlonJD/apple-container-compose-adapter at /Users/marlonjd/Developer/monorepos/emsi_monorepo/tools/apple-container-compose-adapter.

Execute docs/plans/2026-06-12-compose-frontend-localdevproject-plan.md only. Use emsi-workflows:emsi-task-router, emsi-workflows:emsi-verification-gate, superpowers:test-driven-development, and superpowers:verification-before-completion. Read AGENTS.md, README.md, docs/localdevproject-ir.md, docs/apple-native-local-dev-orchestrator.md, Sources/ContainerComposeAdapter/LocalDevProject.swift, Sources/ContainerComposeAdapter/SamplePlans.swift, Sources/ContainerComposeAdapter/LinuxPodBackend.swift, and Tests/ContainerComposeAdapterTests/RuntimeContractTests.swift before editing.

Implement the first ComposeFrontend slice: parse the public simple-web and backend-shaped Compose fixtures into LocalDevProject, bridge to RuntimePlan, add tests for supported fields and diagnostics, and keep all behavior dry-run/no-runtime-mutation. Do not implement Kubernetes parsing, persistent LinuxPod hotplug, rootfs-cache optimization, writable layers, Docker-compatible backends, registry login, host DNS mutation, or runtime execution from parsed Compose.

Verification required before claiming completion: swift test, git diff --check, parser/normalizer tests for both fixtures, dry-run rendering tests for fixture-derived plans, and docs/plans/index.md updated to the actual final state. If you add a dependency, confirm license compatibility with AGPL-3.0-or-later. Do not create/switch branches. Commit child repo changes before any parent monorepo submodule pointer update, and do not update the parent unless explicitly asked.
```
