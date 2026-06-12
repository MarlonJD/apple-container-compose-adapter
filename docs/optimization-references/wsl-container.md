# Optimization Reference: Microsoft WSL Container

## Why It Matters

[Microsoft WSL container](https://learn.microsoft.com/en-us/windows/wsl/wsl-container)
is useful as an optimization reference because it offers a native host
container UX while keeping Linux container work inside a Linux runtime
environment. The public Microsoft documentation describes two major pieces:

- `wslc.exe`, a CLI to build, run, and interact with Linux containers;
- WSL container API, an API for Windows applications to pull, run, mount,
  network, stream stdio, and interact with Linux containers.

The feature is still described as in development. Treat it as a reference, not
as a dependency.

## Boundary

Microsoft WSL container is not a backend target for this repository.

Do not add dockerd or containerd to Container Compose Adapter. Do not turn this
project into Colima, Lima, Rancher Desktop, Docker Desktop, or a WSL clone.
Extract the architecture lesson only:

```text
native host UX still needs a persistent session/storage/event/recovery layer
```

## Architecture Lessons

WSL source and docs point to a useful shape:

- VM session lifecycle;
- storage configure/create/attach/mount;
- persistent ext4 `storage.vhdx`;
- container runtime process startup;
- client/API boundary;
- event tracker;
- volume manager;
- network and container recovery.

For Container Compose Adapter, the corresponding Apple-native research surface
is:

```text
macOS Swift CLI/API
        -> ProjectSessionManager
        -> persistent Apple LinuxPod
        -> optional cca-agent inside the guest
        -> project-storage.ext4 mounted at /var/lib/cca
        -> services, jobs, volumes, DNS, ports, logs, metrics
```

## CCA Experiment Ideas

Future runtime experiments should stay Apple LinuxPod/CCA-oriented:

- `ProjectSessionManager` for project runtime reconnect/recover;
- persistent LinuxPod reuse;
- `project-storage.ext4` attach and mount;
- `/var/lib/cca` as Linux-side project state;
- guest-side `cca-agent` feasibility;
- event tracker;
- volume registry;
- port registry;
- service/job status registry;
- healthcheck via agent vs host exec benchmark;
- log stream via agent vs current host-call approach;
- state recovery after crash, failed run, or interrupted cleanup;
- warm build/cache strategy.

## Safety Interpretation

Engine-like lifecycle does not mean Docker Engine. In this repository it means
persistent session, persistent storage, content/rootfs/initfs caches, volume
registry, port registry, event tracking, recovery, warm service recreate,
metrics, diagnostics, and safe adapter-owned cleanup.
