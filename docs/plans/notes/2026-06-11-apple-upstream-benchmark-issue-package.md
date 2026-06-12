# Apple Upstream Benchmark Issue Package

**Date:** 2026-06-11
**Owner subtree:** `tools/apple-container-compose-adapter`
**Linked evidence:** [Runtime Efficiency Benchmark Evidence](2026-06-11-runtime-efficiency-benchmark-evidence.md)
**Target upstream repositories:**

- `apple/container`
- `apple/containerization`

## Recommendation

Open upstream feedback, but keep it narrow and evidence-led.

## Posted Upstream

Posted manually through the local `gh` CLI authenticated as `MarlonJD`, not
through a Codex/GitHub connector identity.

| Target | Status | URL |
| --- | --- | --- |
| Comment on `apple/containerization#729` | posted | <https://github.com/apple/containerization/issues/729#issuecomment-4684059568> |
| Focused issue on `apple/container` | opened | <https://github.com/apple/container/issues/1698> |

Recommended sequence:

1. Add a comment to the existing `apple/containerization` performance benchmark
   request: <https://github.com/apple/containerization/issues/729>.
2. Open one focused `apple/container` performance issue for the Postgres
   runtime/cgroup memory and block-read behavior.
3. Do not open a separate lifecycle/XPC issue yet. The final benchmark harness
   completed after unique names, readiness waits, port-release waits, and
   cleanup verification were added. Open a lifecycle issue only if a minimal
   standalone reproduction still fails without adapter-specific harness bugs.

Do not post these through a Codex or ChatGPT GitHub connector identity. The
owner should post them manually from their GitHub account.

## Upstream Fit Check

The upstream repositories are worth engaging:

- `apple/container` says contributions are welcome and points contributors to
  the main `containerization` contributing guide.
- `apple/containerization` explicitly welcomes bug fixes, performance
  improvements, API additions/enhancements, documentation, and advocacy.
- `apple/containerization` asks contributors to discuss substantial changes or
  new features in an issue first.
- Recent sampled merged pull requests show non-maintainer contributors are
  accepted in both repositories.

Sampled GitHub API check on 2026-06-11:

| Repository | Closed PRs sampled | Merged sampled | Merged from non-maintainer users in sample |
| --- | ---: | ---: | ---: |
| `apple/container` | 400 | 333 | 134 |
| `apple/containerization` | 400 | 359 | 43 |

Existing related upstream issue:

- <https://github.com/apple/containerization/issues/729> asks for a
  cross-runtime performance regression suite. It already discusses startup,
  volume I/O, small-file I/O, container-to-container networking, port-mapped
  TTFB, and image build performance. The Container Compose Adapter benchmark
  adds a DB/backend-shaped workload with process RSS, cgroup memory, DB data
  footprint, block I/O, and repeated lifecycle evidence.

## Comment Draft For `apple/containerization#729`

```markdown
Thanks for opening this. I ran a small repeated benchmark while evaluating Apple `container` for a Compose-style local development adapter, and the results seem relevant to this request because they add DB/backend-shaped workload data alongside startup and I/O observations.

Environment:

- macOS 26.5.1 (25F80), arm64
- Xcode 26.5 (17F42)
- Apple `container` CLI 1.0.0 (release, commit `ee848e3`)
- MacBook Pro Mac14,7, Apple M2, 16 GB memory
- Docker/OrbStack baseline on the same machine

Workloads:

- `simple-web`: nginx static web container
- `postgres-db-only`: fresh Postgres 16 Alpine container and fresh volume per iteration
- `backend-shaped`: Postgres + migrate + seed + simple API, using the Apple-side PGDATA subdirectory and DB-IP workarounds because this was not exact Compose service-name parity

Iteration counts:

| Workload | Docker/OrbStack | Apple `container` |
| --- | ---: | ---: |
| `simple-web` | 50 | 20 |
| `postgres-db-only` | 50 | 20 |
| `backend-shaped` | 20 | 10 |

Key observations:

- Apple `container` simple-web cached startup is promising: startup/readiness p50 was 0.910s versus Docker/OrbStack 5.795s in this harness. Simple-web cgroup memory p50 was also lower: 15.13 MiB versus 17.18 MiB.
- Postgres process RSS was effectively the same between runtimes: DB-only p50 26.57 MiB on Apple versus 26.68 MiB on Docker/OrbStack.
- DB runtime/cgroup memory was much higher on Apple: DB-only cgroup p50 187.45 MiB versus Docker/OrbStack 65.14 MiB; backend DB cgroup p50 188.45 MiB versus Docker/OrbStack 67.33 MiB.
- DB data footprint was effectively identical: about 45.70 to 45.79 MiB across both runtimes.
- Apple DB block-read snapshots were higher in this workload: DB-only p50 81.05 MiB versus Docker/OrbStack 0.00 MiB; backend DB p50 81.05 MiB versus Docker/OrbStack 3.09 MiB.
- CPU snapshots need careful interpretation because the same load window completed less HTTP/SQL work on Apple in several cases. For example, simple-web p50 load completed 1476 HTTP requests on Apple versus 4882 on Docker/OrbStack.

This might be useful as another benchmark axis for the proposed regression suite: DB/backend workloads should track process RSS, cgroup memory, runtime-reported memory, data footprint, block I/O, and completed work per load window, not only startup or raw disk throughput.

I am happy to reduce this into a standalone public repro if that would be useful. The main question from these results is whether the roughly 187-188 MiB DB cgroup/runtime memory for a small Postgres container is expected per-container VM overhead, tunable via documented flags, or something worth optimizing/tracking as a regression metric.
```

## Issue Draft For `apple/container`

Title:

```text
[Performance]: Postgres workload reports much higher cgroup/runtime memory than Docker despite similar process RSS
```

Issue type: Bug report, or performance issue if maintainers retitle/relabel.

```markdown
### I have done the following

- [x] I have searched the existing issues
- [ ] If possible, I've reproduced the issue using the `main` branch of this project

### Steps to reproduce

I measured a public Postgres workload repeatedly on the same machine against Docker/OrbStack and Apple `container`.

Environment:

- macOS 26.5.1 (25F80), arm64
- Xcode 26.5 (17F42)
- Apple `container` CLI 1.0.0 (release, commit `ee848e3`)
- MacBook Pro Mac14,7, Apple M2, 16 GB memory
- Docker/OrbStack baseline available on the same machine

Apple workload shape:

1. Start Apple `container` services.
2. For each iteration, create a fresh named volume.
3. Run `docker.io/library/postgres:16-alpine` with:
   - `POSTGRES_USER=app`
   - `POSTGRES_PASSWORD=<benchmark-only-password>`
   - `POSTGRES_DB=app`
   - `PGDATA=/var/lib/postgresql/data/pgdata`
   - volume mounted at `/var/lib/postgresql/data`
4. Wait for `pg_isready`.
5. Capture:
   - `container stats --no-stream`
   - `/proc/1/status` inside the container
   - cgroup `memory.current`, `memory.peak`, and `memory.max`
   - `du -sk /var/lib/postgresql/data`
   - runtime-reported block I/O
6. Run a short synthetic SQL loop using `generate_series`.
7. Stop/delete the container and delete the named volume.

Docker/OrbStack used the same image, fresh volume-per-iteration shape, and the
same process/cgroup/disk probes where available.

Iteration counts:

| Workload | Docker/OrbStack | Apple `container` |
| --- | ---: | ---: |
| `postgres-db-only` | 50 | 20 |
| backend-shaped Postgres role | 20 | 10 |

### Problem description

For a small Postgres workload, the Postgres process RSS and data footprint are effectively the same between Docker/OrbStack and Apple `container`, but Apple reports much higher runtime/cgroup memory and higher DB block reads.

DB-only memory:

| Runtime | Process RSS p50 | Cgroup current p50 | Runtime memory p50 |
| --- | ---: | ---: | ---: |
| Docker/OrbStack | 26.68 MiB | 65.14 MiB | 17.21 MiB |
| Apple `container` | 26.57 MiB | 187.45 MiB | 187.01 MiB |

Backend-shaped DB role memory:

| Runtime | Process RSS p50 | Cgroup current p50 | Runtime memory p50 |
| --- | ---: | ---: | ---: |
| Docker/OrbStack | 26.65 MiB | 67.33 MiB | 20.09 MiB |
| Apple `container` | 26.57 MiB | 188.45 MiB | 188.15 MiB |

Disk footprint:

| Workload | Runtime | Data footprint p50 |
| --- | --- | ---: |
| DB-only | Docker/OrbStack | 45.70 MiB |
| DB-only | Apple `container` | 45.70 MiB |
| Backend DB | Docker/OrbStack | 45.78 MiB |
| Backend DB | Apple `container` | 45.79 MiB |

Block read snapshots:

| Workload | Runtime | Block read p50 |
| --- | --- | ---: |
| DB-only | Docker/OrbStack | 0.00 MiB |
| DB-only | Apple `container` | 81.05 MiB |
| Backend DB | Docker/OrbStack | 3.09 MiB |
| Backend DB | Apple `container` | 81.05 MiB |

I expected some overhead from Apple `container`'s one-VM-per-container model, but the process RSS being the same while cgroup/runtime memory is roughly 187-188 MiB makes it hard to tell whether this is:

- expected per-container VM/runtime overhead;
- cgroup accounting that includes runtime/kernel/init memory;
- a tunable default that should be documented for DB/backend workloads;
- or an optimization opportunity.

Could maintainers clarify whether this memory profile is expected, and whether there are recommended flags or runtime settings for small DB containers where the process RSS is much lower than the reported cgroup/runtime memory?

### Environment

- OS: macOS 26.5.1 (25F80), arm64
- Xcode: 26.5 (17F42)
- Container: `container CLI version 1.0.0 (build: release, commit: ee848e3)`
- Hardware: MacBook Pro Mac14,7, Apple M2, 16 GB memory

### Notes

This came from a Compose-adapter feasibility benchmark. The backend-shaped Apple path used documented workarounds in my harness:

- `PGDATA=/var/lib/postgresql/data/pgdata`, because mounting a named volume directly at the Postgres data root exposed `lost+found`.
- DB-IP targeting instead of Compose-style service-name DNS.

So the backend-shaped result is not being presented as Compose parity. The DB-only result is the narrower signal: same Postgres image, same fresh-volume shape, same process RSS, same data footprint, but much higher Apple cgroup/runtime memory and block-read snapshots.
```

## Deferred Issue Candidate

Do not open this yet without a smaller standalone reproduction:

```text
[Bug]: Repeated lifecycle runs can hit XPC/bootstrap or stale port state without explicit cleanup waits
```

Reason to defer:

- Earlier Apple attempts hit XPC/bootstrap, stale state, and address-in-use
  failures.
- The final harness added unique names, readiness polling, port-release waits,
  cleanup verification, and then completed 20 simple-web, 20 DB-only, and 10
  backend-shaped Apple iterations.
- That means the adapter must own lifecycle waits, but it is not yet clear that
  a minimal upstream bug remains after the harness fixes.

Open this only if a minimal script still reproduces the runtime failure after
using unique names and verified cleanup.
