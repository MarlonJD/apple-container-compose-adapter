# Agent Notes

## Scope

- This repository owns Container Compose Adapter, a macOS developer tool that
  maps Docker Compose-style local stacks onto Apple's `container` CLI.
- The goal is practical Docker Compose compatibility for local development on
  Apple silicon and macOS, not a claim of full Docker Engine or Docker Compose
  replacement until behavior is verified.
- Keep source code identifiers, comments, tests, documentation file names, and
  canonical docs in English.
- Treat `docker compose` behavior as the compatibility reference. Treat Apple
  `container` behavior as the runtime target.

## Repository Boundaries

- This repository is a standalone project even when checked out as an EMSI
  monorepo submodule under `tools/apple-container-compose-adapter`.
- Changes inside this repository must be committed in this repository first.
  When the project is used as a submodule, update the parent repository's
  submodule pointer only after the child commit is complete and pushed.
- Do not edit EMSI application, backend, infra, or platform files from this
  repository unless the task explicitly asks for integration work in the parent
  monorepo.
- Do not create, switch, rename, delete, or otherwise perform branch operations
  unless the user explicitly asks for that branch action in the current task.

## Product Direction

- Prefer the name "Container Compose Adapter" in user-facing documentation.
- Explain the tool as a compatibility adapter that reads Docker Compose-style
  intent and runs the closest safe equivalent through Apple's `container` CLI.
- Avoid wording that implies Apple provides a native `container compose`
  command or that this project is an official Apple tool.
- Document unsupported Compose features explicitly instead of silently ignoring
  them.

## Licensing

- The project license is GNU Affero General Public License v3.0 or later:
  `AGPL-3.0-or-later`.
- Project copyright is held as `Copyright (C) 2026 Burak Karahan`.
- New source files should include SPDX headers where the language and local
  style allow it:
  - `SPDX-License-Identifier: AGPL-3.0-or-later`
  - `Copyright (C) 2026 Burak Karahan`
- Do not add dependencies, copied code, examples, or generated assets with
  licenses that conflict with AGPL-3.0-or-later.

## Compatibility Rules

- Preserve Compose semantics where they matter for local development:
  service names, environment interpolation, port publishing, bind mounts,
  named volumes, profiles, one-off jobs, logs, health readiness, dependency
  order, and cleanup behavior.
- When exact parity is not possible, prefer a clear diagnostic with a suggested
  workaround over surprising behavior.
- Keep compatibility logic data-driven where practical. Parse structured
  Compose YAML rather than relying on ad hoc string manipulation.
- Build commands must shell out to `container` only through a narrow execution
  boundary so dry-run, testing, logging, and future runtime adapters stay easy
  to maintain.
- Never hide destructive behavior behind a Compose-compatible command. Deleting
  containers, networks, volumes, or generated state must be explicit and
  documented.

## Planning

- For implementation plans, roadmaps, production-readiness plans, or follow-up
  execution plans, create or update a Markdown artifact under `docs/plans/`.
  Do not leave requested plans only in chat unless the user explicitly asks for
  a conversational answer only.
- Name plan files in English kebab-case as
  `YYYY-MM-DD-<short-topic>-plan.md`.
- Saved plans must be self-contained: include objective, scope, assumptions,
  phases, verification, risks, dependencies, ownership boundaries, explicit
  out-of-scope items, and an `Execution Prompt` section.
- If `docs/plans/index.md`, `docs/plans/completed/index.md`, or
  `docs/plans/notes/index.md` exist, keep them aligned with created, updated,
  completed, superseded, or blocked plans. If they do not exist, create them
  when the planning workflow needs durable tracking.

## Implementation Guidance

- Keep the first implementation path small and testable: parse a useful subset
  of Compose, produce an inspectable execution plan, then run Apple `container`
  commands behind that plan.
- Prefer boring, deterministic CLI behavior over background magic.
- Use clear command names such as `up`, `down`, `logs`, `status`, `run`, and
  `doctor` only when their behavior is documented.
- Include dry-run output for any command that would create, start, stop, or
  delete runtime resources.
- Keep macOS-specific assumptions visible in diagnostics, especially Apple
  silicon, macOS version, `container system status`, network support, and host
  service access.

## Documentation

- Update `README.md` when changing user-facing commands, flags, setup steps,
  compatibility scope, or known limitations.
- Add examples under `examples/` when introducing supported Compose patterns.
- Document Apple `container` version assumptions and tested macOS versions.
- Do not publish secrets, personal machine paths, registry tokens, generated
  local runtime state, or private EMSI data.

## Checks

- Add or update automated tests for parser, compatibility planning, command
  rendering, and error diagnostics before claiming behavior is complete.
- For runtime changes, verify both:
  - a no-side-effect dry run that shows the Apple `container` commands to be
    executed;
  - a real macOS Apple `container` smoke path when the environment is available.
- If Apple `container` is unavailable in the current environment, run the
  parser/planner tests and state that runtime smoke verification was not run.
- Do not loop on the same failing test command. Inspect the failure, make a
  targeted fix only when the cause is clear, and retry once with new evidence.

## Security And Safety

- Treat Compose files as untrusted input. Avoid command injection by passing
  arguments as arrays instead of shell-concatenated strings.
- Validate paths before mounting host files or directories. Warn when a Compose
  file requests broad host mounts such as `/`, `$HOME`, or credential folders.
- Redact environment values that look like secrets in logs, dry-run output, and
  diagnostics.
- Do not mutate Docker Hub, Apple `container` registries, Keychain credentials,
  containers, networks, volumes, or host DNS settings unless the user requested
  that operation and the command behavior is documented.

Run commands from the repository root.
