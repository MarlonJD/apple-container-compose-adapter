# Container Compose Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-06-11
**Owner subtree:** `tools/apple-container-compose-adapter`
**Goal:** Build Container Compose Adapter as a macOS developer tool that reads Docker Compose-style YAML intent and translates it into the closest safe, practical execution through Apple's `container` CLI without claiming to be an official or complete Docker Compose replacement. The project must eventually support an OrbStackless daily development path for stacks that fit its documented compatibility subset.
**Architecture:** Keep Compose parsing, compatibility planning, command rendering, runtime execution, state tracking, build orchestration, and readiness gating as separate modules so behavior can be tested without mutating the host. Make dry-run output the primary contract before enabling real runtime actions.
**Tech stack proposal:** Swift Package Manager CLI, XCTest, Foundation `Process` for argv-based execution, and an AGPL-compatible structured YAML parser after dependency license review. No implementation dependency is added by this planning artifact.

---

## Objective

Implement Container Compose Adapter as a deterministic, testable compatibility adapter for local macOS development:

- Read Docker Compose-style YAML files and `.env` inputs as structured data.
- Normalize service intent into a project-scoped internal model.
- Diagnose unsupported or risky Compose features explicitly.
- Produce an inspectable execution plan and dry-run rendering of Apple `container` CLI commands.
- Execute the verified subset through a narrow runtime boundary only after the dry-run and safety rules are in place.
- Document supported, partially supported, and unsupported Compose features so users understand that the project is an adapter, not an official Apple or Docker Compose replacement.

## Scope

This plan covers the first complete implementation path for a local developer workflow:

- CLI project foundation and command routing.
- Compose file discovery with `compose.yaml`, `compose.yml`, `docker-compose.yaml`, and explicit `--file`.
- A useful subset of Compose services:
  - `image`
  - `build.context`, `build.dockerfile`, and build args for local images
  - `command`
  - `entrypoint`
  - `environment`
  - `env_file`
  - `ports`
  - bind mounts
  - named volumes
  - default project network and service-name connectivity
  - host service access diagnostics and documented host-gateway behavior
  - profiles
  - `depends_on` ordering
  - `depends_on` conditions for `service_started`, `service_healthy`, and `service_completed_successfully`
  - `healthcheck` parsing and readiness polling or a documented faithful emulation strategy
  - one-off `run`
  - `logs`
  - `status`
  - explicit cleanup through `down`
- Backend-shaped OrbStackless smoke coverage: database, migration job, seed job, API service, named volume, health gate, published API port, logs, status, and cleanup.
- Parser, planner, renderer, and executor tests.
- Dry-run and JSON plan output.
- Safety diagnostics for broad mounts, secret-looking environment values, destructive cleanup, and unsupported privileged host access.
- Documentation updates for README, compatibility scope, examples, and known limitations.

## Non-goals / Out Of Scope

- Claiming full Docker Compose parity.
- Claiming Apple provides a native `container compose` command.
- Implementing Docker Engine APIs.
- Supporting production orchestration, Swarm, Kubernetes, or remote hosts.
- Implementing all Compose Specification fields in the first release.
- Silently ignoring unsupported Compose features.
- Removing Docker, Docker Compose, Docker Desktop, or OrbStack as documented fallback paths before the OrbStackless readiness gate passes.
- Mutating Docker Hub, Keychain credentials, host DNS, global networking, or host container state outside resources created and labeled by this adapter.
- Editing EMSI application, backend, infra, or platform files from this repository.
- Updating the parent EMSI monorepo submodule pointer unless explicitly requested after this repository has its own completed commit.
- Creating, switching, renaming, deleting, or otherwise changing branches.

## Assumptions

- Docker Compose behavior is the compatibility reference.
- Apple's `container` CLI is the runtime target.
- "OrbStackless daily development" means the documented smoke path passes without Docker, Docker Compose, Docker Desktop, or OrbStack running. Docker/OrbStack may remain a fallback until that gate is proven.
- The first implementation should optimize for Apple silicon and recent macOS developer machines.
- The current planning environment may not have `container` installed; execution must therefore support skipped runtime smoke evidence while still requiring parser, planner, renderer, and CLI tests.
- Runtime capabilities and CLI flags should be discovered from the installed `container` binary during implementation rather than hardcoded from memory.
- A structured YAML parser is required; ad hoc string parsing is not acceptable for Compose files.
- Any third-party dependency must be reviewed for AGPL-3.0-or-later compatibility before being added.
- New source files should include SPDX and copyright headers when local style allows:
  - `SPDX-License-Identifier: AGPL-3.0-or-later`
  - `Copyright (C) 2026 Burak Karahan`

## Architecture Proposal

Use a layered architecture with one-way dependencies:

```text
CLI
  -> ComposeInputResolver
  -> ComposeParser
  -> ComposeNormalizer
  -> CompatibilityAnalyzer
  -> PlanBuilder
  -> RuntimeCommandRenderer
  -> RuntimeExecutor
```

### Main Units

- `CLI`: Parses command names, global flags, output format, project name, profiles, service filters, and execution mode.
- `ComposeInputResolver`: Finds compose files, `.env`, explicit env files, project root, and working directory.
- `ComposeParser`: Parses YAML into structured raw Compose documents.
- `ComposeNormalizer`: Applies project defaults, environment interpolation, service inheritance rules that are in scope, and profile filtering.
- `CompatibilityAnalyzer`: Converts unsupported, partially supported, risky, or ignored features into diagnostics with severity and suggested workarounds.
- `PlanBuilder`: Produces an internal `ExecutionPlan` with services, volumes, ports, mounts, dependencies, readiness expectations, and cleanup actions.
- `RuntimeCommandRenderer`: Converts `ExecutionPlan` actions into Apple `container` argv arrays and stable dry-run text.
- `RuntimeExecutor`: Runs argv arrays through one narrow boundary, captures stdout/stderr/exit status, redacts sensitive values, and never shells out through string concatenation.
- `StateStore`: Records adapter-owned resource identity and runtime metadata in a local generated state directory so cleanup only targets owned resources.
- `Diagnostics`: Shared structured diagnostics model for CLI text, JSON output, tests, and documentation examples.

### Data Flow

1. Resolve inputs from CLI flags and default Compose file names.
2. Parse YAML and env files into structured models.
3. Normalize Compose intent and apply profile/service selection.
4. Analyze compatibility and safety.
5. Build a project-scoped execution plan.
6. Render dry-run output.
7. Execute only when the command is documented, diagnostics are not blocking, and the user requested execution rather than plan-only output.

## CLI Command Surface Proposal

Use the product name "Container Compose Adapter" in documentation. Use a neutral binary name that does not imply an official Apple or Docker subcommand. Proposed binary: `container-compose-adapter`, with `cca` as a possible documented alias after install packaging exists.

### Global Flags

- `-f, --file <path>`: Compose file path. May be repeated once multi-file merge support exists; first release may accept one file and emit a clear diagnostic for repeated files.
- `-p, --project-name <name>`: Project name used for adapter labels and resource names.
- `--profile <name>`: Enable one Compose profile. Repeatable.
- `--env-file <path>`: Load additional env file before Compose interpolation.
- `--format text|json`: Output format for diagnostics, plans, and status.
- `--dry-run`: Render actions without runtime mutation.
- `--build`: Build local service images before `up` when supported by the compatibility subset.
- `--wait`: Wait for supported health/job readiness gates before returning from `up`.
- `--verbose`: Include capability discovery, resolved files, and command argv details.
- `--no-color`: Disable ANSI color.

### Commands

- `doctor`
  - No side effects.
  - Checks macOS architecture, `container` availability, `container system status` when available, version/capability snapshot, write access to adapter state directory, and known runtime limitations.
- `config`
  - No side effects.
  - Prints the normalized Compose model after env interpolation and profile filtering.
- `plan`
  - No side effects.
  - Prints compatibility diagnostics and the adapter execution plan.
- `up`
  - Creates/starts services for the supported subset.
  - Must support `--dry-run`.
  - Must support idempotent re-run behavior for adapter-owned resources.
  - Must support `--build` for supported local build definitions before OrbStackless readiness can pass.
  - Must support `--wait` for documented `depends_on` readiness gates before OrbStackless readiness can pass.
  - Should support `--detach` when runtime support is implemented.
  - Should refuse execution when blocking diagnostics exist.
- `down`
  - Stops/removes adapter-owned resources for a project.
  - Must support `--dry-run`.
  - Does not remove named volumes unless `--volumes` is explicitly passed.
- `status`
  - Shows adapter-owned service state and last known runtime state.
- `logs`
  - Streams or prints service logs for adapter-owned services.
- `run <service> [args...]`
  - Runs a one-off service command using the normalized service definition.
  - Must support `--dry-run`.
- `version`
  - Prints adapter version and detected Apple `container` version when available.

## Compose Feature Support Matrix

| Compose feature | First implementation status | Target adapter behavior | Diagnostic behavior |
| --- | --- | --- | --- |
| `services.<name>.image` | Supported | Pull/use image through Apple `container` runtime path when available | Blocking if missing with no supported build path |
| `services.<name>.build` | Required for OrbStackless readiness | Support `build.context`, `build.dockerfile`, `build.args`, deterministic local image tags, and `--build` for single-platform local builds when Apple `container` exposes a viable build path; otherwise provide a documented build bridge that does not require OrbStack | Blocking for local dev stacks that require build until implemented; warning only when an equivalent prebuilt `image` is supplied |
| `command` | Supported | Pass command argv/string to runtime command rendering | Warning when shell-specific parsing would be ambiguous |
| `entrypoint` | Supported | Render runtime entrypoint override when supported | Blocking if installed runtime lacks an equivalent |
| `environment` | Supported | Interpolate and pass env values as argv/env entries | Redact secret-looking values in logs and dry-run |
| `env_file` | Supported | Load files relative to Compose file directory | Blocking if file is missing; redact values |
| `.env` interpolation | Supported | Load default `.env` from project directory and apply Compose-style interpolation for in-scope operators | Blocking for invalid interpolation syntax |
| `ports` | Supported, TCP first | Publish host/container TCP ports when runtime supports it | Blocking for unsupported protocol or invalid mapping |
| `expose` | Limited | Keep as metadata unless runtime networking can use it | Warning that host publishing is not implied |
| Bind mounts | Supported with safety diagnostics | Validate host paths and render mounts as argv arrays | Warning for broad mounts such as `/`, `$HOME`, or credential directories; blocking when path does not exist unless create behavior is explicit |
| Named volumes | Supported, local only | Create or map adapter-owned local volumes/state | Warning for driver/options not supported |
| Anonymous volumes | Deferred | Avoid hidden host mutation in first release | Warning or blocking depending on command |
| `depends_on` short syntax | Supported | Start services in dependency order | Warning that readiness is not guaranteed without health support |
| `depends_on` conditions | Required for backend-shaped readiness | Emulate `service_started`, `service_healthy`, and `service_completed_successfully` through runtime status, exec probes, exit-code tracking, or a documented equivalent | Blocking for stacks that request conditions the adapter cannot enforce |
| `healthcheck` | Required for backend-shaped readiness | Parse Compose healthcheck fields, execute or emulate probes when possible, respect interval/timeout/retries/start_period within documented limits | Blocking when a selected service depends on an unenforceable health check |
| `profiles` | Supported | Filter services by active profile set | Blocking if selected service is inactive |
| `restart` | Limited | Preserve in plan metadata; map only if runtime has equivalent | Warning if not enforced |
| `working_dir` | Supported if runtime supports it | Render working directory override | Blocking if runtime lacks equivalent |
| `user` | Supported if runtime supports it | Render user override | Blocking or warning based on runtime capability |
| `labels` | Supported for adapter labels plus user labels when runtime supports it | Add adapter ownership labels and preserve user labels | Warning if user labels cannot be attached |
| `networks` | Required default network; limited custom networks | Provide project-scoped default network behavior with service-name connectivity. Custom drivers/options remain limited until proven. | Blocking if selected services cannot reach each other by service name; warning for custom drivers/options |
| `network_mode` | Unsupported first release | Do not mutate host network assumptions | Blocking |
| `extra_hosts`, `dns`, `hostname` | Limited | Support host service access only through a documented, tested host-gateway strategy; parse other fields for diagnostics until runtime behavior is verified | Warning or blocking based on runtime support |
| `secrets` / `configs` | Unsupported first release | Do not emulate by copying secret files silently | Blocking with documented workaround |
| `deploy` | Unsupported | Swarm/production settings out of scope | Warning if safely ignorable, blocking if user expects placement/resource behavior |
| `privileged`, `cap_add`, `devices` | Unsupported first release | Avoid host privilege escalation | Blocking |
| `platform` | Limited | Prefer local Apple silicon compatible images; pass platform only if runtime supports it | Warning for non-native platform expectations |
| `pull_policy` | Deferred | Use runtime default initially | Warning if explicit policy cannot be honored |
| `container_name` | Limited | Prefer adapter project-scoped names; allow only when safe and non-conflicting | Warning or blocking for unsafe collisions |
| Multi-file merge | Deferred | Accept a single file in first release | Blocking with message that merge support is not implemented |
| Extension fields `x-*` | Supported as ignored metadata | Parse and preserve enough for diagnostics; do not execute | No warning unless referenced by unsupported feature |

## Apple Container Runtime Integration Strategy

- Build a `RuntimeCapabilities` snapshot at startup for commands that need runtime knowledge.
- Discover capabilities through local commands such as `container --help`, subcommand help, version output, and `container system status` when the binary exists.
- Keep capability discovery no-side-effect.
- Represent every runtime operation as an argv array, not a shell string.
- Render both:
  - a human-readable shell-escaped command preview;
  - a machine-readable JSON plan with argv arrays and redacted values.
- Add adapter-owned labels and deterministic names for project, service, and one-off run resources when the runtime supports metadata.
- Use a local state store only for adapter-owned metadata needed to avoid accidental cleanup of unrelated containers.
- `down` must target adapter-owned resources by project identity and must not delete volumes unless `--volumes` is explicit.
- Model image build actions separately from service start actions so `--build`, rebuild detection, and idempotent `up` behavior are testable.
- Model project network creation, service-name resolution, host service access, and port publishing explicitly. Do not treat successful single-container execution as evidence that multi-service networking works.
- Model readiness gates explicitly: started, healthy, completed-successfully, failed, timed-out, and skipped. `up --wait` must return non-zero when a required gate fails or times out.
- Runtime execution should be introduced only after parser, planner, renderer, and dry-run tests exist.
- If Apple `container` is unavailable, `doctor` and mutating commands should return clear diagnostics while parser/planner tests remain runnable.

## Parser / Planner / Executor Separation

### Parser Responsibilities

- Parse YAML into raw Compose documents.
- Preserve source locations when practical for diagnostics.
- Parse `.env` and explicit env files.
- Support the in-scope interpolation operators needed by common Compose files.
- Reject malformed YAML and invalid data types with actionable errors.

### Planner Responsibilities

- Normalize the Compose project.
- Apply profile and service selection.
- Analyze feature compatibility.
- Build an `ExecutionPlan` independent of Apple `container` command syntax.
- Sort services by dependency order.
- Attach diagnostics to plan nodes rather than printing directly.
- Decide whether a command has blocking diagnostics.

### Executor Responsibilities

- Execute only rendered argv arrays.
- Centralize process spawning, timeouts, stdout/stderr capture, cancellation, and redaction.
- Never interpret Compose values as shell fragments.
- Surface runtime failures with command context, exit code, and redacted output.
- Keep dry-run as a renderer path that does not call the executor.

## Dry-run Behavior

Dry-run is the main safety and compatibility contract.

- `plan` is always no-side-effect.
- All mutating commands support `--dry-run`.
- Dry-run output must include:
  - resolved project name;
  - resolved Compose files and env files;
  - enabled profiles;
  - selected services;
  - compatibility diagnostics grouped by severity;
  - planned resources;
  - ordered actions;
  - rendered Apple `container` argv arrays;
  - redacted environment and secret-looking values;
  - cleanup behavior for `down`.
- Text output should be stable enough for humans.
- JSON output should be stable enough for tests and future tooling.
- Blocking diagnostics should produce a non-zero exit code without executing runtime commands.
- Dry-run must not pull images, create containers, create volumes, start services, stop services, remove resources, or write runtime state beyond optional command diagnostics that are documented as no-side-effect.

## Safety / Security Rules

- Treat Compose files as untrusted input.
- Avoid command injection by passing arguments as arrays to `Process`.
- Do not use shell concatenation to execute runtime commands.
- Redact environment values whose keys match secret-like patterns such as `PASSWORD`, `TOKEN`, `SECRET`, `KEY`, `CREDENTIAL`, `PRIVATE`, `AUTH`, or `SESSION`.
- Redact env file values in dry-run, logs, diagnostics, and failed command summaries.
- Validate bind mount host paths before rendering runtime commands.
- Warn on broad host mounts such as `/`, `$HOME`, `/Users`, `~/.ssh`, `.docker`, Keychain-related paths, cloud credential directories, and project-external mounts.
- Block or require an explicit documented override for mounts that would expose credential directories.
- Never remove containers, networks, volumes, or generated state that are not owned by the adapter's project identity.
- Keep destructive behavior explicit:
  - `down` removes adapter-owned containers/network state only.
  - `down --volumes` is required for adapter-owned named volumes.
  - no command removes arbitrary host files.
- Do not mutate Docker Hub, registries, Apple `container` registries, Keychain credentials, host DNS, or global networking unless a future documented command explicitly does so and the user requested it.
- Include safety diagnostics in JSON output so automated tests can assert them.

## Test Strategy

Use test coverage to lock the compatibility contract before runtime mutation.

### Unit Tests

- Compose file discovery and precedence.
- YAML parsing success and failure cases.
- `.env` and `env_file` parsing.
- Environment interpolation:
  - default values;
  - required values;
  - escaped variables;
  - missing variables.
- Service normalization:
  - build;
  - image;
  - command;
  - entrypoint;
  - environment;
  - ports;
  - volumes;
  - networks;
  - profiles;
  - depends_on.
- Build plan generation, deterministic local image tagging, and rebuild/idempotency decisions.
- Compatibility diagnostics for every matrix row marked limited, deferred, or unsupported.
- Dependency ordering and cycle detection.
- Readiness gate planning for `service_started`, `service_healthy`, and `service_completed_successfully`.
- Project name sanitization and resource naming.
- Secret redaction.
- Safety diagnostics for broad mounts.

### Golden / Snapshot Tests

- `config --format json` for fixture Compose files.
- `plan --format json` for fixture Compose files.
- `up --dry-run` text output for common single-service and multi-service stacks.
- `up --dry-run --build --wait` output for a backend-shaped stack with database, migrate job, seed job, API, health gates, and named volume.
- `down --dry-run` output with and without `--volumes`.

### Executor Boundary Tests

- Mock runtime executor receives argv arrays.
- No shell string is executed.
- Runtime stdout/stderr are captured and redacted.
- Non-zero runtime exits become structured diagnostics.
- Missing `container` binary produces a clear diagnostic.

### CLI Tests

- Unknown command and invalid flag diagnostics.
- `doctor` with missing runtime.
- Service selection.
- Profile selection.
- JSON output validity.
- Exit codes for success, warnings, blocking diagnostics, and runtime errors.

### Suggested Verification Commands

After the initial Swift package exists:

```bash
swift test
```

After CLI packaging or executable targets exist, add command-specific smoke tests through the package test runner rather than relying only on manual shell transcripts.

## Runtime Smoke Verification Strategy

Runtime smoke verification must be gated by environment availability and explicit execution intent.

### Always Required Before Runtime Smoke

- Parser/planner/renderer tests pass.
- `doctor` reports the installed `container` binary and system status.
- `up --dry-run` for the smoke fixture shows expected commands.
- `down --dry-run` for the smoke project shows cleanup limited to adapter-owned resources.

### Smoke Fixtures

Create a minimal public-image example once runtime execution is implemented:

- `examples/simple-web/compose.yaml`
- one service using a small HTTP image;
- one high host port to avoid common conflicts;
- no private data;
- no host credential mounts.

Create a backend-shaped fixture before claiming OrbStackless readiness:

- `examples/backend-shaped/compose.yaml`
- one database service with a named volume and a health check;
- one migrate job that must complete successfully after the database is healthy;
- one seed job that must complete successfully after migration;
- one API-like HTTP service that depends on the completed jobs and exposes a high host port;
- no private data, private registry, Docker socket, host credential mounts, or project-external bind mounts;
- explicit expected `up --build --wait`, `status`, `logs`, `down`, and `down --volumes` behavior.

### Runtime Steps

When `container` is available:

1. Run `container system status`.
2. Run `container-compose-adapter doctor`.
3. Run `container-compose-adapter -f examples/simple-web/compose.yaml -p cca-smoke up --dry-run`.
4. Run the documented execute form for `up`.
5. Verify the service is reachable on the published host port.
6. Run `container-compose-adapter -p cca-smoke status`.
7. Run `container-compose-adapter -p cca-smoke logs`.
8. Run `container-compose-adapter -p cca-smoke down --dry-run`.
9. Run the documented execute form for `down`.
10. Confirm adapter-owned resources are removed and unrelated runtime resources remain untouched.

### OrbStackless Daily Development Readiness Gate

Do not describe the adapter as able to replace OrbStack for daily development
until this gate passes on a macOS host with Docker, Docker Compose, Docker
Desktop, and OrbStack stopped or unavailable:

- `doctor` confirms Apple `container` is available and Docker/OrbStack are not required for the selected runtime path.
- `build.context`, `build.dockerfile`, and build args work for at least one local image in the backend-shaped fixture, or the plan documents a non-OrbStack build bridge with the same no-Docker constraint.
- Default project networking supports service-name connectivity for API-to-database style traffic.
- Published ports expose the API-like service on `localhost`.
- Host service access behavior is documented and tested or explicitly diagnosed as unsupported.
- `depends_on` conditions for `service_healthy` and `service_completed_successfully` are enforced or faithfully emulated.
- Named volumes persist across `up`, `down`, and repeated `up`; they are removed only by `down --volumes`.
- `up --build --wait` is idempotent and does not duplicate resources on repeated runs.
- `status`, `logs`, `run`, `down`, and `down --volumes` work after real runtime execution.
- The backend-shaped fixture completes a full cycle: `up --build --wait`, HTTP readiness check, `status`, `logs`, one-off `run`, `down`, repeated `up`, and final `down --volumes`.
- Cleanup proves adapter-owned resources are removed and unrelated Apple `container` resources remain untouched.

If `container` is unavailable, record that runtime smoke verification was not run and include the `doctor` diagnostic as evidence.

## Documentation Milestones

- Update `README.md` with:
  - product positioning as a compatibility adapter;
  - not affiliated with Apple or Docker;
  - install/build instructions;
  - first supported command examples;
  - dry-run-first workflow;
  - runtime smoke caveats.
- Add `docs/compatibility.md` with the support matrix and diagnostics policy.
- Add `docs/runtime-apple-container.md` with:
  - Apple `container` version assumptions;
  - tested macOS versions;
  - capability discovery strategy;
  - OrbStackless readiness gate evidence;
  - host service access behavior;
  - service-name networking behavior;
  - known limitations.
- Add `docs/security.md` with:
  - untrusted Compose input model;
  - redaction behavior;
  - mount safety diagnostics;
  - cleanup ownership rules.
- Add examples under `examples/` only when the corresponding behavior is tested.
- Update this plan and `docs/plans/index.md` as phases move from active to ready-for-verification or completed.

## Phased Implementation Plan

### Phase 0: Baseline, Toolchain, And Capability Discovery

- [ ] Confirm the implementation stack after reading `AGENTS.md`, `CLAUDE.md`, `README.md`, and `docs/plans/index.md`.
- [ ] Inspect whether an Apple `container` binary is installed with no-side-effect commands.
- [ ] Create the minimal package/CLI scaffold only after stack confirmation.
- [ ] Add license headers to new source files where local style allows.
- [ ] Add an initial `doctor` command that can report missing `container`.
- [ ] Add initial tests for `doctor` missing-runtime behavior.
- [ ] Update `docs/plans/index.md` next todo after this phase.

### Phase 1: Compose Input Resolution And Structured Parsing

- [ ] Add Compose file discovery and explicit `--file`.
- [ ] Add `.env` and `--env-file` resolution.
- [ ] Add structured YAML parsing for a single Compose file.
- [ ] Add typed raw model fields for the first support matrix subset.
- [ ] Add parsing tests for valid and invalid fixtures.
- [ ] Add diagnostics for unsupported multi-file merge attempts.

### Phase 2: Normalization And Compatibility Diagnostics

- [ ] Implement environment interpolation for the in-scope Compose operators.
- [ ] Normalize services, project name, profiles, env, ports, volumes, and dependencies.
- [ ] Implement the support matrix as data-driven compatibility rules.
- [ ] Add diagnostics severities: info, warning, blocking.
- [ ] Add tests for every unsupported or limited feature listed in the matrix.
- [ ] Add secret redaction tests.

### Phase 3: Execution Plan And Dry-run Rendering

- [ ] Define `ExecutionPlan`, service actions, resource actions, and cleanup actions independent of runtime syntax.
- [ ] Define image build actions independent of runtime syntax.
- [ ] Define readiness gate actions for started, healthy, completed-successfully, failed, timed-out, and skipped states.
- [ ] Build dependency-ordered start plans.
- [ ] Build `down` cleanup plans that target only adapter-owned resources.
- [ ] Add text and JSON renderers.
- [ ] Add golden tests for `plan`, `up --dry-run`, `up --dry-run --build --wait`, and `down --dry-run`.
- [ ] Ensure blocking diagnostics prevent execution.

### Phase 4: Runtime Command Rendering

- [ ] Add `RuntimeCapabilities` discovery from installed Apple `container` help/status/version output.
- [ ] Add command renderers from execution plan actions to argv arrays.
- [ ] Add tests using fixture capabilities rather than requiring a local runtime.
- [ ] Add diagnostics for runtime capability gaps.
- [ ] Keep all rendered commands visible in dry-run output.

### Phase 5: Runtime Executor And Safe `up` / `down`

- [ ] Add the narrow `RuntimeExecutor` boundary using argv arrays.
- [ ] Add process timeout, cancellation, stdout/stderr capture, and redaction.
- [ ] Implement execution for the smallest safe `up` path after dry-run tests pass.
- [ ] Implement execution for `down` against adapter-owned resources only.
- [ ] Implement idempotent re-run behavior for adapter-owned resources.
- [ ] Add executor mock tests and missing-runtime tests.
- [ ] Document all destructive behavior before enabling it.

### Phase 6: Build, Networking, And Readiness Gates

- [ ] Implement or bridge local image builds for supported `build` definitions without requiring OrbStack.
- [ ] Add deterministic local image tagging and rebuild decisions for `--build`.
- [ ] Implement project-scoped default networking and service-name connectivity.
- [ ] Add host service access diagnostics and documented host-gateway behavior.
- [ ] Implement or faithfully emulate `depends_on` `service_healthy` and `service_completed_successfully`.
- [ ] Implement `up --wait` timeout and failure behavior.
- [ ] Add tests and dry-run snapshots for a backend-shaped database/job/API stack.

### Phase 7: Developer Workflow Commands

- [ ] Implement `config`.
- [ ] Implement `status`.
- [ ] Implement `logs`.
- [ ] Implement `run <service> [args...]`.
- [ ] Add profile and service selection tests across commands.
- [ ] Add JSON output tests for automation-friendly workflows.

### Phase 8: Examples, Documentation, And Runtime Smoke

- [ ] Add tested examples under `examples/`.
- [ ] Add `examples/backend-shaped/compose.yaml` only after the planned behavior is covered by dry-run tests.
- [ ] Update README and dedicated docs.
- [ ] Run `swift test` or the final project-equivalent test command.
- [ ] Run dry-run smoke for examples.
- [ ] Run real Apple `container` smoke only when the runtime is installed and the user has requested runtime mutation.
- [ ] Run OrbStackless readiness smoke only when Docker/OrbStack are stopped or unavailable and Apple `container` is available.
- [ ] Record skipped runtime evidence if `container` is unavailable.

### Phase 9: Completion, Plan Lifecycle, And Release Readiness

- [ ] Confirm all completion criteria below are met or documented as gaps.
- [ ] Confirm the OrbStackless Daily Development Readiness Gate is passed before saying OrbStack is no longer required for daily development.
- [ ] Update `docs/plans/index.md` to `ready-for-verification` or complete the plan lifecycle.
- [ ] If the objective is complete, move this plan to `docs/plans/completed/` and update `docs/plans/completed/index.md`.
- [ ] If remaining work exists, keep this plan active with only the next concrete todo in `docs/plans/index.md`.
- [ ] Commit only if explicitly requested; if committing, commit inside this repository before any parent monorepo submodule pointer update.

## Risks And Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Apple `container` CLI flags or behavior change | Rendered commands may drift | Capability discovery, fixture-based renderer tests, docs with tested versions |
| Users expect full Docker Compose parity | Surprising unsupported behavior | Clear positioning, compatibility matrix, blocking diagnostics for unsupported features |
| Unsafe host mounts expose secrets | Local credential leakage | Mount validation, warnings/blocks for credential paths, explicit overrides only if documented |
| Command injection through Compose values | Host command execution risk | argv arrays only, no shell concatenation, executor boundary tests |
| Secret values leak into dry-run or logs | Credential exposure | Central redaction utility with tests across text and JSON output |
| Runtime cleanup deletes unrelated resources | Data loss | Adapter-owned labels/names, state store, dry-run cleanup previews, `--volumes` explicit |
| YAML parser dependency conflicts with AGPL | Licensing issue | License review before dependency addition; document dependency license |
| Runtime unavailable in CI or local environment | Incomplete verification | Split tests into no-runtime parser/planner/renderer tests and optional runtime smoke |
| Compose networking cannot be matched exactly | Broken local stacks | Limited networking scope, explicit diagnostics, documented workarounds |
| Apple `container` cannot build local Dockerfiles in the needed shape | OrbStackless path cannot support real local stacks | Capability discovery, non-OrbStack build bridge research, blocking diagnostics until solved |
| Service-name DNS or host-gateway behavior cannot be matched | API/database and host dependency workflows fail | Backend-shaped smoke, documented fallback diagnostics, do not claim OrbStackless readiness until proven |
| Health and job completion checks are only partially observable | `up --wait` may return too early | Explicit readiness state model, timeout behavior, probe execution strategy, blocking diagnostics for unenforceable gates |
| Multi-file Compose projects are common | Early adopter friction | Block repeated `--file` with clear message; add merge support as a follow-up plan |

## Dependencies

- macOS developer environment.
- Swift toolchain if the proposed Swift Package Manager path is accepted.
- Apple `container` CLI for runtime smoke and real execution.
- Apple `container` build, network, volume, exec/status/log, and port publishing capabilities, verified through no-side-effect discovery before use.
- Structured YAML parser with AGPL-3.0-or-later compatible license.
- XCTest or project-equivalent test runner.
- Public container images for smoke examples, with no private registry credentials.
- Repository documentation:
  - `AGENTS.md`
  - `CLAUDE.md`
  - `README.md`
  - `docs/plans/index.md`

## Ownership Boundaries

- This repository owns the adapter source, tests, examples, and docs.
- Parent EMSI monorepo files are out of scope unless a future task explicitly requests submodule integration.
- Apple `container` behavior is an external runtime dependency; this project owns diagnostics and command rendering, not runtime internals.
- Docker Compose behavior is the compatibility reference; this project owns only the subset it explicitly documents and tests.
- Local runtime state created by this adapter must be project-scoped and adapter-owned.
- Registry credentials, Keychain, Docker Hub account state, and host DNS are outside the adapter's ownership.

## Open Questions

- What should the final installed binary name be: `container-compose-adapter`, `cca`, or both?
- What minimum macOS and Apple `container` versions should be documented as supported?
- Which YAML parser should be used after AGPL-compatible license review?
- Should first release execution require an explicit `--yes` flag in addition to `--dry-run` support?
- How much Compose interpolation syntax is needed for the first release?
- Should named volumes map to Apple `container` volume primitives, adapter-managed directories, or both depending on capability discovery?
- How should health readiness be implemented if Apple `container` does not expose Docker-like health status?
- Should multi-file Compose merge be a Phase 2 follow-up plan or part of the first release after single-file support stabilizes?
- What examples best represent the first supported local development workflow without requiring private registries or credentials?
- Which non-OrbStack local build path is reliable enough for `build.context` support if Apple `container` build behavior is insufficient?
- What is the exact documented replacement for `host.docker.internal` on Apple `container`, if any?
- How should timeout defaults and CLI overrides work for `up --wait`?
- Should OrbStackless readiness be a separate release milestone after the first dry-run-only preview?

## Completion Criteria

The plan is complete when:

- The CLI can parse and plan at least one useful single-file Compose project and one backend-shaped multi-service fixture.
- `doctor`, `config`, `plan`, `up --dry-run`, and `down --dry-run` work without runtime mutation.
- Unsupported and risky Compose features emit explicit diagnostics.
- Parser, normalizer, compatibility, planner, renderer, redaction, safety, CLI, build-planning, readiness-gate, and executor-boundary tests pass.
- Real `up` and `down` execute the documented subset through Apple `container` when the runtime is available.
- `up --build --wait` executes the backend-shaped fixture through Apple `container` when runtime capabilities are available.
- Runtime smoke is either passed on a machine with Apple `container` or explicitly documented as skipped with evidence.
- The OrbStackless Daily Development Readiness Gate is either passed with evidence or clearly documented as not yet met. Do not claim OrbStack is unnecessary until it passes.
- README and dedicated docs describe positioning, setup, support matrix, dry-run workflow, safety model, and known limitations.
- Examples exist only for tested behavior.
- `docs/plans/index.md` accurately reflects the final state and next todo.
- If complete, this plan is moved to `docs/plans/completed/` and recorded in `docs/plans/completed/index.md`.

## Execution Prompt

```text
Implement the plan in docs/plans/2026-06-11-container-compose-adapter-implementation-plan.md for the Container Compose Adapter repository.

Before changing files, read AGENTS.md, CLAUDE.md, README.md, docs/plans/index.md, and the plan. Follow the local AGENTS.md plan lifecycle for plan and todo updates, and use either superpowers:subagent-driven-development or superpowers:executing-plans to work task-by-task when available. Do not create, switch, rename, delete, or otherwise change branches. Do not edit the parent EMSI monorepo or update any submodule pointer unless explicitly asked.

Start with Phase 0: confirm the implementation stack, inspect the local Apple container CLI capability surface with no-side-effect commands when available, create the minimal CLI/package foundation, and add tests for the initial doctor/missing-runtime behavior. Preserve parser/planner/executor separation, keep dry-run as the first contract, use structured YAML parsing rather than string parsing, pass runtime commands as argv arrays, redact secret-looking values, and document unsupported Compose features explicitly.

Treat OrbStackless daily development as a release gate, not an assumption. Build support, default project networking, service-name DNS, host service access diagnostics, named volume persistence, depends_on health/job gates, idempotent up, logs/status/run/down, and the backend-shaped smoke fixture must be implemented and verified before claiming OrbStack is no longer required for daily development.

After each meaningful phase, run the relevant tests, update docs/plans/index.md so it contains only the next concrete todo for the active plan, and update the plan artifact if reality differs from the proposal. For verification, run the project test command such as swift test once the package exists; run dry-run smoke before any runtime mutation; run real Apple container smoke only if the runtime is installed and execution is explicitly requested. Run the OrbStackless readiness smoke only when Docker/OrbStack are stopped or unavailable and Apple container is available. Commit only if explicitly requested; if committing, commit inside this repository before any parent monorepo submodule pointer update.
```
