# Plan Index

This file tracks active Container Compose Adapter plans and their next concrete
todo. Keep detailed task lists inside the plan artifact; keep only the next
action here.

Status terms: `active`, `paused`, `blocked`, `ready-for-verification`,
`completed`, `archived`, `superseded`.

| Status | Plan | Owner | Next Todo | Verification |
| --- | --- | --- | --- | --- |
| superseded | [Container Compose Adapter Implementation Plan](2026-06-11-container-compose-adapter-implementation-plan.md) | `tools/apple-container-compose-adapter` | Do not start the public Apple `container` CLI runtime path unless it is explicitly re-approved; reuse its parser/planner/dry-run architecture in the LinuxPod-first plan. | Superseded for runtime strategy by [LinuxPod Compose Runtime Backend Implementation Plan](2026-06-12-linuxpod-compose-runtime-backend-plan.md) after LinuxPod smoke evidence and the 2026-06-12 user decision to stop treating the public CLI as the optimization path. |
| blocked | [LinuxPod Compose Runtime Backend Implementation Plan](2026-06-12-linuxpod-compose-runtime-backend-plan.md) | `tools/apple-container-compose-adapter` | Do not proceed to Phase 7 LinuxPod replacement optimization or longer Phase 6 runs unless a new hypothesis is explicitly re-approved; keep Docker/OrbStack as the recommended backend runtime and LinuxPod as optional research only. | Phase 6 completed with decision `linuxpod-not-promising`: dry-run, one signed runtime smoke, and `5` signed warm-image iterations succeeded functionally with `0` failures and clean cleanup, but missed the Docker/OrbStack Viability Gate by a wide margin on startup/readiness, guest cgroup memory, and block reads. Evidence note: [2026-06-12-linuxpod-phase-6-benchmark-decision.md](notes/2026-06-12-linuxpod-phase-6-benchmark-decision.md). Warm run JSONL: [20260612T045331Z-phase6-warm-5.jsonl](../evidence/linuxpod-phase6-benchmark/20260612T045331Z-phase6-warm-5.jsonl). Host physical memory remains `blocked` by Phase 5. |
| active | [Apple-native Orchestrator Roadmap](2026-06-12-apple-native-orchestrator-roadmap-plan.md) | `tools/apple-container-compose-adapter` | Do not start Stage 3 runtime store or persistent LinuxPod research unless it is explicitly approved in a new task. | Stage 1 verification is tracked in the completed [Compose Frontend To LocalDevProject Plan](completed/2026-06-12-compose-frontend-localdevproject-plan.md). Stage 2 verification is tracked in the completed [AppleNativePlanner Compatibility Contract Plan](completed/2026-06-12-apple-native-planner-compatibility-contract-plan.md). Benchmarking starts only after the parser/planner gates make the measured path representative. |
