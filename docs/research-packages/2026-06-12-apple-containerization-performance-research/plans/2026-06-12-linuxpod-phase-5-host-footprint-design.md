# LinuxPod Phase 5 Host Footprint Design

**Date:** 2026-06-12
**Linked plan:** [LinuxPod Compose Runtime Backend Implementation Plan](../2026-06-12-linuxpod-compose-runtime-backend-plan.md)
**Status:** design accepted; measurement evidence tracked separately.

## Problem

Guest cgroup memory alone cannot prove that LinuxPod is cheaper than
Docker/OrbStack on the host. The base overhead spike rejected runner-process
RSS (`ps -o rss=` on the harness PID) because it did not scale with guest
workload, so the project currently has no reliable host-side memory source.
Phase 6 benchmark comparisons must not claim lower host cost until one exists.

## Measurement Model

One in-process harness run per scenario: the harness brings up the scenario
inside a single signed process (runtime state is not durable across CLI
invocations), samples guest and host sources while the pod is alive, then
stops and deletes only adapter-owned resources. All VM-creating commands run
escalated outside the sandboxed shell because the sandbox denies Hypervisor
access.

Scenarios:

- `idle-pod`: project LinuxPod created with no service containers started.
- `db-only`: postgres service started and healthy.
- `full-stack`: backend-shaped DB -> migrate -> seed -> API fixture up.
- `scale-test`: `db-only` followed by a bulk insert workload
  (`psql generate_series`), sampled before and after the load.

## Candidate Host Sources

| Source | Attribution | Notes |
| --- | --- | --- |
| `task-info-phys-footprint` | adapter-process | `task_info(TASK_VM_INFO).phys_footprint` read in-process; the ledger that Activity Monitor reports and the expected home of VZ guest pages. |
| `footprint-tool` | adapter-process | `/usr/bin/footprint <pid>`; may require elevated permissions; probed before use. |
| `vmmap-summary` | adapter-process | `vmmap -summary <pid>` physical footprint line; requires task inspection rights; probed before use. |
| `ps-rss-tree` | process-tree | `ps -o rss=` over the adapter process tree; expected to repeat the spike rejection and document it. |
| `vm-stat-delta` | system-wide | `vm_stat` free/active/wired deltas; not attributable to one process, kept only as a cross-check and recorded `blocked` for attribution. |

## Rejection Criteria

A host source is **rejected-not-scaling** when the guest cgroup current
memory grows by at least `64 MiB` between the pre-load and post-load samples
of `scale-test` while the host source grows by less than half of the guest
delta. A source is **blocked** when it cannot attribute memory to the adapter
process (system-wide sources) or cannot be sampled in this environment
(permission failures). Otherwise a source that tracks the guest delta is
**accepted**. Acceptance requires the scale check, not just plausible
absolute values.

## JSONL Schema `container-compose-adapter/host-footprint/v1`

Sample records (one per sampling point):

```json
{
  "schemaVersion": "container-compose-adapter/host-footprint/v1",
  "recordType": "linuxpod-host-footprint-sample",
  "timestamp": "ISO-8601",
  "project": "cca-linuxpod-phase5-footprint",
  "scenario": "idle-pod | db-only | full-stack | scale-test-before | scale-test-after",
  "sampleIndex": 1,
  "guest": {
    "cgroupMemoryCurrentBytes": 0,
    "cgroupMemoryLimitBytes": 0,
    "processCount": 0,
    "cpuUsageUsec": 0,
    "blockReadBytes": 0,
    "blockWriteBytes": 0
  },
  "hostSources": [
    {
      "source": "task-info-phys-footprint",
      "attribution": "adapter-process | process-tree | system-wide",
      "bytes": 0,
      "status": "sampled | unavailable | error",
      "note": "optional detail"
    }
  ]
}
```

Decision records (one per source after the scale test):

```json
{
  "schemaVersion": "container-compose-adapter/host-footprint/v1",
  "recordType": "linuxpod-host-footprint-source-decision",
  "timestamp": "ISO-8601",
  "project": "cca-linuxpod-phase5-footprint",
  "source": "task-info-phys-footprint",
  "guestDeltaBytes": 0,
  "hostDeltaBytes": 0,
  "verdict": "accepted | rejected-not-scaling | blocked",
  "reason": "short explanation"
}
```

The final record of a run is a cleanup-proof record matching the existing
runtime evidence conventions (`stateDirectoryExistsAfterCleanup`,
`ownedPrefix`, process-check note).

The guest block is `null` for host-only probe records taken before any VM
exists (Task 5.2 dry probes use the same sample shape with
`project: "host-probe"` and no `guest` block).

## Safety

- The harness reuses the existing runtime approval token and refuses to run
  without it; dry-run remains the default.
- Only `cca-linuxpod-` prefixed resources are created, stopped, or deleted.
- Bulk-load SQL runs inside the adapter-owned postgres container only.
- Evidence lives under `docs/evidence/linuxpod-host-footprint/`.

## Documentation Rule

Until a source is recorded `accepted` in decision evidence, project
documentation must not claim that LinuxPod base VM overhead or host memory
cost is lower than Docker/OrbStack.
