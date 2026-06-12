# LocalDevProject IR

## Purpose

Compose and Kubernetes should not map directly to LinuxPod. They should compile
into a shared `LocalDevProject` graph first.

The IR keeps the runtime backend small and lets Compose and Kubernetes support
grow independently. The runtime planner should consume local-development intent,
not raw YAML syntax.

## Current Scaffold

The Swift scaffold currently defines:

- `LocalDevProject`
- `LocalDevService`
- `LocalDevJob`
- `LocalDevVolume`
- `LocalDevMount`
- `LocalDevPort`
- `LocalDevDependency`
- `LocalDevHealthcheck`
- `LocalDevSecret`
- `LocalDevConfig`
- `LocalDevRoute`
- `LocalDevNetwork`
- `LocalDevBuildSpec`

`LocalDevProject.runtimePlan()` bridges the scaffold into the existing
`RuntimePlan` so current dry-run and LinuxPod planning tests can exercise the
same execution boundary.

## Project Fields

`LocalDevProject` represents:

- stable project id and display name;
- source files used to build the graph;
- long-running services;
- one-off jobs;
- named volumes;
- network/alias intent;
- ingress-lite routes;
- secrets and configs;
- active profiles.

## Service Fields

`LocalDevService` represents:

- service name;
- image reference;
- optional build spec for future build support;
- command and entrypoint intent;
- environment variables;
- env files;
- bind, named-volume, and tmpfs mounts;
- host/container ports;
- internal DNS aliases;
- dependency conditions;
- healthcheck;
- restart policy;
- profiles.

The current runtime bridge maps service image, command, environment, bind
mounts, named-volume mounts, deterministic ports, dependencies, and healthcheck
to `ServicePlan`.

## Job Fields

`LocalDevJob` represents:

- job name;
- image reference;
- optional build spec for future build support;
- command;
- environment variables;
- env files;
- mounts;
- dependencies;
- completion policy;
- profiles.

The current bridge maps jobs to `ServicePlan(kind: .oneOffJob)` and adds a
`service_completed_successfully` readiness marker.

## Volumes And Mounts

Supported IR volume kinds:

- `named`
- `bind`
- `tmpfs`

Supported IR mount kinds:

- `namedVolume`
- `bind`
- `tmpfs`

Current runtime support maps named volumes to adapter-owned Linux-side state
and bind mounts to host shares. Tmpfs is represented in the IR, but the current
runtime bridge emits a blocking diagnostic instead of pretending tmpfs will
execute.

Named volumes must preserve by default. Deletion is allowed only through an
explicit adapter-owned volume cleanup path.

## Dependency Conditions

Dependencies support:

- `serviceStarted`
- `serviceHealthy`
- `serviceCompletedSuccessfully`

These map to the existing readiness kinds used by `RuntimePlan` and
`LinuxPodBackend`.

## Routes

`LocalDevRoute` is the ingress-lite placeholder. It represents local route
intent such as:

- host name;
- path prefix;
- target service;
- target port.

The first implementation may only preserve this intent. Runtime execution
should not claim ingress support until a local proxy or equivalent route layer
is implemented and tested.

## Build Specs

`LocalDevBuildSpec` is present so Compose `build` and future Kubernetes local
image workflows can be represented. The current runtime bridge emits
`unsupported-localdev-build` because this package does not yet implement a
Dockerless build pipeline.

Future build research should decide among Apple `container` build behavior,
BuildKit-in-LinuxPod, or another non-Docker builder. Do not add Docker Desktop,
OrbStack, Colima, Podman, Lima, or Rancher as implementation backends.

## Compose Mapping

| Compose concept | LocalDevProject mapping |
| --- | --- |
| service | `LocalDevService` |
| command / entrypoint | service process intent |
| depends_on | `LocalDevDependency` |
| healthcheck | `LocalDevHealthcheck` |
| ports | `LocalDevPort` |
| volumes | `LocalDevVolume` / `LocalDevMount` |
| environment / env_file | environment and env file intent |
| profiles | project/service/job profiles |
| one-off command service | `LocalDevJob` when planned as a job |
| secrets / configs | `LocalDevSecret` / `LocalDevConfig` |

## Kubernetes Mapping

| Kubernetes object | LocalDevProject mapping |
| --- | --- |
| Deployment | `LocalDevService` |
| StatefulSet | `LocalDevService` plus named volume intent |
| Service | DNS alias and optional local port intent |
| ConfigMap | `LocalDevConfig`, env, or file mount intent |
| Secret | `LocalDevSecret`, env, or file mount intent |
| Job | `LocalDevJob` |
| PersistentVolumeClaim | `LocalDevVolume` |
| Ingress | `LocalDevRoute` |
| Namespace | project scope or profile |

## Diagnostic Rule

Unsupported runtime features must become diagnostics. The current scaffold
already blocks build specs, dynamic host ports, invalid mount sources, and
tmpfs mounts during `runtimePlan()` normalization.

Future parser work should follow the same rule: keep the source intent visible,
then produce a clear diagnostic when the current runtime cannot safely execute
it.
