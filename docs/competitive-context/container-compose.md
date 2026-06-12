# Competitive Context: Container-Compose

## What Exists

[`Mcrich23/Container-Compose`](https://github.com/Mcrich23/Container-Compose)
is an existing Apple `container` Compose bridge. Its public README describes
limited Docker Compose support for Apple Container, says it is not a Docker or
Docker Compose wrapper, documents Homebrew installation, and exposes
Compose-like `up` behavior.

That is a useful project. It also means Container Compose Adapter should not
be another simple Apple `container` CLI/API wrapper.

## Why Not Duplicate It

Container Compose Adapter is not intended to duplicate that wrapper layer.

Existing Apple Container Compose wrappers primarily translate Compose YAML into
Apple `container` CLI/API behavior. That layer is already occupied and should
be treated as an external benchmark and compatibility reference, not an
implementation backend for this repository.

If this differentiation cannot be made real, the right path is to contribute
to `Mcrich23/Container-Compose` rather than maintain a duplicate tool.

## Areas It Appears To Cover

- Apple Container Compose bridge behavior.
- Homebrew availability.
- Active release and user-interest signal.
- Compose `up`, `down`, `build`, and `version` basics.
- YAML parsing and Apple `container` command/API integration.

## Gaps That Validate This Roadmap

The public project and Apple container discussions show important local-dev
gaps that map directly to this roadmap:

- service DNS and aliases for same-project services;
- `depends_on` object form and condition semantics;
- one-off jobs for migrations and seeds;
- named volume semantics for database workloads;
- project isolation beyond container naming;
- warm runtime/recreate behavior without removing every service;
- networking behavior and port predictability;
- logs, status, event, and recovery model.

## Container Compose Adapter Differentiation

Container Compose Adapter focuses below the wrapper layer:

- LinuxPod-first runtime research;
- one project = one persistent LinuxPod;
- persistent Linux-side project storage;
- engine-like amortization without Docker Engine;
- reusable Linux-side ext4 named volumes;
- service DNS and deterministic ports;
- healthcheck and job orchestration;
- benchmark/evidence-first development;
- future Kubernetes local-development input subset.

This project is not an implementation backend for `container-compose`, Docker
Desktop, OrbStack, Colima, Podman, Lima, Rancher Desktop, or Microsoft WSL
container. Those tools remain comparison, benchmark, or optimization
references only.
