# KEDA — Kubernetes Event-Driven Autoscaling

### Operational & Developer Reference Guide

---

## Table of Contents

1. [What is KEDA?](#what-is-keda)
2. [Architecture & Components](#architecture-components)
3. [KEDA Metrics Server vs Standard Metrics Server](#keda-metrics-server-vs-standard-metrics-server)
4. [KEDA vs HPA with Custom Metrics](#keda-vs-hpa-with-custom-metrics)
5. [Enabling KEDA on a Cluster](#enabling-keda-on-a-cluster)
6. [Customising the KEDA Helm Values](#customising-the-keda-helm-values)
7. [Prometheus Integration](#prometheus-integration)
8. [Core CRDs](#core-crds)
9. [Scale-to-Zero Configuration](#scale-to-zero-configuration)
10. [HPA-Backed Scale-Up Configuration](#hpa-backed-scale-up-configuration)
11. [Authentication](#authentication-triggerauthentication)
12. [Example Configurations](#example-configurations)
13. [CPU-Based Scaling with KEDA](#cpu-based-scaling-with-keda)
14. [Time-Based Scaling — Scale to Zero on a Schedule](#time-based-scaling-scale-to-zero-on-a-schedule)
15. [Cron + CPU: schedule vs load](#cron-cpu-schedule-vs-load)
16. [Vertical Scaling — Pod Resource Requests (VPA + KEDA)](#vertical-scaling-pod-resource-requests-vpa-keda)
17. [Operational Commands & Debugging](#operational-commands-debugging)
18. [Known Constraints & Gotchas](#known-constraints-gotchas)
19. [When to Use KEDA vs Plain HPA](#when-to-use-keda-vs-plain-hpa)

---

## What is KEDA?

KEDA (Kubernetes Event-Driven Autoscaler) extends Kubernetes' native scaling capabilities to external event sources. While the standard Horizontal Pod Autoscaler (HPA) relies purely on internal resource metrics like CPU and memory, KEDA scales workloads based on external signals — queue depth, stream lag, HTTP request rate, Prometheus queries, cloud service triggers, and more.

Key capabilities:

- **Scale to zero** — drain replicas completely when idle, scale back up the moment events arrive
- **60+ built-in scalers** — Kafka, RabbitMQ, Redis, AWS SQS, Azure Service Bus, Prometheus, PostgreSQL, cron, and more
- **HPA integration** — KEDA does not replace HPA; it generates and manages HPA objects under the hood, feeding them event-driven metrics
- **Job scaling** — spawn and clean up Kubernetes Jobs in response to events via `ScaledJob`
- **Proactive scaling** — acts on queue depth or stream lag *before* CPU spikes, unlike reactive HPA polling

!!! note

    KEDA is a CNCF graduated project and is production-grade. It must be the **only** installed external metrics adapter in the cluster.

---

## Architecture & Components

```
External Event Source (e.g. Kafka, RabbitMQ, SQS)
        │
        ▼
  KEDA Scaler (monitors the event source)
        │
        ▼
  KEDA Metrics Adapter (exposes metrics at external.metrics.k8s.io)
        │
        ▼
  HPA Controller (reads metrics, decides replica count)
        │
        ▼
  Pods (scaled up / down / to zero)
```

When KEDA is installed by this platform, the following components run in the `keda-system` namespace:

| Container | Role |
|---|---|
| `keda-operator` | Manages CRDs, controls 0↔1 scaling (activation), connects to event sources |
| `keda-operator-metrics-apiserver` | Implements the External Metrics API; serves event-source metrics to the HPA |
| `keda-admission-webhooks` | Validates `ScaledObject` / `ScaledJob` resources at admission time |

KEDA dynamically creates and manages an HPA object for each `ScaledObject`. You do not manage that HPA directly.

---

## KEDA Metrics Server vs Standard Metrics Server

These are two distinct components serving different API paths — they coexist without conflict.

| | Standard Metrics Server | KEDA Metrics Server |
|---|---|---|
| **API group** | `metrics.k8s.io/v1beta1` | `external.metrics.k8s.io/v1beta1` |
| **Data source** | Kubelet (node/pod CPU & memory) | External systems (queues, streams, APIs) |
| **Used by** | `kubectl top`, HPA CPU/memory scaling | HPA event-driven scaling via KEDA |
| **Looks** | Inward — inside the cluster | Outward — outside the cluster |
| **Installed by** | Kubernetes cluster (or `metrics-server` chart) | KEDA Helm install |

!!! important

    For CPU and memory KEDA scalers, KEDA falls back to the standard Metrics Server (`metrics.k8s.io`). You still need the standard Metrics Server installed if you use resource-based triggers in KEDA.

!!! important

    Only one implementor of `external.metrics.k8s.io` is permitted per cluster. Running another custom adapter alongside KEDA will break metric resolution.

Query KEDA's external metrics directly:

```bash
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1"

# Query a specific scaler's metric value
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/<namespace>/<metric-name>?labelSelector=scaledobject.keda.sh/name=<scaledobject-name>"
```

---

## KEDA vs HPA with Custom Metrics

!!! note

    The comparison is not "KEDA vs HPA" — KEDA uses HPA internally. The real question is: **KEDA vs manually wiring HPA to a custom metrics adapter**.

| Capability | HPA + Custom Metrics Adapter | KEDA |
|---|---|---|
| Scale to zero | Minimum 1 replica | Minimum 0 replicas |
| Proactive (queue-depth) scaling | Lags — reacts after CPU spikes | Scales on queue length before CPU spikes |
| External event sources | Requires custom adapter per source | 60+ built-in scalers, zero adapter code |
| Auth to external systems | Ad hoc per adapter implementation | First-class `TriggerAuthentication` CRD |
| Multi-trigger logic | One HPA per metric, causes conflicts | Multiple triggers in a single ScaledObject |
| Job / batch scaling | Not supported | `ScaledJob` CRD |
| Config complexity | High — adapter config + HPA YAML | Low — single ScaledObject YAML |
| Cluster overhead | Minimal (native) | Low — one operator + metrics server pod |
| Config validation | Silent failures | Admission webhooks prevent conflicts |
| Estimated cost saving (batch) | Baseline | ~30% reduction via scale-to-zero |

**When plain HPA still wins:**

- CPU/memory metrics directly correlate with your load
- Simple stateless web service with gradual, predictable traffic
- You want zero additional cluster components
- You need something up quickly — HPA is native and well-documented

---

## Enabling KEDA on a Cluster

KEDA is delivered as a platform **Helm addon** (`addons/helm/oss.yaml`, `feature: keda`). It is **off by default** and enabled per cluster via a feature label on the cluster definition.

### Enable in the cluster definition

In the tenant repository, add the `enable_keda` label to the cluster definition:

```yaml
# <tenant_path>/clusters/<cluster_name>.yaml
metadata:
  labels:
    enable_keda: "true"
```

Argo CD will deploy KEDA as a system Helm application (for example `system-keda-<cluster_name>`) into the `keda-system` namespace.

### Verify the install

```bash
kubectl get pods -n keda-system
# Expected:
# keda-operator-xxxxx                          1/1   Running
# keda-operator-metrics-apiserver-xxxxx        1/1   Running
# keda-admission-webhooks-xxxxx                1/1   Running

# CRDs installed by KEDA
kubectl get crds | grep keda
```

### Prerequisites

- The standard **Metrics Server** is installed (required for the KEDA `cpu` / `memory` triggers).
- No other implementor of `external.metrics.k8s.io` is installed in the cluster.

---

## Customising the KEDA Helm Values

The platform ships default Helm values for KEDA under `config/keda/` in this repository. Tenants override or extend these values from their workloads repository using the same path layout.

### Value file layout

| File | Scope |
|---|---|
| `config/keda/all.yaml` | Defaults applied to **every** cluster that consumes this path |
| `config/keda/<cloud_vendor>.yaml` | Per-cloud defaults (for example `aws.yaml`, `azure.yaml`) |
| `config/keda/<cluster_name>.yaml` | Overrides for a **single** cluster (matches the cluster's `cluster_name` field) |

### Resolution order (precedence)

Values are layered; **more specific files override the same keys** from less specific ones. From **highest** to **lowest** precedence:

1. **Cluster-specific (workloads repo)**: `config/keda/<cluster_name>.yaml`
2. **Cloud-specific (workloads repo)**: `config/keda/<cloud_vendor>.yaml`
3. **Global tenant (workloads repo)**: `config/keda/all.yaml`
4. **Cloud-specific (platform repo)**: `config/keda/<cloud_vendor>.yaml`
5. **Global platform defaults (platform repo)**: `config/keda/all.yaml`

Missing files are ignored (`ignoreMissingValueFiles: true`). Maps are deep-merged by Helm; lists are replaced.

### What the platform defaults set

The platform `config/keda/all.yaml` ships with the following opinionated defaults:

- 3 replicas of the operator and the metrics API server, spread across nodes via `podAntiAffinity` on `kubernetes.io/hostname`
- Hardened pod / container security context (non-root, read-only filesystem, no privilege escalation, all capabilities dropped)

Per-workload scaling behaviour (cooldown, HPA `behavior`, `restoreToOriginalReplicaCount`, fallback, etc.) is **not** configured here — those fields live on the `ScaledObject` CRD under `spec.advanced` and are set by tenants on each `ScaledObject`. See the [KEDA ScaledObject spec](https://keda.sh/docs/latest/reference/scaledobject-spec/#advanced).

### Example — override replica count for a single cluster

```yaml
# <tenant_path>/config/keda/dev.yaml
operator:
  replicaCount: 1
metricsServer:
  replicaCount: 1
```

### Example — set a priority class for the KEDA control plane

```yaml
# <tenant_path>/config/keda/all.yaml
priorityClassName: system-cluster-critical
```

Refer to the [upstream `values.yaml`](https://github.com/kedacore/charts/blob/main/keda/values.yaml) for the complete list of supported keys.

---

## Prometheus Integration

KEDA exposes Prometheus metrics from each of its components (operator, metrics server, admission webhooks). To scrape them via the **Prometheus Operator** (kube-prometheus-stack), enable the chart's `prometheus.*` flags through `config/keda/...`.

### Metrics endpoints

Each component serves Prometheus metrics on its own port at `/metrics`:

| Component | Port | What you get |
|---|---|---|
| `keda-operator` | `8080` | `keda_scaler_active`, `keda_scaler_metrics_value`, `keda_scaled_object_errors_total`, `keda_resource_registered_total`, `keda_trigger_registered_total`, build info, scaling-loop latency |
| `keda-operator-metrics-apiserver` | `8080` | gRPC client metrics for the internal metrics service, plus the standard `apiserver_*` metrics |
| `keda-admission-webhooks` | `8080` | `keda_webhook_scaled_object_validation_total`, `keda_webhook_scaled_object_validation_errors` |

See the [KEDA Prometheus integration docs](https://keda.sh/docs/latest/integrations/prometheus/) for the full list.

### Enable ServiceMonitors

If the cluster runs `kube-prometheus-stack` (`enable_kube_prometheus_stack: "true"`), enable KEDA's `ServiceMonitor` resources so Prometheus discovers and scrapes each component.

```yaml
# <tenant_path>/config/keda/all.yaml
prometheus:
  metricServer:
    enabled: true                  # Expose Prometheus metrics on the metrics API server
    serviceMonitor:
      enabled: true                # Create a ServiceMonitor for it
      interval: 30s
      scrapeTimeout: 10s
      additionalLabels:
        # Label your kube-prometheus-stack Prometheus selects on.
        # Default selector for the chart is `release: <helm-release-name>`.
        release: kube-prometheus-stack

  operator:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      additionalLabels:
        release: kube-prometheus-stack

  webhooks:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      additionalLabels:
        release: kube-prometheus-stack
```

!!! note "Match the Prometheus selector"

    The `additionalLabels` value must match the `serviceMonitorSelector` configured on your Prometheus instance. Inspect it with:

    ```bash
    kubectl get prometheus -A -o yaml | yq '.items[].spec.serviceMonitorSelector'
    ```

    If you do not see your KEDA `ServiceMonitor` showing up as a target in Prometheus, the selector labels almost certainly do not match.

### Alternative: PodMonitors

If you prefer scraping pods directly (or you don't expose Services for the metrics ports), enable `podMonitor` instead:

```yaml
# <tenant_path>/config/keda/all.yaml
prometheus:
  operator:
    enabled: true
    podMonitor:
      enabled: true
      interval: 30s
      additionalLabels:
        release: kube-prometheus-stack
  metricServer:
    enabled: true
    podMonitor:
      enabled: true
      additionalLabels:
        release: kube-prometheus-stack
```

### Ship Prometheus alerting rules

The KEDA chart can also create a `PrometheusRule` resource for you. Define alerts under `prometheus.operator.prometheusRules`:

```yaml
# <tenant_path>/config/keda/all.yaml
prometheus:
  operator:
    enabled: true
    prometheusRules:
      enabled: true
      additionalLabels:
        release: kube-prometheus-stack
      alerts:
        - alert: KEDAScalerErrors
          annotations:
            summary: "KEDA scaler {{ $labels.scaler }} is erroring"
            description: "ScaledObject {{ $labels.scaledObject }} is hitting errors on scaler {{ $labels.scaler }}"
          expr: sum by (scaledObject, scaler) (rate(keda_scaler_detail_errors_total[5m])) > 0
          for: 5m
          labels:
            severity: warning

        - alert: KEDAOperatorDown
          annotations:
            summary: "KEDA operator is down"
            description: "No KEDA operator instance has been scraped for 5 minutes"
          expr: absent(up{job=~".*keda.*operator.*"} == 1)
          for: 5m
          labels:
            severity: critical
```

### Verify Prometheus is scraping KEDA

```bash
# ServiceMonitors created by the chart
kubectl get servicemonitor -n keda-system

# Confirm Prometheus selected them as scrape targets
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Browse to http://localhost:9090/targets and search for "keda"

# Sanity-check a metric
curl -s http://localhost:9090/api/v1/query?query=keda_build_info | jq .
```

### Pre-built Grafana dashboard

KEDA publishes a community Grafana dashboard alongside the project. Import [`keda-dashboard.json`](https://github.com/kedacore/keda/blob/main/config/grafana/keda-dashboard.json) and point it at your KEDA-scraping Prometheus datasource.

---

## Core CRDs

KEDA installs four Custom Resource Definitions:

| CRD | Scope | Purpose |
|---|---|---|
| `ScaledObject` | Namespace | Maps event sources to Deployments / StatefulSets |
| `ScaledJob` | Namespace | Spawns and cleans up Kubernetes Jobs on events |
| `TriggerAuthentication` | Namespace | Stores credentials for event sources |
| `ClusterTriggerAuthentication` | Cluster | Same as above, but available cluster-wide |

---

## ArgoCD Integration — Required `ignoreDifferences`

!!! warning "Critical: ArgoCD Sync and KEDA Scaling Conflicts"

    When deploying KEDA-scaled workloads with ArgoCD, you **must** add `ignoreDifferences` configuration to your Application definition. Without this, ArgoCD will continuously revert the replica count set by KEDA's autoscaler, causing a reconciliation loop where ArgoCD overwrites KEDA's scaling decisions.

### Why this is needed

KEDA (and the HPA it manages internally) dynamically updates the `spec.replicas` field on your Deployment based on scaling triggers. ArgoCD, by default, treats any deviation from the source manifest as a difference and will sync the Application back to the desired state, resetting `spec.replicas` to the value in Git. This creates a conflict: KEDA scales up/down, ArgoCD reverts it back.

### Solution: Add `ignoreDifferences` to your Application

In your ArgoCD Application definition, add the following to `spec.ignoreDifferences`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-keda-app
  namespace: argocd
spec:
  # ... other Application config ...
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

This tells ArgoCD to ignore changes to the replica count on Deployment resources, allowing KEDA full control over scaling.

### Example: Full Application with ignoreDifferences

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-keda-workload
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/my-repo
    targetRevision: HEAD
    path: workloads/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

### StatefulSet workloads

If you are using a `StatefulSet` instead of a Deployment, add an additional entry:

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/replicas
  - group: apps
    kind: StatefulSet
    jsonPointers:
      - /spec/replicas
```

### Important notes

- **Only the replica count is ignored** — all other Deployment fields (image, environment variables, resource requests, etc.) are still synced normally by ArgoCD.
- **Scope is Application-level** — this `ignoreDifferences` applies to all Deployments/StatefulSets managed by that Application. If you have multiple Applications, each needs its own configuration.
- **Not just KEDA** — this also applies if you are using plain HPA or any other scaling mechanism that modifies `spec.replicas` at runtime.

---

## Scale-to-Zero Configuration

KEDA uniquely allows `minReplicaCount: 0`. When no events are present, KEDA drains the deployment entirely. When an event arrives, KEDA scales from 0→1 (activation phase), then hands over to HPA for 1→N.

### Key ScaledObject Fields

| Field | Description |
|---|---|
| `minReplicaCount: 0` | Enables full scale-to-zero |
| `cooldownPeriod` | Seconds to wait after last event before scaling to zero (default: 300) |
| `pollingInterval` | How often KEDA checks the event source (default: 30s) |
| `activationLagThreshold` | Minimum event count required to leave zero (activation phase) |

### Example — Kafka consumer with scale-to-zero

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: kafka-consumer
    kind: Deployment
  minReplicaCount: 0        # Scale fully to zero when idle
  maxReplicaCount: 20
  cooldownPeriod: 300       # Wait 5 mins of silence before scaling to zero
  pollingInterval: 30
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka-bootstrap:9092
        consumerGroup: my-consumer-group
        topic: my-topic
        lagThreshold: "50"
        activationLagThreshold: "5"  # Need >5 messages to leave zero
      authenticationRef:
        name: kafka-trigger-auth
```

---

## HPA-Backed Scale-Up Configuration

Once a workload is active (replica count ≥ 1), the HPA controller takes over scaling from 1→N. You can control scale-up and scale-down velocity through the `advanced.horizontalPodAutoscalerConfig.behavior` block.

### Recommended Pattern — Aggressive up, conservative down

```yaml
spec:
  advanced:
    restoreToOriginalReplicaCount: true
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 0       # React immediately
          policies:
            - type: Percent
              value: 100                      # Double replicas every 15s if needed
              periodSeconds: 15
        scaleDown:
          stabilizationWindowSeconds: 300     # Wait 5 mins before reducing
          policies:
            - type: Percent
              value: 50                       # Remove at most 50% per minute
              periodSeconds: 60
```

### Cron + Event Hybrid — Pre-scale for known peaks

```yaml
triggers:
  - type: cron
    metadata:
      timezone: Europe/London
      start: "0 8 * * 1-5"      # Scale up weekday mornings
      end: "0 20 * * 1-5"
      desiredReplicas: "10"
  - type: kafka                  # Also respond to real queue depth
    metadata:
      bootstrapServers: kafka-bootstrap:9092
      consumerGroup: my-consumer-group
      topic: my-topic
      lagThreshold: "100"
```

When multiple triggers are defined, the **highest** desired replica count wins.

### Prometheus-based scale-up (HTTP rate)

```yaml
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-server.monitoring.svc:9090
      metricName: http_requests_per_second
      query: sum(rate(http_requests_total[1m]))
      threshold: "100"
```

---

## Authentication (TriggerAuthentication)

Use `TriggerAuthentication` to securely supply credentials to scalers. This is preferred over embedding credentials directly in the `ScaledObject`.

### Secret-based auth

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: kafka-trigger-auth
  namespace: default
spec:
  secretTargetRef:
    - parameter: sasl
      name: kafka-secrets
      key: sasl-mechanism
    - parameter: username
      name: kafka-secrets
      key: username
    - parameter: password
      name: kafka-secrets
      key: password
```

Reference in your ScaledObject:

```yaml
triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka-bootstrap:9092
      consumerGroup: my-consumer-group
      topic: my-topic
      lagThreshold: "100"
    authenticationRef:
      name: kafka-trigger-auth
```

### Cloud pod identity (AWS / Azure / GCP)

KEDA natively supports workload identity federation — no secrets required:

```yaml
spec:
  podIdentity:
    provider: aws        # or: azure, gcp, azure-workload
```

For cluster-wide shared credentials use `ClusterTriggerAuthentication` with `kind: ClusterTriggerAuthentication` in the `authenticationRef`.

---

## Example Configurations

### RabbitMQ Queue Worker

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: rabbitmq-worker
  namespace: default
spec:
  scaleTargetRef:
    name: rabbitmq-worker
  minReplicaCount: 0
  maxReplicaCount: 30
  cooldownPeriod: 300
  pollingInterval: 10
  triggers:
    - type: rabbitmq
      metadata:
        queueName: task-queue
        mode: QueueLength
        value: "10"
        activationValue: "1"
      authenticationRef:
        name: rabbitmq-auth
```

### AWS SQS Batch Processor

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: sqs-batch-processor
  namespace: default
spec:
  jobTargetRef:
    parallelism: 1
    completions: 1
    backoffLimit: 3
    template:
      spec:
        containers:
          - name: processor
            image: my-batch-processor:latest
        restartPolicy: Never
  pollingInterval: 30
  minReplicaCount: 0
  maxReplicaCount: 50
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 5
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.eu-west-1.amazonaws.com/123456789/my-queue
        queueLength: "5"
        awsRegion: eu-west-1
      authenticationRef:
        name: aws-pod-identity-auth
```

### Multi-trigger with ScalingModifiers

```yaml
spec:
  advanced:
    scalingModifiers:
      formula: "kafka_lag / 100 + prometheus_rps / 50"
      target: "10"
      activationTarget: "1"
      metricType: AverageValue
  triggers:
    - name: kafka_lag
      type: kafka
      metadata:
        topic: events
        lagThreshold: "1"
    - name: prometheus_rps
      type: prometheus
      metadata:
        query: sum(rate(http_requests_total[1m]))
        threshold: "1"
```

---

## CPU-Based Scaling with KEDA

KEDA supports CPU-based scaling through its built-in `cpu` scaler, which proxies to the standard Kubernetes Metrics Server (not the KEDA external metrics adapter). This behaves similarly to plain HPA CPU scaling, but with the added benefit of being expressed as a `ScaledObject` — meaning you can combine it with other KEDA triggers in a single resource.

!!! note "Prerequisite"

    The standard Kubernetes Metrics Server must be installed. KEDA's CPU scaler reads from `metrics.k8s.io`, not from KEDA's own external metrics endpoint.

!!! warning "Note on scale-to-zero"

    CPU-based triggers cannot scale a workload to zero because if there are no pods, there is no CPU metric to read. If you need scale-to-zero, combine the CPU trigger with a second trigger (e.g. cron or queue-depth) that can drive replicas to zero.

### How it works

The `cpu` scaler targets an average CPU utilisation percentage across all pods in the deployment. When average utilisation exceeds the threshold, KEDA instructs the HPA to add replicas. When it drops, replicas are reduced — down to `minReplicaCount` (minimum 1 for CPU-only triggers).

### Example — Scale on CPU utilisation

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cpu-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: my-api
    kind: Deployment
  minReplicaCount: 2        # Cannot be 0 with CPU-only trigger
  maxReplicaCount: 20
  pollingInterval: 15       # Check every 15 seconds
  cooldownPeriod: 60
  triggers:
    - type: cpu
      metricType: Utilization   # AverageValue or Utilization
      metadata:
        value: "60"             # Target 60% average CPU utilisation
```

### Example — CPU trigger combined with queue depth (recommended pattern)

Combining CPU with a queue trigger gives you reactive scale-up on CPU pressure *and* proactive scale-up on queue depth. The highest desired replica count from any trigger wins.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: api-worker-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: api-worker
    kind: Deployment
  minReplicaCount: 1
  maxReplicaCount: 30
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 0
          policies:
            - type: Percent
              value: 100
              periodSeconds: 15
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Percent
              value: 25
              periodSeconds: 60
  triggers:
    - type: cpu
      metricType: Utilization
      metadata:
        value: "70"             # Scale up if avg CPU exceeds 70%
    - type: rabbitmq
      metadata:
        queueName: work-queue
        mode: QueueLength
        value: "20"             # Also scale up if queue exceeds 20 messages
      authenticationRef:
        name: rabbitmq-auth
```

If you combine **`cpu` with `cron`** (for example scale to zero on weekends while scaling on CPU during the week), both triggers still feed **one** KEDA-managed HPA; Kubernetes takes the **maximum** of the replica counts each metric implies. There is no separate CPU autoscaler “arguing” with cron. For behaviour across inactive windows, `minReplicaCount: 0`, and strict off-hours policies, see [Cron + CPU: schedule vs load](#cron-cpu-schedule-vs-load).

### `metricType` options

| metricType | Behaviour |
|---|---|
| `Utilization` | Target average CPU as a percentage of the pod's CPU request (e.g. `"60"` = 60%) |
| `AverageValue` | Target an absolute average CPU value in millicores (e.g. `"500m"`) |

### Memory scaling

The `memory` scaler works identically to `cpu`, substituting memory utilisation:

```yaml
triggers:
  - type: memory
    metricType: Utilization
    metadata:
      value: "75"             # Scale if average memory utilisation exceeds 75%
```

---

## Time-Based Scaling — Scale to Zero on a Schedule

The KEDA `cron` trigger scales workloads based on a time schedule using standard cron expressions. This is the correct approach for:

- Scaling dev/staging environments to zero overnight and at weekends
- Pre-scaling production services ahead of known peak hours
- Hard-stopping batch processors outside of business hours

The cron trigger works by expressing a desired replica count for a given time window. When the window opens, KEDA scales to `desiredReplicas`. When it closes, KEDA reverts to `minReplicaCount` — which can be `0`.

### Cron expression format

```
"minute hour day-of-month month day-of-week"

Examples:
"0 18 * * *"      → 6:00 PM every day
"0 8 * * 1-5"     → 8:00 AM Monday–Friday
"0 0 * * 6,0"     → Midnight Saturday and Sunday
"30 7 * * 1-5"    → 7:30 AM weekdays
```

### Example — Scale to zero between 6PM and 8AM every day

This is the most common overnight cost-saving pattern. The workload runs during business hours and is fully drained outside of them.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: overnight-scale-to-zero
  namespace: default
spec:
  scaleTargetRef:
    name: my-service
    kind: Deployment
  minReplicaCount: 0        # Allow full scale-to-zero
  maxReplicaCount: 10
  triggers:
    # Window 1: business hours — scale UP to 3 replicas
    - type: cron
      metadata:
        timezone: Europe/London   # Always specify — defaults to UTC otherwise
        start: "0 8 * * *"        # 8:00 AM every day
        end: "0 18 * * *"         # 6:00 PM every day
        desiredReplicas: "3"

    # Window 2: outside business hours — scale to zero
    # (implicit — minReplicaCount: 0 applies when no cron window is active)
```

!!! note "How the off-window works"

    You only need to define the *active* window. When no cron trigger is firing and there are no other active triggers, KEDA scales down to `minReplicaCount`. Setting `minReplicaCount: 0` means the workload reaches zero automatically outside the defined window. You do not need a second cron entry for the off period.

### Example — Weekdays only, with weekend scale-to-zero

```yaml
triggers:
  - type: cron
    metadata:
      timezone: Europe/London
      start: "0 8 * * 1-5"     # 8 AM Monday–Friday
      end: "0 18 * * 1-5"      # 6 PM Monday–Friday
      desiredReplicas: "5"
```

At 6 PM Friday, KEDA scales to zero. At 8 AM Monday, it scales back to 5. The weekend is fully zero-cost.

### Example — Staged scaling across the day (peak hours)

Use multiple cron triggers to express different replica targets throughout the day. KEDA takes the highest desired count from any currently-active trigger.

```yaml
triggers:
  # Off-peak morning ramp
  - type: cron
    metadata:
      timezone: Europe/London
      start: "0 7 * * 1-5"
      end: "0 9 * * 1-5"
      desiredReplicas: "3"

  # Peak hours
  - type: cron
    metadata:
      timezone: Europe/London
      start: "0 9 * * 1-5"
      end: "0 17 * * 1-5"
      desiredReplicas: "10"

  # Evening wind-down
  - type: cron
    metadata:
      timezone: Europe/London
      start: "0 17 * * 1-5"
      end: "0 20 * * 1-5"
      desiredReplicas: "3"

  # Overnight and weekends → minReplicaCount: 0 applies (scale to zero)
```

### Example — Cron + event trigger hybrid (production-safe pattern)

For production services, you typically want a guaranteed minimum during business hours *and* the ability to scale beyond that on real traffic. Combining cron with a metric trigger achieves this:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: production-hybrid-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: api-service
    kind: Deployment
  minReplicaCount: 0          # Allow zero outside business hours
  maxReplicaCount: 50
  triggers:
    # Guarantee a baseline during business hours
    - type: cron
      metadata:
        timezone: Europe/London
        start: "0 8 * * 1-5"
        end: "0 18 * * 1-5"
        desiredReplicas: "5"   # Minimum 5 replicas during the day

    # Scale further based on actual queue depth
    - type: rabbitmq
      metadata:
        queueName: api-requests
        mode: QueueLength
        value: "10"            # 1 replica per 10 queued requests
      authenticationRef:
        name: rabbitmq-auth

    # Scale further based on CPU if traffic spikes
    - type: cpu
      metricType: Utilization
      metadata:
        value: "65"
```

**Result:** Outside business hours with an empty queue and low CPU, the service scales to zero. During business hours, it holds at least 5 replicas. If traffic spikes beyond what 5 replicas can handle, queue depth and CPU triggers push it higher — up to 50.

### Cron + CPU: schedule vs load {#cron-cpu-schedule-vs-load}

A common question is whether a **weekend / overnight “off” schedule** (`cron` + `minReplicaCount: 0`) will **fight** **CPU-based** scaling.

**They do not run as two separate autoscalers.** Cron and CPU are **triggers on the same `ScaledObject`**, and KEDA still creates **one** managed HPA for that object. Each trigger contributes a metric; the HPA evaluates the replica count implied by **each** metric and adopts the **maximum** — the same “highest desired replica count wins” rule described for other multi-trigger setups ([HPA-backed scale-up](#hpa-backed-scale-up-configuration), [CPU + queue example](#cpu-based-scaling-with-keda)). That is coordination, not two controllers overwriting each other. The case that *does* cause fights is a **second, manually created HPA** on the same workload ([Known constraints](#known-constraints-gotchas)).

**How to read it operationally**

| Situation | What usually happens |
|---|---|
| Cron window **active** (`desiredReplicas` set), traffic is low | Cron sets a **floor** at least that high; CPU is satisfied or also drives replicas — you get `max(cron, cpu)` capped by `maxReplicaCount`. |
| Cron window **active**, traffic is high | CPU can push replicas **above** the cron baseline up to `maxReplicaCount`. |
| Cron window **inactive**, `minReplicaCount: 0`, **no pods** | There is no CPU utilisation to measure; the workload can stay at **zero** unless another trigger can activate scale-from-zero (for example queue depth). |
| Cron window **inactive**, but **pods are running** | CPU (and any other triggers) can still recommend replicas. Autoscaling alone cannot enforce a “hard” blackout if something keeps pods alive—use pausing (`autoscaling.keda.sh/paused`), ingress or policy controls, or remove other scale-from-zero triggers if you need a strict off window. |

**Practical pattern:** Use `cron` for a **time-based baseline** during known hours (for example weekdays 08:00–18:00) and `cpu` for **burst scaling on top**. Use `minReplicaCount` and any non-CPU triggers to define behaviour outside those windows (for example full scale-to-zero on nights and weekends).

### Cron timezone reference

Always specify `timezone` explicitly. KEDA defaults to UTC if omitted, which will misfire in any non-UTC environment.

| Region | Timezone string |
|---|---|
| UK / Ireland | `Europe/London` |
| Central Europe | `Europe/Berlin` / `Europe/Paris` |
| US Eastern | `America/New_York` |
| US Pacific | `America/Los_Angeles` |
| India | `Asia/Kolkata` |
| Singapore / HKT | `Asia/Singapore` |

Valid timezone strings follow the IANA tz database format. Full list: [List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

---

## Vertical Scaling — Pod Resource Requests (VPA + KEDA)

!!! important "Important distinction"

    KEDA is a *horizontal* scaler — it controls the *number* of pods, not their size. Changing pod CPU/memory requests is *vertical* scaling, which is the domain of the **Vertical Pod Autoscaler (VPA)**. These are complementary tools, not alternatives.

| Tool | What it changes |
|---|---|
| KEDA / HPA | Number of replicas |
| VPA | CPU and memory requests per pod |
| Both together | Right-sized pods at the right replica count |

### Why you might want both

Without VPA, pod resource requests are static — set at deploy time and never adjusted. If you over-provision requests (common, to avoid OOMKills), you pay for headroom on every replica that KEDA spins up. VPA continuously analyses actual usage and recommends (or applies) tighter requests, meaning each KEDA-spawned replica costs less.

### How to run VPA alongside KEDA safely

The key risk is that VPA in `Auto` mode **restarts pods** to apply new resource sizes. This can conflict with KEDA's scaling decisions, causing unexpected pod churn. The safe pattern is to run VPA in `Off` mode (recommendations only) and apply changes during planned maintenance windows or through a GitOps pipeline.

```
KEDA  → controls replica count (horizontal)
VPA   → recommends resource sizes (vertical, apply manually or via pipeline)
```

### Installing VPA

```bash
# Install VPA from the Kubernetes autoscaler repo
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vertical-pod-autoscaler.yaml

# Verify
kubectl get pods -n kube-system | grep vpa
```

### VPA in recommendation-only mode (safe with KEDA)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-service-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-service          # Must match the deployment KEDA is scaling
  updatePolicy:
    updateMode: "Off"         # Recommendations only — no automatic restarts
  resourcePolicy:
    containerPolicies:
      - containerName: my-service
        minAllowed:
          cpu: 100m
          memory: 128Mi
        maxAllowed:
          cpu: 4
          memory: 4Gi
        controlledResources: [cpu, memory]
```

### Reading VPA recommendations

```bash
kubectl describe vpa my-service-vpa -n default
```

Output excerpt:

```
Recommendation:
  Container Recommendations:
    Container Name: my-service
    Lower Bound:
      cpu:    180m
      memory: 210Mi
    Target:                     ← apply this to your deployment
      cpu:    350m
      memory: 410Mi
    Upper Bound:
      cpu:    1200m
      memory: 1500Mi
```

Apply the `Target` values to your Deployment's resource requests. KEDA will then scale the right-sized pods horizontally.

### Complete KEDA + VPA pattern

```yaml
# 1. Deployment — resource requests informed by VPA recommendations
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
  namespace: default
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: my-service
          image: my-service:latest
          resources:
            requests:
              cpu: 350m       # From VPA Target recommendation
              memory: 410Mi
            limits:
              cpu: 1000m
              memory: 1Gi
---
# 2. KEDA ScaledObject — controls replica count
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-service-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: my-service
  minReplicaCount: 0
  maxReplicaCount: 20
  triggers:
    - type: cron
      metadata:
        timezone: Europe/London
        start: "0 8 * * 1-5"
        end: "0 18 * * 1-5"
        desiredReplicas: "3"
    - type: rabbitmq
      metadata:
        queueName: work-queue
        mode: QueueLength
        value: "10"
      authenticationRef:
        name: rabbitmq-auth
---
# 3. VPA — monitors and recommends right-sized requests
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-service-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-service
  updatePolicy:
    updateMode: "Off"         # Safe — recommendations only, no restarts
```

### VPA + KEDA constraints

| Constraint | Detail |
|---|---|
| **Don't use VPA `Auto` mode with KEDA** | VPA `Auto` restarts pods to resize them, which disrupts KEDA-managed scaling and can cause replica count oscillation |
| **VPA and HPA cannot both control CPU/memory on the same deployment** | If VPA manages CPU requests, do not use a KEDA CPU trigger on the same deployment — they will conflict |
| **VPA needs history to be accurate** | VPA recommendations improve over time; give it at least a few days of traffic data before applying changes |
| **`Off` mode requires manual application** | You must read the VPA recommendation and update the Deployment manifest yourself (or via pipeline) |

---

## Operational Commands & Debugging

### Status checks

```bash
# KEDA component health
kubectl get pods -n keda-system

# All ScaledObjects across the cluster
kubectl get scaledobject -A

# Detailed state of a specific ScaledObject
kubectl describe scaledobject <name> -n <namespace>

# HPA objects created by KEDA
kubectl get hpa -A

# All ScaledJobs
kubectl get scaledjob -A

# TriggerAuthentication resources
kubectl get triggerauthentication -A
```

### Logs

```bash
# KEDA operator (scaling decisions, activation events)
kubectl logs -n keda-system -l app=keda-operator -f

# KEDA metrics server (metric fetch errors)
kubectl logs -n keda-system -l app=keda-operator-metrics-apiserver -f
```

### Metrics inspection

```bash
# List all external metrics exposed by KEDA
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1"

# Query a specific metric value
kubectl get --raw \
  "/apis/external.metrics.k8s.io/v1beta1/namespaces/<namespace>/<metric-name>?labelSelector=scaledobject.keda.sh/name=<scaledobject-name>"
```

### Pausing autoscaling (maintenance)

```bash
# Pause a ScaledObject
kubectl annotate scaledobject <name> autoscaling.keda.sh/paused=true

# Resume
kubectl annotate scaledobject <name> autoscaling.keda.sh/paused- --overwrite
```

### ScaledObject status fields to watch

```
READY    — KEDA is successfully reading the event source
ACTIVE   — at least one trigger is above its activation threshold
FALLBACK — KEDA cannot reach the event source; using fallback replica count
PAUSED   — autoscaling is suspended
```

---

## Known Constraints & Gotchas

| Constraint | Detail |
|---|---|
| **One external metrics adapter only** | KEDA must be the sole implementor of `external.metrics.k8s.io`. Running another adapter alongside it will break metric resolution. |
| **Don't mix KEDA + manual HPA** | Never create a separate HPA targeting the same Deployment as a ScaledObject. KEDA manages the HPA internally — a second HPA will conflict and cause erratic scaling. |
| **CPU/memory scalers still need standard Metrics Server** | KEDA's CPU and memory triggers proxy to `metrics.k8s.io`, not `external.metrics.k8s.io`. Ensure standard Metrics Server is installed. |
| **Cold-start latency** | Scaling from 0→1 incurs pod scheduling and startup time. For latency-sensitive workloads consider `minReplicaCount: 1`. |
| **`cooldownPeriod` only applies to 0-scale** | The cooldown period only governs the transition to zero replicas. Scale-down between `n` and `m` (where both ≥ 1) is controlled by the HPA stabilisation window. |
| **Resource quotas** | KEDA can scale rapidly. Ensure namespace resource quotas are defined to prevent unexpected overconsumption. |
| **`ScaledJob` has no HPA** | Unlike `ScaledObject`, `ScaledJob` does not create an HPA. KEDA's controller manages job parallelism directly. |

---

## When to Use KEDA vs Plain HPA

```
Is your scaling signal external to the cluster?
(queue depth, stream lag, cloud service metrics)
        │
        ├── YES ──► Use KEDA
        │
        └── NO
              │
              ▼
        Do you need scale-to-zero?
              │
              ├── YES ──► Use KEDA
              │
              └── NO
                    │
                    ▼
              Is CPU/memory a reliable proxy for your load?
                    │
                    ├── YES ──► Plain HPA is sufficient
                    │
                    └── NO ──► Use KEDA with Prometheus or custom metric trigger
```

**Use KEDA for:**

- Queue-based workers (RabbitMQ, SQS, Kafka)
- Bursty or intermittent batch jobs
- Event-driven microservices
- Dev/staging environments (scale to zero saves cost)
- Any workload where CPU is a lagging or irrelevant indicator

**Stick with plain HPA for:**

- Stateless HTTP APIs where CPU tracks load well
- Gradual, predictable traffic growth
- Teams wanting minimal cluster complexity

---

*Based on KEDA 2.19 — see the upstream [KEDA documentation](https://keda.sh/docs/) for the authoritative reference.*
