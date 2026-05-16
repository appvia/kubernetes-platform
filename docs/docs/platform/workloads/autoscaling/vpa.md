# VPA — Vertical Pod Autoscaler

### Operational & Developer Reference Guide

---

## Table of Contents

1. [What is VPA?](#what-is-vpa)
2. [Architecture & Components](#architecture--components)
3. [Update Modes Explained](#update-modes-explained)
4. [Enabling VPA on a Cluster](#enabling-vpa-on-a-cluster)
5. [GitOps Integration — VPA with ArgoCD](#gitops-integration--vpa-with-argocd)
6. [Customising the VPA Helm Values](#customising-the-vpa-helm-values)
7. [Core CRD — VerticalPodAutoscaler](#core-crd--verticalpodautoscaler)
8. [Common Examples](#common-examples)
9. [Application Team Runbook — Using VPA in Your Workloads](#application-team-runbook--using-vpa-in-your-workloads)
10. [VPA with KEDA — Safe Integration Pattern](#vpa-with-keda--safe-integration-pattern)
11. [Reading & Applying Recommendations](#reading--applying-recommendations)
12. [Operational Commands & Debugging](#operational-commands--debugging)
13. [Known Constraints & Gotchas](#known-constraints--gotchas)

---

## What is VPA?

The **Vertical Pod Autoscaler (VPA)** adjusts the CPU and memory **requests** (and optionally limits) on running pods based on observed resource usage. Unlike KEDA or HPA, which scale the _number_ of replicas, VPA sizes the _resources per pod_.

### Why you need VPA

In practice, setting resource requests is hard:

- **Over-provision** → pay for unused headroom on every pod
- **Under-provision** → risk OOMKills or CPU throttling
- **Static requests** → don't adapt as traffic patterns change

VPA continuously samples actual pod resource usage and recommends tighter, more accurate requests. Over time, this means each pod costs less while remaining stable.

### Key capabilities

- **Recommendation engine** — analyzes historical CPU/memory usage and suggests right-sized requests
- **Safe update modes** — apply recommendations automatically (`Auto`), manually (`Off`), or by draining and replacing pods (`Recreate`)
- **Resource bounds** — define min/max allowed requests so recommendations don't violate your constraints
- **Checkpoint history** — persists historical data so recommendations improve even after pod restarts
- **Selective targeting** — apply VPA to specific containers or deployments while excluding others

### Production-safe pattern

For workloads scaled by KEDA (or any other autoscaler), the production-safe pattern is:

```
VPA in "Off" mode (recommendations only)
      ↓
Operator / pipeline manually reads recommendations
      ↓
Updates deployment requests during planned maintenance
      ↓
KEDA/HPA scales the right-sized pods horizontally
```

This decouples VPA recommendation cycles from KEDA's horizontal scaling decisions, avoiding pod churn.

---

## Architecture & Components

VPA is deployed as three independent components running in the `kube-system` namespace (default):

```
Pod Resource Usage (kubelet metrics)
        │
        ▼
  VPA Recommender (analyzes usage, computes recommendations)
        │
        ▼
  VPA Updater (optionally applies or evicts pods to apply changes)
        │
        ▼
  VPA Admission Controller (validates VPA resources, prevents conflicts)
        │
        ▼
  Pod is resized (auto, recreated, or manually updated)
```

| Component                | Replica Count | Role                                                                                                  |
| ------------------------ | ------------- | ----------------------------------------------------------------------------------------------------- |
| **Recommender**          | 2 (HA)        | Monitors pod metrics; computes and stores recommendations                                             |
| **Updater**              | 2 (HA)        | In `Auto`/`Recreate` modes, evicts and replaces pods to apply new resource sizes                      |
| **Admission Controller** | 2 (HA)        | Validates `VerticalPodAutoscaler` resources; prevents simultaneous updates; stores checkpoint history |

All three components are hardened by default (non-root, read-only filesystem, no capabilities). Memory usage is constrained to prevent the control plane from scaling out of control.

---

## Update Modes Explained

The VPA CRD has an `updatePolicy.updateMode` field that controls _how_ recommendations are applied:

### `Off` — Recommendations Only (Safe with KEDA)

```yaml
updatePolicy:
  updateMode: "Off"
```

**Behaviour:** VPA analyzes usage and emits recommendations; **no automatic changes**. You must manually read the recommendations and update your Deployment manifest.

**When to use:**

- Workloads scaled by KEDA or other autoscalers (avoids disruptive restarts during scaling events)
- Production systems where pod restarts carry risk
- Teams wanting full control over when changes happen
- Any workload where you want to batch recommendation updates with other deployment changes

**How to apply recommendations:**

```bash
# 1. View the recommendation
kubectl describe vpa <name> -n <namespace>

# 2. Update your Deployment manifest with the "Target" values
# 3. Apply via GitOps or kubectl apply
```

**Example:**

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
    name: my-service
  updatePolicy:
    updateMode: "Off" # ← Recommendations only
  resourcePolicy:
    containerPolicies:
      - containerName: my-service
        minAllowed:
          cpu: 100m
          memory: 128Mi
        maxAllowed:
          cpu: 2
          memory: 2Gi
```

### `Initial` — Only on Pod Creation

```yaml
updatePolicy:
  updateMode: "Initial"
```

**Behaviour:** VPA applies recommendations **only to newly created pods**. Existing pods keep their original requests.

**When to use:**

- Workloads with frequent pod churn (rollouts, job completions) — new pods are automatically right-sized
- Minimizes disruption to long-lived pods
- Good middle ground between `Off` and `Auto`

**Caveat:** If your Deployment has a long lifecycle without updates, pods retain stale requests. Combine with regular redeployments to benefit from updated recommendations.

### `Recreate` — Evict and Restart (Disruptive)

```yaml
updatePolicy:
  updateMode: "Recreate"
```

**Behaviour:** When a recommendation diverges significantly from the current request, VPA evicts the pod (respecting `PodDisruptionBudget`), triggering a restart with new requests.

**When to use:**

- Stateless, fault-tolerant workloads (e.g., API servers, job workers)
- Non-critical services or dev/staging environments
- Workloads with very short lifespans (recommendations become stale quickly)

**Risk:** Pod restarts can cause brief service interruptions and disrupt KEDA scaling decisions.

### `Auto` — Immediate Update (Most Disruptive)

```yaml
updatePolicy:
  updateMode: "Auto"
```

**Behaviour:** VPA immediately evicts pods as soon as a new recommendation differs from the current request, without waiting for pod age or scaling stability.

**When to use:**

- **NOT recommended** in production
- Dev/staging only, where pod churn is acceptable
- Workloads with no availability constraints

**Why avoid with KEDA:** VPA `Auto` can evict pods mid-scaling cycle, causing unexpected replica oscillation and service disruptions.

---

## Enabling VPA on a Cluster

VPA is delivered as a platform **Helm addon** (`addons/helm/oss.yaml`, `feature: vpa`). It is **off by default** and enabled per cluster via a feature label.

### Enable in the cluster definition

In the tenant repository, add the `enable_vpa` label:

```yaml
# <tenant_path>/clusters/<cluster_name>.yaml
metadata:
  labels:
    enable_vpa: "true"
```

Argo CD will deploy VPA as a system Helm application (e.g., `system-vpa-<cluster_name>`) into the `kube-system` namespace.

### Verify the install

```bash
kubectl get pods -n kube-system | grep vpa
# Expected output:
# vpa-admission-controller-xxxxx        1/1   Running
# vpa-recommender-xxxxx                 1/1   Running
# vpa-updater-xxxxx                     1/1   Running

# Verify CRD is installed
kubectl get crd | grep verticalpodautoscaler

# Check VPA version
kubectl get deployment -n kube-system vpa-recommender -o yaml | grep image
```

### Prerequisites

- **Metrics Server must be installed** — VPA reads pod resource usage from kubelet metrics (`metrics.k8s.io`). The standard Kubernetes Metrics Server is required and should already be deployed on the platform.

---

## GitOps Integration — VPA with ArgoCD

!!! info "Critical: Ignore Resource Requests to Allow VPA and ArgoCD to Co-exist"

    When using VPA in `Auto` or `Recreate` modes alongside ArgoCD, you **MUST** add `ignoreDifferences` to your application definition to prevent ArgoCD from reverting VPA's resource adjustments. This tells ArgoCD to ignore drift in resource requests/limits fields, allowing VPA to manage them freely.

    **Example:**
    ```yaml
    helm:
      path: <PATH_TO_HELM_CHART>
      repository: <REPO_URL>
      version: main

    sync:
      ## The order in which to deploy the application
      phase: primary
      ## The duration to wait before retrying the application
      duration: 60s
      ## The maximum duration to wait before retrying the application
      max_duration: 2m

    ignoreDifferences:
      - group: apps
        kind: Deployment
        jsonPointers:
          # Allow KEDA to scale the deployment without ArgoCD
          # considering it a drift
          - /spec/replicas
          # Allow VPA to adjust the resource requests without
          # ArgoCD considering it a drift
          - /spec/template/spec/containers/0/resources/requests
    ```

    **Without this**, ArgoCD will continuously revert VPA's changes, causing conflicts and preventing VPA from functioning correctly. See [Approach 2](#approach-2-pragmatic-argocds-ignoredifferences) below for more details.

---

This platform uses **ArgoCD as the GitOps source of truth**. When VPA runs in "Off" mode (recommendations only), the key question is: **how do recommendations get applied to your manifests?**

VPA recommendations live **only in the cluster** (in the VPA resource's `.status.recommendation` field). Your Deployment manifests live in **git**. This is a clean separation of concerns — VPA advises, but developers decide when to apply.

### The Problem: ArgoCD Reverts In-Cluster Changes

If you manually apply VPA recommendations in-cluster without updating git, ArgoCD will revert them:

```
Git manifest: cpu: 100m, memory: 256Mi
       ↓
ArgoCD syncs: Cluster = Git
       ↓
You apply VPA recommendation: cpu: 250m, memory: 320Mi (in-cluster)
       ↓
ArgoCD detects drift on next sync
       ↓
ArgoCD reverts: cpu: 100m, memory: 256Mi (back to git)
```

### Two Practical Approaches

#### **Approach 1 (Recommended): Off Mode + Developer Responsibility**

Use VPA in `Off` mode (recommendations only, no automatic changes). **Developers own reading recommendations and updating their manifests.**

```
VPA runs and recommends
       ↓
Developer views: kubectl describe vpa <name>
       ↓
Developer updates manifest in git with new requests
       ↓
Developer commits and pushes
       ↓
ArgoCD deploys the updated manifest
       ↓
Everything in git, cluster stays in sync
```

**Setup:**

1. **Always deploy workloads with baseline requests** (never omit them):

   ```yaml
   spec:
     template:
       spec:
         containers:
           - name: my-service
             resources:
               requests:
                 cpu: 100m # Conservative baseline
                 memory: 256Mi
               limits:
                 cpu: 1000m
                 memory: 1Gi
   ```

2. **Create a VPA in Off mode:**

   ```yaml
   apiVersion: autoscaling.k8s.io/v1
   kind: VerticalPodAutoscaler
   metadata:
     name: my-service-vpa
   spec:
     targetRef:
       kind: Deployment
       name: my-service
     updatePolicy:
       updateMode: "Off" # ← Recommendations only
     resourcePolicy:
       containerPolicies:
         - containerName: my-service
           minAllowed:
             cpu: 50m
             memory: 128Mi
           maxAllowed:
             cpu: 4
             memory: 4Gi
   ```

3. **Developer workflow:**
   - VPA generates recommendations (after 2–5 days of history)
   - Developer reads: `kubectl describe vpa my-service-vpa`
   - Developer updates deployment manifest in their workload repo
   - Commits and pushes
   - ArgoCD deploys
   - Done — git stays accurate

**Pros:**

- ✅ Git is the true source of truth
- ✅ Full audit trail (changes are in git history)
- ✅ Developers review changes before applying (they own resource decisions)
- ✅ Simple to understand and operate
- ✅ No automation complexity
- ✅ Works seamlessly with ArgoCD (no ignoring differences)

**Cons:**

- ⚠ Requires developer discipline (they must remember to check and update)
- ⚠ Recommendations don't auto-apply
- ⚠ Best effort — some teams may skip or delay updates

---

#### **Approach 2 (Pragmatic): ArgoCD `ignoreDifferences`**

Tell ArgoCD to **ignore resource request/limit fields**. VPA can apply changes in-cluster freely; ArgoCD won't revert them.

On this platform, add `ignoreDifferences` directly to your helm application definition:

```yaml
# workloads/applications/my-service/dev.yaml
helm:
  repository: https://charts.example.com
  version: 1.0.0
  release_name: my-service
  values: |
    key: value

# Tell ArgoCD to ignore resource fields — let VPA manage them
ignoreDifferences:
  - kind: Deployment
    group: apps
    jsonPointers:
      - /spec/template/spec/containers/0/resources/requests
      - /spec/template/spec/containers/0/resources/limits
      # Repeat for each container in multi-container pods:
      # - /spec/template/spec/containers/1/resources/requests
      # - /spec/template/spec/containers/1/resources/limits
```

The ApplicationSet will automatically apply this to the generated ArgoCD Application. Now you can use VPA in `Auto` or `Recreate` mode, and changes apply immediately without ArgoCD reverting them.

See [Allowing Controllers to Manage Fields](../../tenant/applications.md#allowing-controllers-to-manage-fields--ignoredifferences) in the applications documentation for more details.

**Pros:**

- ✅ Simple to implement (add `ignoreDifferences` block to your app definition)
- ✅ VPA changes apply immediately (no waiting for developer action)
- ✅ Useful for non-critical or experimental workloads

**Cons:**

- ❌ Git is no longer complete source of truth (resource requests drift)
- ❌ Loss of audit trail (who changed what when?)
- ❌ Harder to review changes before they're applied
- ❌ Risk: New deployments or rollbacks reset to git values, losing VPA tuning
- ❌ Requires periodic manual review to stay aware of what VPA changed

**When to use:** Non-critical workloads, dev/staging, or when you accept that resource requests are "VPA-managed" outside of git.

---

### Which Approach Should You Choose?

| Scenario                                | Approach                                         | Reasoning                                                     |
| --------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- |
| Production, multi-team, strict GitOps   | **Approach 1**                                   | Developer ownership, full audit trail, git is source of truth |
| Non-critical, experimental, dev/staging | **Approach 2**                                   | Simpler, automatic updates, acceptable drift                  |
| Mixed environment                       | **Approach 1 for prod, Approach 2 for non-prod** | Different policies per namespace/workload                     |

**Recommendation for this platform:** Start with **Approach 1**. It aligns with GitOps principles and keeps git accurate. Approach 2 is a fallback for teams that want VPA automation without manual intervention.

---

## Customising the VPA Helm Values

The platform ships default Helm values for VPA under `config/vpa/` in this repository. Tenants can override or extend these values from their workloads repository.

### Value file layout

| File                             | Scope                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------- |
| `config/vpa/all.yaml`            | Defaults applied to **every** cluster that consumes this path                   |
| `config/vpa/<cloud_vendor>.yaml` | Per-cloud defaults (e.g., `aws.yaml`, `azure.yaml`)                             |
| `config/vpa/<cluster_name>.yaml` | Overrides for a **single** cluster (matches the cluster's `cluster_name` field) |

### Resolution order (precedence)

Values are layered; **more specific files override the same keys** from less specific ones. From **highest** to **lowest** precedence:

1. **Cluster-specific (workloads repo)**: `config/vpa/<cluster_name>.yaml`
2. **Cloud-specific (workloads repo)**: `config/vpa/<cloud_vendor>.yaml`
3. **Global tenant (workloads repo)**: `config/vpa/all.yaml`
4. **Cloud-specific (platform repo)**: `config/vpa/<cloud_vendor>.yaml`
5. **Global platform defaults (platform repo)**: `config/vpa/all.yaml`

Missing files are ignored. Maps are deep-merged; lists are replaced.

### What the platform defaults set

The platform `config/vpa/all.yaml` ships with:

- 2 replicas of recommender, updater, and admission controller (HA by default)
- Pod disruption budgets to prevent simultaneous component evictions
- Hardened pod/container security contexts (non-root, read-only, no capabilities)
- Conservative resource bounds to prevent under-sizing
- Tight resource requests/limits on VPA components themselves

### Example — run VPA in "Off" mode cluster-wide

```yaml
# <tenant_path>/config/vpa/all.yaml
updater:
  enabled: true # Explicitly enable if you want recommendations stored (default: true)


# Note: Update mode is NOT a helm value — it's set per VerticalPodAutoscaler CRD
```

### Example — disable VPA updater (recommendations only, prevent automatic evictions)

```yaml
# <tenant_path>/config/vpa/all.yaml
updater:
  enabled: false # Disable the updater component — no pod evictions will occur
```

### Example — adjust minimum recommendation bounds

```yaml
# <tenant_path>/config/vpa/all.yaml
recommender:
  extraArgs:
    pod-recommendation-min-cpu-millicores: "50" # Prevent CPU recommendations below 50m
    pod-recommendation-min-memory-mb: "256" # Prevent memory recommendations below 256Mi
```

Refer to the [upstream `values.yaml`](https://github.com/FairwindsOps/charts/blob/master/stable/vpa/values.yaml) for all supported keys.

---

## Core CRD — VerticalPodAutoscaler

The `VerticalPodAutoscaler` CRD defines what to monitor and how to apply changes.

### Basic structure

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: <name>
  namespace: <namespace>
spec:
  # Target — what to monitor (Deployment, StatefulSet, DaemonSet, Job)
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-service

  # Update policy — how to apply recommendations
  updatePolicy:
    updateMode: "Off" # Off, Initial, Recreate, or Auto

  # Resource policy — bounds and per-container controls
  resourcePolicy:
    containerPolicies:
      - containerName: "*" # Match all containers
        minAllowed:
          cpu: 100m
          memory: 128Mi
        maxAllowed:
          cpu: 4
          memory: 4Gi
        controlledResources:
          - cpu
          - memory
        controlledValues: RequestsAndLimits
```

### Key fields

| Field                       | Meaning                                                                                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `targetRef`                 | The workload to monitor — must match a Deployment, StatefulSet, DaemonSet, or Job by name and namespace          |
| `updateMode`                | `Off` (recommendations only), `Initial` (on pod creation), `Recreate` (evict and restart), or `Auto` (immediate) |
| `minAllowed` / `maxAllowed` | CPU/memory bounds; recommendations are clipped to these ranges                                                   |
| `controlledResources`       | Which resources VPA controls — `cpu`, `memory`, or both (default: both)                                          |
| `controlledValues`          | `RequestsAndLimits` (adjusts both requests and limits), `RequestsOnly` (requests only)                           |

### Matching multiple containers

```yaml
resourcePolicy:
  containerPolicies:
    # Specific container
    - containerName: app
      minAllowed: { cpu: 100m, memory: 128Mi }
      maxAllowed: { cpu: 2, memory: 2Gi }

    # Sidecar — different bounds
    - containerName: sidecar
      minAllowed: { cpu: 10m, memory: 32Mi }
      maxAllowed: { cpu: 500m, memory: 512Mi }

    # Init containers and others (wildcard)
    - containerName: "*"
      minAllowed: { cpu: 50m, memory: 64Mi }
      maxAllowed: { cpu: 1, memory: 1Gi }
```

---

## Common Examples

### Example 1 — Off-the-shelf web service with static requests

**Goal:** Get recommendations without disrupting the running pod; apply manually during next deployment.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api-server-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-server

  # Recommendations only — no pod restarts
  updatePolicy:
    updateMode: "Off"

  resourcePolicy:
    containerPolicies:
      - containerName: api-server
        minAllowed:
          cpu: 100m
          memory: 256Mi
        maxAllowed:
          cpu: 4
          memory: 4Gi
        controlledResources:
          - cpu
          - memory
        controlledValues: RequestsAndLimits
```

**Applying recommendations:**

```bash
# 1. View recommendations
kubectl describe vpa api-server-vpa -n default

# Output:
# Recommendation:
#   Container Recommendations:
#     Container Name: api-server
#     Lower Bound:
#       cpu:    120m
#       memory: 256Mi
#     Target:                         ← Use these values
#       cpu:    250m
#       memory: 320Mi
#     Upper Bound:
#       cpu:    500m
#       memory: 1Gi

# 2. Update your Deployment manifest
kubectl set resources deployment api-server \
  -c api-server \
  --requests=cpu=250m,memory=320Mi \
  --limits=cpu=500m,memory=1Gi

# Or edit directly:
kubectl edit deployment api-server
# Update spec.template.spec.containers[0].resources
```

### Example 2 — Batch worker with Auto mode (dev/staging only)

**Goal:** Automatically right-size short-lived batch jobs in non-critical environments.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: batch-worker-vpa
  namespace: staging
spec:
  targetRef:
    apiVersion: batch/v1
    kind: Job
    name: batch-processor

  # Auto mode — safe for non-critical workloads
  updatePolicy:
    updateMode: "Auto"

  resourcePolicy:
    containerPolicies:
      - containerName: worker
        minAllowed:
          cpu: 100m
          memory: 256Mi
        maxAllowed:
          cpu: 2
          memory: 2Gi
```

**Why Auto here:** Batch jobs are short-lived, and staging environments have no availability SLA. Auto mode applies recommendations immediately as they stabilize.

### Example 3 — Stateful service with Initial mode

**Goal:** Right-size new pods automatically; existing pods keep their original requests until next rolling update.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: database-replica-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: postgresql-replicas

  # Apply only to newly created pods
  updatePolicy:
    updateMode: "Initial"

  resourcePolicy:
    containerPolicies:
      - containerName: postgresql
        minAllowed:
          cpu: 500m
          memory: 1Gi
        maxAllowed:
          cpu: 8
          memory: 16Gi
        # Only control requests; let DBA set limits
        controlledValues: RequestsOnly
```

**How it works:** When the StatefulSet next rolls out (e.g., during a Helm upgrade), new pods launch with VPA-recommended requests. Existing pods are unaffected until they're replaced through normal rolling updates.

### Example 4 — Multi-container pod with selective control

**Goal:** VPA only adjusts the main application; sidecars are excluded or have fixed bounds.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: app-with-sidecars-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp

  updatePolicy:
    updateMode: "Off"

  resourcePolicy:
    containerPolicies:
      # Main application container — let VPA recommend freely
      - containerName: app
        minAllowed:
          cpu: 100m
          memory: 256Mi
        maxAllowed:
          cpu: 4
          memory: 4Gi

      # Istio sidecar — fixed resource usage, exclude from VPA
      - containerName: istio-proxy
        controlledResources: [] # Empty = exclude from scaling

      # OpenTelemetry collector sidecar — tighter bounds
      - containerName: otel-collector
        minAllowed:
          cpu: 50m
          memory: 64Mi
        maxAllowed:
          cpu: 200m
          memory: 256Mi
```

### Example 5 — Exclude certain pods from VPA

**Goal:** Use VPA cluster-wide but exclude certain deployments (e.g., system services).

Instead of creating a VPA for every workload, VPA can also be configured with a policy to exclude certain pods by label:

```yaml
# In the cluster configuration, via Helm values:
# config/vpa/all.yaml

recommender:
  extraArgs:
    # Exclude pods with label vpa-exclude=true
    excluded-label-key: "vpa-exclude"
    excluded-label-value: "true"
```

Then mark pods to exclude:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: system-service
  namespace: kube-system
spec:
  template:
    metadata:
      labels:
        vpa-exclude: "true" # ← VPA will ignore this deployment
    spec:
      containers: ...
```

---

## Application Team Runbook — Using VPA in Your Workloads

This section is for **application teams** deploying workloads into the platform. It covers the step-by-step workflow for using VPA.

### Prerequisites

- Your cluster has VPA enabled (`enable_vpa: "true"` label in cluster definition)
- Your workloads are deployed via ArgoCD using manifests in a git repository
- Platform team has chosen **Approach 1** (Off mode + developer responsibility) or **Approach 2** (ignoreDifferences)

### Step 1: Deploy Your Workload via the Platform's Application System

On this platform, applications are deployed via helm charts using the ApplicationSet pattern. Create your application definition:

```yaml
# workloads/applications/my-service/dev.yaml
helm:
  # Reference to your Helm chart
  repository: https://charts.example.com
  version: 1.0.0
  release_name: my-service

  # Define baseline resource requests for the Helm chart to use
  values: |
    resources:
      requests:
        cpu: 100m          # Conservative baseline
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 1Gi

# Optional: If using Approach 2 (ignoreDifferences), let VPA manage requests
# ignoreDifferences:
#   - kind: Deployment
#     group: apps
#     jsonPointers:
#       - /spec/template/spec/containers/0/resources/requests
#       - /spec/template/spec/containers/0/resources/limits
```

Then create a `values/all.yaml` file with the same resource structure for re-usability:

```yaml
# workloads/applications/my-service/values/all.yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

Refer to the [Tenant Applications guide](../../tenant/applications.md) for details on the full deployment pattern, values resolution, and `ignoreDifferences` configuration.

**Important:** Always include baseline resource requests. VPA uses them as a starting point to recommend improvements.

### Step 2: Create a VerticalPodAutoscaler Resource

Add a VPA resource targeting your deployment:

```yaml
# manifests/my-service/vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-service-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-service

  # Use "Off" mode — recommendations only
  updatePolicy:
    updateMode: "Off"

  resourcePolicy:
    containerPolicies:
      - containerName: my-service
        minAllowed:
          cpu: 50m
          memory: 128Mi
        maxAllowed:
          cpu: 4
          memory: 4Gi
        controlledResources:
          - cpu
          - memory
        controlledValues: RequestsAndLimits
```

Commit and push — ArgoCD will deploy it.

### Step 3: Check Recommendations (After 2–5 Days)

VPA needs historical data to stabilize. After a few days of running:

```bash
kubectl describe vpa my-service-vpa -n production
```

Output:

```
Status:
  Recommendation:
    Container Recommendations:
      Container Name: my-service
      Lower Bound:
        Cpu:     80m
        Memory:  220Mi
      Target:                    ← Use this value
        Cpu:     150m
        Memory:  310Mi
      Upper Bound:
        Cpu:     500m
        Memory:  900Mi
```

**Check:**

- Does `Target` make sense? (typically 10–30% different from your requests)
- Have recommendations stabilized? (check `.status.lastUpdateTime`)
- Are they within your `minAllowed` / `maxAllowed` bounds?

### Step 4: Apply the Recommendation (Approach 1 — Off Mode)

**If your platform uses Approach 1 (Off mode + developer responsibility):**

1. **Update your values file** with the Target values from VPA:

   ```yaml
   # workloads/applications/my-service/values/all.yaml
   resources:
     requests:
       cpu: 150m # ← From VPA Target
       memory: 310Mi # ← From VPA Target
     limits:
       cpu: 1000m
       memory: 1Gi
   ```

2. **Alternatively, update inline values** in your cluster-specific config:

   ```yaml
   # workloads/applications/my-service/dev.yaml
   helm:
     repository: https://charts.example.com
     version: 1.0.0
     values: |
       resources:
         requests:
           cpu: 150m      # ← From VPA Target
           memory: 310Mi  # ← From VPA Target
   ```

3. **Commit and push to git:**

   ```bash
   git add workloads/applications/my-service/
   git commit -m "chore: update resource requests based on VPA recommendations"
   git push
   ```

4. **ArgoCD will automatically sync** and redeploy with new requests:
   ```bash
   kubectl rollout status deployment/my-service -n <namespace>
   ```

See [Helm Values Resolution](../../tenant/applications.md#helm-values-resolution) for the complete layering order (cluster-specific, environment-specific, tenant-specific, default).

### Step 4 (Alternative): Apply Automatically (Approach 2 — ignoreDifferences)

**If your platform uses Approach 2 (ignoreDifferences):**

1. **Add `ignoreDifferences` to your application definition:**

   ```yaml
   # workloads/applications/my-service/dev.yaml
   helm:
     repository: https://charts.example.com
     version: 1.0.0
     values: |
       resources:
         requests:
           cpu: 100m
           memory: 256Mi

   ignoreDifferences:
     - kind: Deployment
       group: apps
       jsonPointers:
         - /spec/template/spec/containers/0/resources/requests
         - /spec/template/spec/containers/0/resources/limits
   ```

2. **VPA automatically applies changes** in-cluster — no manual git updates needed
3. **Monitor actual usage** after VPA adjusts resources:
   ```bash
   kubectl top pods -n <namespace> -l app=my-service
   ```
4. **Be aware:** Resource requests in git may drift from cluster values. Periodically check recommendations to stay informed.

### Monitoring Actual Usage

After applying new requests, verify they're appropriate:

```bash
# Check current usage
kubectl top pods -n production -l app=my-service

# Column meanings:
# CPU: actual CPU being used
# MEMORY: actual memory being used
# Compare against your requests in the manifest
```

**Red flags:**

- Usage consistently at 95%+ of requests → bounds are too tight
- Usage consistently at 5% of requests → can be tightened further
- Pods getting OOMKilled → memory recommendation was wrong

### Excluding a Workload from VPA

If a workload should **not** be managed by VPA:

**Option 1: Don't create a VPA resource** — VPA only affects workloads with an explicit VerticalPodAutoscaler CRD.

**Option 2: Use exclusion label** (if configured by platform):

```yaml
spec:
  template:
    metadata:
      labels:
        vpa-exclude: "true"
```

### Troubleshooting — VPA Isn't Recommending

```bash
# 1. Check VPA exists
kubectl get vpa my-service-vpa -n production

# 2. Check pod metrics are available
kubectl top pods -n production -l app=my-service

# 3. Check when recommendations were last updated
kubectl get vpa my-service-vpa -n production -o jsonpath='{.status.lastUpdateTime}'

# 4. View any error conditions
kubectl describe vpa my-service-vpa -n production
```

**Common causes:**

- Workload is brand new (< 2 days old) — VPA needs historical data
- Metrics Server not running (`kubectl get deployment metrics-server -n kube-system`)
- Pod has no CPU/memory usage (`kubectl top pods` shows "unknown")

### FAQ

**Q: Will VPA restart my pods automatically?**
A: Only if you use `updateMode: Auto` or `Recreate`. With `Off` mode (recommended), VPA only recommends; you apply changes when ready.

**Q: Can I use VPA with KEDA?**
A: Yes! But see [VPA with KEDA](#vpa-with-keda--safe-integration-pattern) — use `Off` mode to avoid conflicts.

**Q: What if I disagree with a VPA recommendation?**
A: Adjust `minAllowed` and `maxAllowed` bounds to constrain recommendations:

```yaml
resourcePolicy:
  containerPolicies:
    - containerName: my-service
      minAllowed:
        cpu: 100m # ← Raise this to force higher recommendations
        memory: 256Mi
      maxAllowed:
        cpu: 2 # ← Lower this to cap recommendations
        memory: 2Gi
```

**Q: How often should I update requests based on VPA?**
A: With Approach 1 (Off mode), whenever a significant change appears (monthly or quarterly review is reasonable). Don't chase every small fluctuation.

---

## VPA with KEDA — Safe Integration Pattern

!!! warning "Potential conflict"

    VPA and KEDA are **complementary but can interfere** if misconfigured. VPA changes pod resource requests; KEDA changes the number of pods. Without care, you risk pod churn.

### The Risk — Why They Can Conflict

KEDA scales horizontally (0→1→N replicas) based on external event sources. VPA updates resource requests (and optionally restarts pods to apply changes). If VPA is in `Auto` or `Recreate` mode while KEDA is actively scaling, VPA evictions can disrupt KEDA's scaling calculations:

```
Timeline:
  T0: KEDA scales 1 → 5 replicas (queue depth rises)
  T1: VPA recommender computes new requests
  T2: VPA updater evicts a pod (Recreate mode)
  T3: Pod restarts with new requests
  T4: But KEDA's HPA is still scaling based on the original event metrics
      → potential overshooting, oscillation, or unnecessary replicas
```

### The Safe Pattern

For workloads using KEDA **always use VPA in `Off` mode** (recommendations only):

```yaml
# VPA for a KEDA-scaled workload
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-worker-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-worker

  updatePolicy:
    updateMode: "Off" # ← CRITICAL: Recommendations only

  resourcePolicy:
    containerPolicies:
      - containerName: my-worker
        minAllowed:
          cpu: 100m
          memory: 256Mi
        maxAllowed:
          cpu: 2
          memory: 2Gi
---
# Paired with KEDA ScaledObject
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-worker-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: my-worker
  minReplicaCount: 1
  maxReplicaCount: 30
  triggers:
    - type: rabbitmq
      metadata:
        queueName: work
        mode: QueueLength
        value: "10"
      authenticationRef:
        name: rabbitmq-auth
```

### How to apply VPA recommendations with KEDA

1. **Monitor VPA recommendations** — watch the VPA resource for new Target values:

   ```bash
   watch kubectl describe vpa my-worker-vpa -n default
   ```

2. **Apply during planned maintenance** — update the Deployment manifest _outside_ of active scaling periods (e.g., scheduled maintenance windows, after-hours, weekends):

   ```bash
   kubectl set resources deployment my-worker \
     -c my-worker \
     --requests=cpu=350m,memory=410Mi
   ```

   Or via GitOps:

   ```yaml
   spec:
     template:
       spec:
         containers:
           - name: my-worker
             resources:
               requests:
                 cpu: 350m # From VPA Target
                 memory: 410Mi
   ```

3. **Batch updates** — group VPA changes with other deployment updates (version bumps, config changes) to minimize rollouts.

### Why `Off` mode works

- **VPA recommender** still analyzes pod usage and stores recommendations (no change)
- **VPA updater** is not asked to evict pods (no disruption to KEDA's scaling)
- **Operator reads recommendations manually** at chosen times, decoupling VPA from KEDA's scaling cycles
- **KEDA scales uninterrupted** — no surprise pod restarts mid-scaling event

### Monitoring VPA recommendations in KEDA scenarios

Set up alerts for when new recommendations diverge significantly:

```bash
# Every hour, check if VPA recommendations changed
kubectl get vpa -n default -o json | \
  jq '.items[] | select(.status.recommendation != null) | "\(.metadata.name): \(.status.recommendation.containerRecommendations[0].target)"'
```

Or integrate VPA status into your Prometheus/Grafana for visibility.

---

## Reading & Applying Recommendations

### View recommendations

```bash
# Describe a specific VPA
kubectl describe vpa <name> -n <namespace>

# Example output:
# Status:
#   Recommendation:
#     Container Recommendations:
#       Container Name: app
#       Lower Bound:
#         Cpu:     120m
#         Memory:  256Mi
#       Target:                 ← What to apply
#         Cpu:     250m
#         Memory:  320Mi
#       Upper Bound:
#         Cpu:     500m
#         Memory:  1Gi
#       Uncapped Target:        ← If no bounds were set
#         Cpu:     290m
#         Memory:  350Mi
```

### Export recommendations to a file

```bash
# Get all VPA recommendations in JSON
kubectl get vpa -A -o json > vpa-recommendations.json

# Filter to specific VPA
kubectl get vpa <name> -n <namespace> -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' | jq .
```

### Apply recommendations manually

**Option 1: kubectl set resources**

```bash
kubectl set resources deployment my-service \
  -c my-service \
  --requests=cpu=250m,memory=320Mi \
  --limits=cpu=500m,memory=1Gi
```

**Option 2: kubectl edit**

```bash
kubectl edit deployment my-service

# Update the resources section:
# spec.template.spec.containers[0].resources:
#   requests:
#     cpu: 250m
#     memory: 320Mi
```

**Option 3: GitOps pipeline**

Update your deployment manifest in Git:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  template:
    spec:
      containers:
        - name: my-service
          resources:
            requests:
              cpu: 250m # From VPA Target
              memory: 320Mi
            limits:
              cpu: 500m
              memory: 1Gi
```

Commit and let your GitOps tool apply it.

### Validation before applying

Before applying recommendations, sanity-check them:

1. **Did usage stabilize?** — VPA needs historical data to be accurate. Check the VPA's recommendation age in `.status.lastUpdateTime`. New workloads need 2-5 days of traffic.

2. **Are bounds reasonable?** — Compare the recommendation against your `minAllowed` / `maxAllowed` constraints. If a recommendation hits the ceiling, your bounds may be too tight.

3. **Did the recommendation change recently?** — If the Target oscillates wildly, the workload is probably still stabilizing. Wait a few more days.

4. **Is this a special day?** — If you're applying recommendations made during a traffic dip (holiday, weekend), they may under-provision for normal load. Adjust the `maxAllowed` or delay application.

---

## Operational Commands & Debugging

### Status checks

```bash
# VPA components
kubectl get pods -n kube-system | grep vpa

# All VerticalPodAutoscalers in the cluster
kubectl get vpa -A

# Detailed status of a specific VPA
kubectl describe vpa <name> -n <namespace>

# Check if a workload has a VPA targeting it
kubectl get vpa -A | grep <deployment-name>
```

### Logs

```bash
# VPA Recommender — recommendation computation, history analysis
kubectl logs -n kube-system -l app=vpa-recommender -f

# VPA Updater — eviction and pod updates (if Auto/Recreate mode)
kubectl logs -n kube-system -l app=vpa-updater -f

# Admission Controller — resource validation, conflicts
kubectl logs -n kube-system -l app=vpa-admission-controller -f
```

### Metrics inspection

VPA does not expose Prometheus metrics by default. For cost visibility and historical tracking, use **kubecost** (already deployed on the platform).

```bash
# Via kubecost dashboard — navigate to Allocations → Filter by namespace
# See cost per pod, including the "ghost" cost of over-provisioned requests
```

### Debug — why is a VPA not recommending?

```bash
# 1. Check VPA exists and targets the right workload
kubectl describe vpa <name> -n <namespace>
# Verify: targetRef.name matches your Deployment/StatefulSet

# 2. Check Metrics Server is running
kubectl get deployment metrics-server -n kube-system

# 3. Check if pod has metrics
kubectl top pods -n <namespace>
# If empty, pods are brand new (no history yet) or Metrics Server is unhealthy

# 4. Check VPA recommender logs for errors
kubectl logs -n kube-system -l app=vpa-recommender | grep -i error

# 5. How long has the workload been running?
kubectl get vpa <name> -n <namespace> -o jsonpath='{.status.lastUpdateTime}'
# VPA needs 2–5 days of historical data before stabilizing recommendations
```

### Debug — why is a recommendation not applying?

```bash
# If updateMode: "Auto" or "Recreate", check updater logs
kubectl logs -n kube-system -l app=vpa-updater | tail -20

# Check if pod disruption budgets are blocking eviction
kubectl get pdb -A
kubectl describe pdb <name> -n <namespace>

# Check if the pod is actually being evicted
kubectl get events -n <namespace> | grep -i evict
```

---

## Known Constraints & Gotchas

| Constraint                                                       | Detail                                                                                                                                                                         |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **VPA needs historical data**                                    | Recommendations improve over time; new workloads need 2–5 days of real traffic before recommendations stabilize. Early recommendations may be inaccurate.                      |
| **Don't use `Auto` mode with KEDA**                              | VPA `Auto` can evict pods during KEDA scaling events, causing oscillation. Use `Off` (recommendations only) instead.                                                           |
| **VPA and HPA cannot control CPU/memory on the same deployment** | If VPA is managing CPU/memory requests, do NOT use an HPA CPU/memory trigger on the same workload — they will conflict and fight over replica count.                           |
| **Metrics Server is required**                                   | VPA reads metrics from kubelet via the standard Kubernetes Metrics Server (`metrics.k8s.io`). If Metrics Server is unhealthy, VPA won't get data.                              |
| **VPA needs PodDisruptionBudget for safe eviction**              | In `Auto`/`Recreate` modes, ensure workloads have a PDB; otherwise VPA may evict all replicas simultaneously.                                                                  |
| **Recommendations reset on cluster upgrades**                    | VPA checkpoint history may be lost on cluster reboots or admission controller restarts. Recommendations will stabilize again over time.                                        |
| **Resource requests vs. limits**                                 | By default, VPA controls both requests and limits (via `controlledValues: RequestsAndLimits`). If you want VPA to change requests only, set `controlledValues: RequestsOnly`.  |
| **Initial mode doesn't help long-lived pods**                    | If a Deployment's pods live for months without rolling out, `Initial` mode never gets a chance to apply recommendations. Schedule periodic rollouts or use `Off` mode instead. |
| **Wildcard container policies are last resort**                  | Matching `containerName: "*"` applies to all containers, overriding per-container policies. Use sparingly.                                                                     |

---

## Reference Links

- [Official VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Fairwinds VPA Helm Chart](https://github.com/FairwindsOps/charts/tree/master/stable/vpa)
- [VPA API Reference](https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/pkg/apis/autoscaling.k8s.io/v1/doc.go)
- [Integration with Kubecost — Cost Allocation](https://docs.kubecost.com/)

---

_Based on VPA 4.11 (Fairwinds chart) — see the upstream [VPA repository](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) for the authoritative reference._
