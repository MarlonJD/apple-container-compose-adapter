# Kubernetes Input Subset

## Product Rule

Kubernetes support is an input/frontend feature. It is not a full Kubernetes
cluster, not a production distribution, and not a kubelet/controller/scheduler
replacement.

The supported path is:

```text
Kubernetes YAML / Helm template output / Kustomize output
        -> KubernetesSubsetFrontend
        -> LocalDevProject IR
        -> AppleNativePlanner
        -> LinuxPodProjectRuntime
```

The tool should consume rendered YAML. It should not implement Helm or
Kustomize internally in the first phase.

## First Supported Object Set

| Kubernetes object | Local-development behavior |
| --- | --- |
| Deployment | long-running `LocalDevService` |
| StatefulSet | stateful `LocalDevService` with named volume intent |
| Service | internal DNS alias and optional local port intent |
| ConfigMap | `LocalDevConfig`, env, or file mount intent |
| Secret | `LocalDevSecret`, env, or file mount intent with redaction |
| Job | `LocalDevJob` with logs and exit code |
| PersistentVolumeClaim | adapter-owned `LocalDevVolume` |
| Ingress | `LocalDevRoute` ingress-lite intent |
| Namespace | project scope or profile |

## Explicit Non-goals

Do not support or claim:

- CRDs;
- operators;
- admission webhooks;
- mutating or validating webhook behavior;
- RBAC enforcement;
- ServiceAccount token semantics;
- NetworkPolicy;
- HorizontalPodAutoscaler;
- DaemonSet;
- full StatefulSet ordinal behavior;
- real kube-scheduler behavior;
- kubelet compatibility;
- kubectl-compatible API server;
- full CNI or CSI implementation;
- production Kubernetes conformance.

## Input Modes

Potential CLI shapes:

```bash
cca plan -f k8s/dev/
cca up -f k8s/dev/ --runtime linuxpod
helm template ./chart -f values.local.yaml | cca up -f -
kustomize build overlays/local | cca up -f -
```

These commands are design examples. They are not implemented by the current
CLI.

## Translation Details

Deployment maps to a service:

```text
metadata.name -> LocalDevService.name
container.image -> LocalDevService.image
container.command/args -> command intent
container.env/envFrom -> environment/config/secret intent
container.ports -> LocalDevPort
readinessProbe -> LocalDevHealthcheck
volumeMounts -> LocalDevMount
```

Service maps to DNS/port intent:

```text
metadata.name -> alias
spec.ports[].port -> internal route port
spec.ports[].targetPort -> target service port
optional local annotation -> deterministic host port
```

Job maps to a one-off job:

```text
metadata.name -> LocalDevJob.name
container.image -> image
container.command/args -> command
restartPolicy Never -> run-to-completion expectation
```

PVC maps to named volume intent:

```text
metadata.name -> LocalDevVolume.name
requested storage -> sizeBytes when parseable
```

Ingress maps to ingress-lite route intent:

```text
host/path -> LocalDevRoute
backend service/port -> target service and target port
```

## Useful Local Annotations

Possible project-specific annotations:

```yaml
metadata:
  annotations:
    cca.local/host-port: "8080"
    cca.local/profile: "dev"
    cca.local/run-as-job: "true"
    cca.local/volume-size: "1073741824"
    cca.local/ignore: "true"
```

Annotations must not imply full Kubernetes behavior. They only tune
local-development translation.

## Diagnostics

Unsupported Kubernetes objects or fields should produce diagnostics with a
suggested workaround. Examples:

- unsupported object kind;
- multi-replica controller when only single-replica local mode is supported;
- dynamic host port when deterministic publishing is required;
- unsupported probe type;
- unsupported volume source;
- secret/config source that cannot be loaded safely.

The user-facing wording should be direct:

> Kubernetes support currently means local-development manifest translation.
> It is not a Kubernetes cluster and does not run controllers or operators.
