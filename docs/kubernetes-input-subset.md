# Kubernetes Input Subset

## Product Rule

Kubernetes support is an input/frontend feature. It is not a full Kubernetes distribution, not a production cluster, and not a kubelet/controller/scheduler replacement.

The implemented path is:

```text
Kubernetes YAML / Helm template output / Kustomize output
        -> KubernetesSubsetFrontend
        -> LocalDevProject IR
        -> AppleNativePlanner
        -> LinuxPod runtime plan
```

The tool consumes rendered YAML. It does not implement Helm or Kustomize
internally in this phase.

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

Implemented CLI shape:

```bash
container-compose-adapter --runtime linuxpod --dry-run \
  --k8s-file rendered.yaml -p project-name up
```

`--k8s-file` accepts one rendered multi-document YAML file. Piped stdin,
directory inputs, and shorthand aliases remain future design examples:

```bash
helm template ./chart -f values.local.yaml | cca up -f -
kustomize build overlays/local | cca up -f -
```

The supported render style indents mapping-style sequence items two columns
past their parent key (the style used by the backend-shaped fixture at
`docs/evidence/fixtures/backend-shaped/k8s.yaml`).

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

Implemented annotations:

```yaml
metadata:
  annotations:
    cca.local/host-port: "8080"        # Service: deterministic host port
    cca.local/host-ip: "127.0.0.1"     # Service: host bind address
    cca.local/depends-on: "db:service_healthy,seed:service_completed_successfully"
    cca.local/profile: "dev"           # workload/Job: local profile
    cca.local/ignore: "true"           # any object: skip translation
```

`cca.local/depends-on` exists because Kubernetes has no Compose-style
`depends_on`; it restores explicit local startup ordering with the same
condition names Compose uses. `cca.local/host-port` requires exactly one
service port. Future candidates such as `cca.local/run-as-job` and
`cca.local/volume-size` are not implemented.

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
