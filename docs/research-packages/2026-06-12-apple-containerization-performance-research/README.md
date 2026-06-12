# Apple Containerization Performance Research Package

Date: 2026-06-12

This package is a handoff bundle for deep research into whether Container
Compose Adapter can close the performance gap between Apple `container` /
`apple/containerization` and Docker/OrbStack-class Compose runtimes on macOS.

## How to use this package

1. Upload this entire package, or the zip built from it, to a research-capable
   model.
2. Paste the contents of `PROMPT.md`.
3. Ask the model to browse current upstream sources before answering.
4. Treat the local benchmark evidence as measured input, not as final proof of
   what upstream can or cannot optimize.

## Research goal

Find a realistic path, if any, to make a Compose-level runtime on top of
Apple's open source `container` and `containerization` projects competitive
enough for local backend development. The research must distinguish:

- adapter implementation problems;
- Apple `container` and `containerization` architecture limits;
- tunable or patchable upstream behavior;
- open source alternatives that already provide the needed Compose runtime
  model.

## Key local conclusions to challenge

- Apple `container` is promising for simple web workloads but currently shows
  high DB/backend cgroup/runtime memory and block-read volume in this benchmark.
- Phase 5 could not obtain reliable process-attributed host memory because
  macOS does not charge the VM guest memory to the runner process in the tested
  tools.
- LinuxPod can run the backend-shaped fixture end to end, but the Phase 6 gate
  failed on guest cgroup memory, startup/readiness, and block-read volume.
- The current LinuxPod implementation is safe and clean, but likely too cold:
  it deletes adapter-owned runtime state on cleanup and does not yet behave like
  Docker's long-lived VM, image store, layer cache, and page cache model.

## Public upstream sources to inspect

- https://github.com/apple/container
- https://github.com/apple/containerization
- https://github.com/apple/container/issues/1698
- https://github.com/apple/containerization/issues/729
- https://docs.docker.com/desktop/features/vmm/
- https://docs.docker.com/desktop/settings-and-maintenance/settings/
- https://github.com/lima-vm/lima
- https://github.com/abiosoft/colima
- https://github.com/runfinch/finch
- https://podman-desktop.io/docs/podman/creating-a-podman-machine
- https://github.com/rancher-sandbox/rancher-desktop
