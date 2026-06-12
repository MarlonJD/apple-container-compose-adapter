# AppleNativePlanner Compatibility Contract Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-06-12
**Owner subtree:** `tools/apple-container-compose-adapter`
**Status:** `completed`
**Goal:** Introduce an `AppleNativePlanner` compatibility contract between `LocalDevProject` and backend-specific dry-run/runtime actions.

**Architecture:** `ComposeFrontend` continues to translate Docker Compose YAML into `LocalDevProject`. `AppleNativePlanner` becomes the named boundary that validates the graph against the first Apple-native local-development subset and emits a `RuntimePlan` plus structured compatibility diagnostics. `LinuxPodBackend` and `NoopDryRunBackend` keep consuming `RuntimePlan` so this stage remains dry-run-first and backend-safe.

**Tech Stack:** SwiftPM, XCTest, existing `ContainerComposeAdapter` runtime models, existing public fixtures under `docs/evidence/fixtures/`.

---

## Objective

Implement the Stage 2 roadmap gate from
`docs/plans/2026-06-12-apple-native-orchestrator-roadmap-plan.md`.

The work should make this product path explicit:

```text
Docker Compose YAML
        -> ComposeFrontend
        -> LocalDevProject IR
        -> AppleNativePlanner
        -> RuntimePlan
        -> LinuxPodBackend / NoopDryRunBackend dry-run actions
```

The compatibility contract must explain what the first Apple-native subset can
plan, what it preserves as intent only, and what it rejects with diagnostics
before any runtime mutation or benchmark happens.

## Scope

In scope:

- Add a public `AppleNativePlanner` API that consumes `LocalDevProject`.
- Return a structured planner result containing the `RuntimePlan`,
  compatibility diagnostics, and a support matrix for the first Compose subset.
- Keep `LocalDevProject.runtimePlan()` as a compatibility wrapper that delegates
  to `AppleNativePlanner`, so existing callers keep working during the
  transition.
- Move the current LocalDevProject-to-RuntimePlan normalization rules behind
  the planner boundary without changing the existing fixture-derived dry-run
  action shape.
- Add diagnostics for LocalDevProject fields that are currently silently
  ignored by runtime planning, such as env files, routes, secrets, configs,
  network aliases, unsupported restart policies, and non-default job completion
  policy.
- Add focused tests for fixture-derived planner diagnostics, support-matrix
  classification, action shape, redaction, and blocking diagnostics.
- Keep all verification no-side-effect except Swift tests and diff checks.

## Assumptions And Open Questions

Assumptions:

- Stage 1 is complete and pushed as child repo commit `7e6d127`; do not redo
  the Compose frontend implementation.
- Docker Compose behavior remains the compatibility reference.
- `LocalDevProject` remains the shared IR for future Compose and Kubernetes
  frontends.
- `RuntimePlan` remains the backend input for this stage.
- LinuxPod remains the primary Apple-native runtime research target, but no
  runtime mutation is approved by this plan.
- The first support matrix is project-owned Swift data with optional Markdown
  documentation later, not a generated benchmark report.

Open questions:

- Whether the support matrix should later be rendered in README as a user-facing
  compatibility table.
- Whether env files should become a blocking diagnostic immediately or a
  preserved-intent warning until env-file loading is implemented.
- Whether non-default restart policies should map to backend metadata later or
  stay unsupported until LinuxPod lifecycle semantics are proven.
- Whether routes should remain `preserved-intent` or become blocking when a
  command would otherwise appear executable.

## Explicit Out Of Scope

- Runtime mutation.
- Kubernetes parsing.
- Persistent LinuxPod hotplug.
- Rootfs-cache optimization.
- Writable layers.
- Docker-compatible backends for Docker Desktop, OrbStack, Colima, Podman,
  Lima, Rancher Desktop, or Finch.
- Registry login, Docker Hub credential changes, Keychain mutation, or image
  pull side effects.
- Host DNS mutation.
- Product performance benchmarks.
- Parent EMSI monorepo submodule pointer updates.

## File Structure

- Create `Sources/ContainerComposeAdapter/AppleNativePlanner.swift` for the
  planner boundary, support matrix types, compatibility diagnostics, and
  LocalDevProject-to-RuntimePlan normalization.
- Modify `Sources/ContainerComposeAdapter/LocalDevProject.swift` to keep only
  IR model definitions and delegate `runtimePlan()` to `AppleNativePlanner`.
- Modify `Tests/ContainerComposeAdapterTests/RuntimeContractTests.swift` for
  direct planner contract tests.
- Modify `Tests/ContainerComposeAdapterTests/ComposeFrontendTests.swift` so
  fixture-derived dry-run assertions plan through `AppleNativePlanner`.
- Optionally modify `README.md` only if implementation adds a user-visible
  command or public support table.
- Update `docs/plans/index.md` when implementation starts, pauses, completes,
  or discovers a durable compatibility gap.

## Support Matrix For This Stage

`AppleNativePlanner` should classify the first subset this way:

| Feature | Status | Planner behavior |
| --- | --- | --- |
| service image | `supported` | Required for executable services and jobs. |
| command and entrypoint | `supported` | Concatenate entrypoint + command for services; preserve job command. |
| environment map/list values | `supported` | Convert to sorted `EnvironmentVariable` values and rely on existing redaction. |
| env files | `unsupported` | Emit a diagnostic because runtime env-file loading is not implemented. |
| deterministic host ports | `supported` | Convert to `PortMapping`. |
| dynamic host ports | `unsupported` | Emit blocking diagnostic `unsupported-localdev-dynamic-port`. |
| bind mounts | `supported-with-safety-checks` | Convert to `MountPlan`; backend safety diagnostics still apply. |
| named-volume mounts | `supported` | Convert to `MountPlan` and `VolumePlan`. |
| tmpfs mounts | `unsupported` | Emit blocking diagnostic `unsupported-localdev-tmpfs-mount`. |
| build specs | `unsupported` | Emit blocking diagnostic `unsupported-localdev-build`. |
| depends_on conditions | `supported` | Map to `ReadinessKind`. |
| healthcheck test | `supported` | Map to `ReadinessProbe(serviceHealthy)`. |
| one-off jobs | `supported` | Map to `ServicePlan(kind: .oneOffJob)` with completion readiness. |
| routes | `preserved-intent` | Emit diagnostic until a local route layer exists. |
| secrets and configs | `preserved-intent` | Emit diagnostic until runtime injection exists. |
| network aliases | `preserved-intent` | Emit diagnostic until planner owns DNS/hosts semantics. |
| restart policy | `preserved-intent` | Emit diagnostic when policy is not the default local-dev behavior. |
| job allow-failure policy | `unsupported` | Emit diagnostic because readiness ordering assumes success. |

## Phases

### Phase 1: Contract Tests First

- [x] **Step 1: Add a failing direct planner test for the existing IR bridge**

Add this test to `Tests/ContainerComposeAdapterTests/RuntimeContractTests.swift`:

```swift
func testAppleNativePlannerPreservesCurrentRuntimePlanShape() throws {
    let project = LocalDevProject(
        id: "demo-stack",
        name: "Demo Stack",
        services: [
            LocalDevService(
                name: "api",
                image: "mirror.gcr.io/library/python:3.12-alpine",
                command: ["python", "app.py"],
                entrypoint: ["/bin/sh", "-ec"],
                environment: ["API_TOKEN": "secret-value"],
                mounts: [
                    LocalDevMount(kind: .namedVolume, source: "api-cache", target: "/cache")
                ],
                ports: [
                    LocalDevPort(hostIP: "127.0.0.1", hostPort: 18080, containerPort: 8080)
                ],
                dependencies: [
                    LocalDevDependency(target: "migrate", condition: .serviceCompletedSuccessfully)
                ],
                healthcheck: LocalDevHealthcheck(test: ["python", "-c", "print('ready')"], timeoutSeconds: 7)
            )
        ],
        jobs: [
            LocalDevJob(
                name: "migrate",
                image: "mirror.gcr.io/library/python:3.12-alpine",
                command: ["python", "migrate.py"],
                mounts: [
                    LocalDevMount(kind: .namedVolume, source: "api-cache", target: "/cache")
                ]
            )
        ],
        volumes: [
            LocalDevVolume(name: "api-cache")
        ]
    )

    let result = AppleNativePlanner().plan(project)

    XCTAssertEqual(result.runtimePlan.project.rawValue, "Demo Stack")
    XCTAssertEqual(result.runtimePlan.volumes, [VolumePlan(name: "api-cache")])
    XCTAssertEqual(result.runtimePlan.services.map(\.name), ["api", "migrate"])
    XCTAssertEqual(result.runtimePlan.services.map(\.kind), [.service, .oneOffJob])
    XCTAssertEqual(result.runtimePlan.services[0].command, ["/bin/sh", "-ec", "python", "app.py"])
    XCTAssertEqual(result.runtimePlan.services[0].ports, [PortMapping(hostPort: 18080, containerPort: 8080)])
    XCTAssertFalse(result.runtimePlan.hasBlockingDiagnostics)
}
```

- [x] **Step 2: Run the focused test and verify it fails before implementation**

Run:

```bash
swift test --filter RuntimeContractTests/testAppleNativePlannerPreservesCurrentRuntimePlanShape
```

Expected result before implementation: fail to compile because
`AppleNativePlanner` does not exist.

### Phase 2: Planner Boundary

- [x] **Step 1: Create the planner API**

Create `Sources/ContainerComposeAdapter/AppleNativePlanner.swift` with SPDX
headers and this public boundary:

```swift
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Burak Karahan

import Foundation

public struct AppleNativePlanner: Sendable {
    public init() {}

    public func plan(_ project: LocalDevProject) -> AppleNativePlannerResult {
        var diagnostics = project.diagnostics
        let support = AppleNativeSupportMatrix(project: project)
        diagnostics.append(contentsOf: support.diagnostics)

        let servicePlans = project.services.map { service in
            service.runtimeServicePlan(diagnostics: &diagnostics)
        }
        let jobPlans = project.jobs.map { job in
            job.runtimeServicePlan(diagnostics: &diagnostics)
        }
        let volumePlans = project.volumes.compactMap { volume in
            volume.runtimeVolumePlan(diagnostics: &diagnostics)
        }
        let runtimePlan = RuntimePlan(
            project: ProjectName(project.name),
            services: servicePlans + jobPlans,
            volumes: volumePlans,
            diagnostics: diagnostics
        )

        return AppleNativePlannerResult(
            runtimePlan: runtimePlan,
            support: support,
            diagnostics: diagnostics
        )
    }
}

public struct AppleNativePlannerResult: Equatable, Sendable {
    public let runtimePlan: RuntimePlan
    public let support: AppleNativeSupportMatrix
    public let diagnostics: [Diagnostic]
}
```

- [x] **Step 2: Move the existing normalization helpers behind the planner**

Move the current `fileprivate` runtime mapping methods from
`LocalDevProject.swift` into `AppleNativePlanner.swift` as private extensions
on `LocalDevService`, `LocalDevJob`, `LocalDevVolume`, `LocalDevMount`,
`LocalDevPort`, `[LocalDevPort]`, `[LocalDevMount]`,
`[LocalDevDependency]`, `LocalDevDependencyCondition`, and `Diagnostic`.

Keep behavior equivalent for:

```swift
LocalDevService.runtimeServicePlan(diagnostics:)
LocalDevJob.runtimeServicePlan(diagnostics:)
LocalDevVolume.runtimeVolumePlan(diagnostics:)
LocalDevMount.runtimeMountPlan(diagnostics:owner:)
LocalDevPort.runtimePortMapping(diagnostics:owner:)
Dictionary<String, String>.runtimeEnvironment
```

- [x] **Step 3: Preserve the old compatibility wrapper**

Replace `LocalDevProject.runtimePlan()` in
`Sources/ContainerComposeAdapter/LocalDevProject.swift` with:

```swift
public func runtimePlan() -> RuntimePlan {
    AppleNativePlanner().plan(self).runtimePlan
}
```

- [x] **Step 4: Run the focused bridge test**

Run:

```bash
swift test --filter RuntimeContractTests/testAppleNativePlannerPreservesCurrentRuntimePlanShape
```

Expected result after this phase: pass.

### Phase 3: Support Matrix And Diagnostics

- [x] **Step 1: Add support-matrix types**

Add these types to `AppleNativePlanner.swift`:

```swift
public enum AppleNativeSupportStatus: String, Codable, Equatable, Sendable {
    case supported
    case supportedWithSafetyChecks = "supported-with-safety-checks"
    case preservedIntent = "preserved-intent"
    case unsupported
}

public struct AppleNativeSupportEntry: Codable, Equatable, Sendable {
    public let feature: String
    public let status: AppleNativeSupportStatus
    public let diagnosticCode: String?

    public init(feature: String, status: AppleNativeSupportStatus, diagnosticCode: String? = nil) {
        self.feature = feature
        self.status = status
        self.diagnosticCode = diagnosticCode
    }
}

public struct AppleNativeSupportMatrix: Codable, Equatable, Sendable {
    public let entries: [AppleNativeSupportEntry]
    public let diagnostics: [Diagnostic]
}
```

- [x] **Step 2: Implement project-derived matrix evaluation**

Add an initializer that inspects `LocalDevProject` and emits diagnostics for
runtime-relevant fields that are not executable yet. Use these diagnostic
codes:

```text
unsupported-apple-native-env-file
preserved-apple-native-route-intent
preserved-apple-native-secret-intent
preserved-apple-native-config-intent
preserved-apple-native-network-intent
preserved-apple-native-restart-policy
unsupported-apple-native-job-allow-failure
```

Keep `build`, dynamic ports, invalid mount sources, tmpfs mounts, and non-named
project volumes in the existing normalization diagnostics so old assertions
remain meaningful.

- [x] **Step 3: Add a failing diagnostics test**

Add this test to `RuntimeContractTests.swift`:

```swift
func testAppleNativePlannerReportsCompatibilityDiagnosticsForPreservedIntent() {
    let project = LocalDevProject(
        id: "compat",
        name: "Compat",
        services: [
            LocalDevService(
                name: "api",
                image: "mirror.gcr.io/library/python:3.12-alpine",
                envFiles: [".env"],
                aliases: ["api.local"],
                restartPolicy: .always
            )
        ],
        jobs: [
            LocalDevJob(
                name: "seed",
                image: "mirror.gcr.io/library/python:3.12-alpine",
                completionPolicy: .allowFailure
            )
        ],
        networks: [
            LocalDevNetwork(name: "default", aliases: ["api"])
        ],
        routes: [
            LocalDevRoute(name: "api", host: "api.local", targetService: "api", targetPort: 8080)
        ],
        secrets: [
            LocalDevSecret(name: "api-token", environmentKey: "API_TOKEN")
        ],
        configs: [
            LocalDevConfig(name: "api-config", environmentKey: "APP_CONFIG")
        ]
    )

    let result = AppleNativePlanner().plan(project)
    let codes = Set(result.diagnostics.map(\.code))

    XCTAssertTrue(codes.contains("unsupported-apple-native-env-file"))
    XCTAssertTrue(codes.contains("preserved-apple-native-route-intent"))
    XCTAssertTrue(codes.contains("preserved-apple-native-secret-intent"))
    XCTAssertTrue(codes.contains("preserved-apple-native-config-intent"))
    XCTAssertTrue(codes.contains("preserved-apple-native-network-intent"))
    XCTAssertTrue(codes.contains("preserved-apple-native-restart-policy"))
    XCTAssertTrue(codes.contains("unsupported-apple-native-job-allow-failure"))
    XCTAssertTrue(result.runtimePlan.hasBlockingDiagnostics)
}
```

- [x] **Step 4: Run the focused diagnostics test**

Run:

```bash
swift test --filter RuntimeContractTests/testAppleNativePlannerReportsCompatibilityDiagnosticsForPreservedIntent
```

Expected result after implementation: pass.

### Phase 4: Fixture-derived Dry-run Contract

- [x] **Step 1: Update fixture tests to call the planner explicitly**

In `Tests/ContainerComposeAdapterTests/ComposeFrontendTests.swift`, replace
direct bridge calls in dry-run tests:

```swift
let plan = project.runtimePlan()
```

with:

```swift
let plannerResult = AppleNativePlanner().plan(project)
let plan = plannerResult.runtimePlan
```

Assert that the public fixtures have no planner diagnostics:

```swift
XCTAssertEqual(plannerResult.diagnostics, [])
```

- [x] **Step 2: Keep the LinuxPod dry-run action shape stable**

Preserve the existing assertion order for the backend-shaped fixture:

```text
addContainer db
addContainer migrate
addContainer seed
addContainer api
startContainer db
waitForReadiness db
runJob migrate
waitForReadiness migrate
runJob seed
waitForReadiness seed
startContainer api
waitForReadiness api
```

- [x] **Step 3: Run fixture-derived tests**

Run:

```bash
swift test --filter ComposeFrontendTests
```

Expected result: pass, with no runtime mutation.

### Phase 5: Documentation And Lifecycle Tracking

- [x] **Step 1: Update README only if implementation changes user-visible behavior**

If implementation adds a new public command, flag, or rendered support matrix,
update `README.md`. If the work only adds internal planner types and tests, do
not edit README.

- [x] **Step 2: Update plan index to the final state**

When implementation is complete and verified, update
`docs/plans/index.md` so this plan is either:

- `ready-for-verification` if Swift tests pass but review is still desired; or
- moved to `docs/plans/completed/` and recorded in
  `docs/plans/completed/index.md` if the objective is fully met.

If a durable compatibility gap is accepted, add a note under
`docs/plans/notes/` and link it from `docs/plans/notes/index.md`.

## Verification Gates

Planning-only creation of this file must pass:

```bash
git diff --check
```

Implementation of this plan must pass:

```bash
swift test
git diff --check
```

Implementation evidence must include:

- Direct `AppleNativePlanner` tests for existing bridge shape.
- Support-matrix or diagnostics tests for preserved/unsupported intent.
- Fixture-derived dry-run tests for `simple-web` and `backend-shaped`.
- Redaction assertion proving secret-looking values do not appear in rendered
  dry-run output.
- Confirmation that no runtime-mutating LinuxPod command was run.

Runtime smoke is not required for this plan. Product benchmarks are explicitly
deferred until later roadmap stages.

## Risks And Mitigations

Risk: the planner becomes only a rename of `LocalDevProject.runtimePlan()`.

Mitigation: require direct planner tests, support matrix output, and diagnostics
for currently ignored LocalDevProject fields.

Risk: diagnostics become too noisy for fields that are preserved as future
intent.

Mitigation: use `preserved-intent` status and warning severity where execution
can still be safely inspected; use blocking severity only where the rendered
runtime plan would mislead users.

Risk: moving helper methods breaks existing callers.

Mitigation: keep `LocalDevProject.runtimePlan()` as a delegation wrapper and
run the full Swift test suite.

Risk: support matrix wording drifts into runtime or benchmark claims.

Mitigation: describe support as planner compatibility only, not proof of
runtime performance or replacement viability.

## Dependencies And Ownership Boundaries

- Owner: `tools/apple-container-compose-adapter`.
- Child repo changes stay inside this repository.
- Do not update the parent EMSI monorepo submodule pointer unless explicitly
  asked.
- If a parent pointer update is explicitly requested later, commit and push the
  child repository first, then update the parent gitlink.
- Do not create, switch, rename, or delete branches.
- Keep source code identifiers, comments, tests, docs, and plan names in
  English.
- Preserve `AGPL-3.0-or-later` headers for new Swift source files.

## Affected Files Or Docs

Expected implementation files:

- `Sources/ContainerComposeAdapter/AppleNativePlanner.swift`
- `Sources/ContainerComposeAdapter/LocalDevProject.swift`
- `Tests/ContainerComposeAdapterTests/RuntimeContractTests.swift`
- `Tests/ContainerComposeAdapterTests/ComposeFrontendTests.swift`
- `docs/plans/index.md`

Possible implementation files:

- `README.md`
- `docs/plans/completed/index.md`
- `docs/plans/notes/index.md`
- `docs/plans/notes/2026-06-12-apple-native-planner-compatibility-gaps.md`

## Rollback Or Recovery Notes

If the planner extraction grows too large, keep the compatibility wrapper in
`LocalDevProject.runtimePlan()` and add only `AppleNativePlanner` as a facade in
the first pass. Capture the larger extraction as a follow-up note.

If diagnostics create broad test churn, keep the fixture path diagnostics-free
and limit new diagnostics to one focused compatibility test until the support
matrix is reviewed.

If the support matrix design feels too heavy, keep the public result shape but
store entries as simple feature/status/code records. Do not add a separate
schema generator in this stage.

## Execution Prompt

Use this prompt to execute the plan:

```text
You are working in MarlonJD/apple-container-compose-adapter at /Users/marlonjd/Developer/monorepos/emsi_monorepo/tools/apple-container-compose-adapter.

Execute docs/plans/2026-06-12-apple-native-planner-compatibility-contract-plan.md only. Use emsi-workflows:emsi-task-router, emsi-workflows:emsi-verification-gate, superpowers:test-driven-development, and superpowers:verification-before-completion. Read AGENTS.md, README.md, docs/apple-native-local-dev-orchestrator.md, docs/localdevproject-ir.md, docs/benchmark-and-metrics-plan.md, docs/plans/index.md, docs/plans/2026-06-12-apple-native-orchestrator-roadmap-plan.md, Sources/ContainerComposeAdapter/ComposeFrontend.swift, Sources/ContainerComposeAdapter/LocalDevProject.swift, Sources/ContainerComposeAdapter/SamplePlans.swift, Sources/ContainerComposeAdapter/LinuxPodBackend.swift, Tests/ContainerComposeAdapterTests/ComposeFrontendTests.swift, and Tests/ContainerComposeAdapterTests/RuntimeContractTests.swift before editing.

Implement the Stage 2 AppleNativePlanner compatibility contract: add a planner boundary between LocalDevProject and RuntimePlan, keep LocalDevProject.runtimePlan() as a delegating compatibility wrapper, add a support matrix and structured diagnostics for unsupported or preserved-intent LocalDevProject fields, and update fixture-derived dry-run tests so action shape and redaction remain stable. Keep all behavior dry-run/no-runtime-mutation.

Do not implement runtime mutation, Kubernetes parsing, persistent LinuxPod hotplug, rootfs-cache optimization, writable layers, Docker-compatible backends, registry login, host DNS mutation, or product benchmarks. Do not create/switch branches. Do not update the parent monorepo submodule pointer unless explicitly asked; if parent integration is later requested, commit and push the child repo first.

Verification required before claiming completion: swift test, git diff --check, focused AppleNativePlanner diagnostics/action-shape tests, fixture-derived dry-run tests for simple-web and backend-shaped, and docs/plans/index.md updated to the actual final state.
```
