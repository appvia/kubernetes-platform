# Autoscaling

## Overview

Autoscaling on this platform happens along two axes:

- **Horizontal autoscaling** — change the *number* of pods (or Kubernetes Jobs) in response to load. The platform delivers this via [**KEDA**](keda.md), which generalises the native `HorizontalPodAutoscaler` to over 60 external event sources (queues, streams, Prometheus queries, cron, CPU/memory, cloud services).
- **Vertical autoscaling** — change the CPU and memory *requests* on existing pods. The platform does not yet ship a managed VPA addon; the KEDA guide describes the safe pattern for layering an unmanaged VPA on top of a KEDA-scaled workload.

Node-level scaling (provisioning new VMs to fit pending pods) is a separate concern handled by **Karpenter** — see [Node pools](../../nodepools/overview.md).

| Layer | What it scales | Platform component |
|---|---|---|
| Cluster (nodes) | Worker node count and shape | [Karpenter](../../nodepools/karpenter.md) |
| Workload (replicas) | Number of pods / parallel Jobs | [KEDA](keda.md) |
| Pod (resource requests) | CPU and memory requests per pod | VPA, applied by tenant (see [KEDA + VPA pattern](keda.md#vertical-scaling-pod-resource-requests-vpa-keda)) |

## Enabling autoscaling

Each addon is feature-flagged on the cluster definition in the tenant repository:

```yaml
metadata:
  labels:
    enable_keda: "true"                   # Event-driven horizontal autoscaling
    enable_karpenter_nodepools: "true"    # Karpenter node pools (AWS / EKS)
```

## Next steps

- [**KEDA**](keda.md) — enabling KEDA, customising the Helm values, Prometheus integration, and end-to-end examples (scale-to-zero, cron, queue depth, CPU, hybrid patterns).
