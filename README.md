# Container Compose Adapter

Container Compose Adapter is a macOS developer tool for mapping Docker
Compose-style local development stacks onto Apple container runtime surfaces.

The project aims for practical Docker Compose compatibility where it is useful
for local development, while documenting any behavior that cannot be matched
exactly by the selected runtime.

This project is not affiliated with Apple or Docker.

## Current Status

The current SwiftPM implementation is intentionally small and gate-driven:

- Runtime-neutral planning, dry-run output, diagnostics, redaction, and safety
  checks live in the core library.
- `NoopDryRunBackend` renders plans without runtime side effects.
- `LinuxPodBackend` is available only through explicit runtime selection and
  requires a current-task approval token for commands that create, start, stop,
  or delete runtime resources.
- Docker/OrbStack-backed Docker Compose remains the compatibility and
  efficiency baseline. Public Apple `container` CLI behavior is only a
  fallback, capability probe, or negative-control comparison.

The LinuxPod path currently uses the pinned
`apple/containerization` package version `0.26.5`.

## Build And Test

Run from the repository root:

```bash
swift test
```

## Local LinuxPod Signing

LinuxPod runtime execution uses Virtualization.framework. A binary launched
through plain `swift run` does not carry the required entitlement, so runtime
smoke runs must use a signed executable. Run the signing helper after each
`swift build` or `swift test` that may replace the debug binary:

```bash
swift build
scripts/sign-debug-runtime.sh
```

Verify the entitlement before running runtime-mutating commands:

```bash
codesign -d --entitlements :- .build/arm64-apple-macosx/debug/container-compose-adapter
```

## Dry Run

Render the public-image LinuxPod smoke plan without creating runtime resources:

```bash
swift run container-compose-adapter \
  --runtime linuxpod \
  --dry-run \
  --sample public-smoke \
  --project-name phase3-public-smoke \
  --format text \
  --evidence-jsonl docs/evidence/linuxpod-compose-runtime/phase3-public-smoke-dry-run.jsonl \
  up
```

Use `--sample backend-shaped` to render the public DB -> migrate -> seed -> API
fixture used by the LinuxPod one-pod Phase 4 gate.

The generated plan uses adapter-owned names prefixed with `cca-linuxpod-`,
redacts likely secret environment values, and records JSONL evidence. Dry-run
output is required before any LinuxPod runtime mutation.

The `--evidence-jsonl` flag appends dry-run evidence in `--dry-run` mode and
runtime execution evidence after a successful approved runtime command.
Approved runtime execution output includes action-level results such as job
exit codes, captured log summaries, cleanup actions, and status metadata when
the selected backend provides them. Use `--format json` for the machine-readable
execution result.

## Runtime Mutation

Commands that create, start, stop, or delete LinuxPod/runtime resources require
all of the following:

- explicit approval in the current task;
- the runtime flag `--runtime linuxpod`;
- the approval token `I_APPROVE_CCA_LINUXPOD_RUNTIME_MUTATION`;
- adapter-owned `cca-linuxpod-*` resource names and state only.

Do not use this project for private workloads, registry login, Keychain
mutation, Docker Hub credential changes, global prune/cleanup, host DNS
mutation, or destructive host changes.

## License

Copyright (C) 2026 Burak Karahan

Container Compose Adapter is free software licensed under the GNU Affero
General Public License v3.0 or later. See [LICENSE](LICENSE) for the full
license text.

SPDX-License-Identifier: AGPL-3.0-or-later
