# Plan Index

This file tracks active Container Compose Adapter plans and their next concrete
todo. Keep detailed task lists inside the plan artifact; keep only the next
action here.

Status terms: `active`, `paused`, `blocked`, `ready-for-verification`,
`completed`, `archived`, `superseded`.

| Status | Plan | Owner | Next Todo | Verification |
| --- | --- | --- | --- | --- |
| active | [Efficiency And Shared Runtime Pilot Plan](2026-06-11-efficiency-and-shared-runtime-pilot-plan.md) | `tools/apple-container-compose-adapter` | Start Phase 1 by defining the measurement evidence schema, redaction rules, resource snapshots, and dry-run-only harness contract before any runtime mutation. | Phase 0 evidence captured in [Phase 0 Capability Discovery Evidence](notes/2026-06-11-phase-0-capability-discovery-evidence.md); local Apple `container` CLI unavailable; official docs show per-container VM model and no Compose-style shared-runtime primitive. |
| paused | [Container Compose Adapter Implementation Plan](2026-06-11-container-compose-adapter-implementation-plan.md) | `tools/apple-container-compose-adapter` | Wait for the efficiency/shared-runtime pilot recommendation before starting implementation Phase 0. | Paused because the project should only proceed if the pilot shows enough efficiency or operational value. |
