# Plan Index

This file tracks active Container Compose Adapter plans and their next concrete
todo. Keep detailed task lists inside the plan artifact; keep only the next
action here.

Status terms: `active`, `paused`, `blocked`, `ready-for-verification`,
`completed`, `archived`, `superseded`.

| Status | Plan | Owner | Next Todo | Verification |
| --- | --- | --- | --- | --- |
| superseded | [Container Compose Adapter Implementation Plan](2026-06-11-container-compose-adapter-implementation-plan.md) | `tools/apple-container-compose-adapter` | Do not start the public Apple `container` CLI runtime path unless it is explicitly re-approved; reuse its parser/planner/dry-run architecture in the LinuxPod-first plan. | Superseded for runtime strategy by [LinuxPod Compose Runtime Backend Implementation Plan](2026-06-12-linuxpod-compose-runtime-backend-plan.md) after LinuxPod smoke evidence and the 2026-06-12 user decision to stop treating the public CLI as the optimization path. |
| active | [LinuxPod Compose Runtime Backend Implementation Plan](2026-06-12-linuxpod-compose-runtime-backend-plan.md) | `tools/apple-container-compose-adapter` | Start Phase 5 host footprint measurement: define the JSONL schema separating cgroup/guest memory from host physical memory and test host-side sources. | The signed Phase 4 backend-shaped runtime `up` smoke passed end to end after service log capture exposed the virtiofs named-volume chown failure and three fixes landed (ext4 block named volumes without `lost+found`, per-container APFS rootfs clones, all-containers-before-pod-creation planner ordering). DB became healthy, migrate/seed exited `0`, the API passed readiness through the `db` hosts entry, and approved cleanup was reproven. Up JSONL: [20260612T040900-phase4-backend-shaped-ordered-runtime-up.jsonl](../evidence/linuxpod-compose-runtime/20260612T040900-phase4-backend-shaped-ordered-runtime-up.jsonl). Cleanup JSONL: [20260612T041100-phase4-backend-shaped-ordered-runtime-down-cleanup.jsonl](../evidence/linuxpod-compose-runtime/20260612T041100-phase4-backend-shaped-ordered-runtime-down-cleanup.jsonl). `.container-compose-adapter` is absent after cleanup and exact process-name checks found no lingering adapter/vmexec/vminit processes. |
