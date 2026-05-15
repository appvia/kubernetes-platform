# Autoscaling

## Overview

Autoscaling on this platform operates across three independent axes:

- **Horizontal autoscaling** — change the *number* of pods (or Kubernetes Jobs) in response to load. The platform delivers this via [**KEDA**](keda.md), which generalises the native `HorizontalPodAutoscaler` to over 60 external event sources (queues, streams, Prometheus queries, cron, CPU/memory, cloud services).
- **Vertical autoscaling** — change the CPU and memory *requests* on existing pods. The platform ships the [**Vertical Pod Autoscaler (VPA)**](vpa.md), which continuously analyzes actual resource usage and recommends right-sized requests.
- **Node-level autoscaling** — provision new worker nodes to fit pending pods. This is handled by [**Karpenter**](../../nodepools/karpenter.md).

| Layer | What it scales | Platform component |
|---|---|---|
| Cluster (nodes) | Worker node count and shape | [Karpenter](../../nodepools/karpenter.md) |
| Workload (replicas) | Number of pods / parallel Jobs | [KEDA](keda.md) |
| Pod (resource requests) | CPU and memory requests per pod | [VPA](vpa.md) |

### Why all three?

Each layer solves a different problem:

- **Karpenter** ensures you have enough compute capacity for all pods
- **KEDA** scales the *number* of pods based on external events (queues, streams, time-based schedules)
- **VPA** right-sizes each pod's resource requests based on actual usage

Running all three together means **the right number of right-sized pods on the right amount of compute**.

### Safe integration: VPA + KEDA

VPA and KEDA are complementary but must be coordinated to avoid pod churn:

!!! warning "VPA + KEDA — Prevent Conflicts"

    When using VPA on workloads scaled by KEDA:
    
    - **Use VPA in `Off` mode** (recommendations only, no automatic pod evictions)
    - **Apply recommendations manually** during planned maintenance windows
    - This prevents VPA evictions from disrupting KEDA's scaling decisions
    
    See [VPA with KEDA](vpa.md#vpa-with-keda--safe-integration-pattern) for the full pattern.

## Enabling autoscaling

Each addon is feature-flagged on the cluster definition in the tenant repository:

```yaml
metadata:
  labels:
    enable_vpa: "true"                    # Vertical scaling — right-size pod requests
    enable_keda: "true"                   # Horizontal scaling — scale replicas on events
    enable_karpenter_nodepools: "true"    # Node scaling — auto-provision worker nodes
```

## Next steps

- [**VPA**](vpa.md) — enabling VPA, reading recommendations, applying changes safely, and safe integration with KEDA.
- [**KEDA**](keda.md) — enabling KEDA, customising Helm values, Prometheus integration, and end-to-end examples (scale-to-zero, cron, queue depth, CPU, hybrid patterns).
- [**Karpenter**](../../nodepools/karpenter.md) — node-level autoscaling for AWS/EKS.
