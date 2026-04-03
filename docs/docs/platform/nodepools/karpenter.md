# Karpenter node pools

## Overview

The platform can install optional **Karpenter `NodePool`** resources for AWS (EKS) clusters via the in-repo Helm chart `charts/karpenter-nodepools`. Pools reference an EKS **NodeClass** (`nodeClassRef` on `eks.amazonaws.com`, typically named `default`) and express instance constraints through **`spec.template.spec.requirements`**.

Enable the addon on a cluster with the feature label:

```yaml
metadata:
  labels:
    enable_karpenter_nodepools: "true"
```

Argo CD deploys the chart as a system Helm application (for example `system-karpenter-nodepools-<cluster_name>`). You need the Karpenter controller and a suitable NodeClass in the cluster; this chart only manages **`NodePool`** CRs.

---

## Platform defaults

Configuration is supplied through Helm values under the top-level key **`nodePools`**: a **map** keyed by the Kubernetes `NodePool` name (for example `amd64`, `arm64`). Each entry has optional **`metadata`** (`labels`, `annotations`) and a **`spec`** that mirrors the Karpenter `NodePool` API (`template`, `weight`, `disruption`, and so on).

In this repository, defaults and comments live under:

- **`config/karpenter_nodepools/all.yaml`** — optional global platform file (merged first when present; missing files are skipped).
- **`config/karpenter_nodepools/aws.yaml`** — AWS (`cloud_vendor: aws`) defaults and field documentation. As shipped, it defines two pools:
  - **`amd64`** — `c` / `m` / `r` families, selected CPU sizes and generations, **spot and on-demand**, **`kubernetes.io/arch: amd64`**, weight `100`.
  - **`arm64`** — same instance constraints for Graviton, **spot and on-demand**, **`kubernetes.io/arch: arm64`**, weight `50`.

Both pools point at **`nodeClassRef.name: default`**. Tune weights, disruption, or requirements to match your environments.

---

## How value files are merged

The **system Helm** ApplicationSet passes a fixed list of value files (later files override earlier ones). For this feature, `feature` is `karpenter_nodepools`, so paths resolve to `config/karpenter_nodepools/…` in each repository:

1. Platform repo: `config/karpenter_nodepools/all.yaml`
2. Platform repo: `config/karpenter_nodepools/<cloud_vendor>.yaml` (for AWS, `aws.yaml`)
3. Tenant repo: `<tenant_path>/config/karpenter_nodepools/all.yaml`
4. Tenant repo: `<tenant_path>/config/karpenter_nodepools/<cloud_vendor>.yaml`
5. Tenant repo: `<tenant_path>/config/karpenter_nodepools/<cluster_name>.yaml`

Missing files are ignored (`ignoreMissingValueFiles: true`).

**Maps** (such as `nodePools` and per-pool objects) are merged deeply by Helm: you can override a single field for one pool without repeating unrelated keys.

**Lists** (such as `spec.template.spec.requirements`) are **replaced** when a later file sets them. If you override `requirements`, repeat the **full** list you want in that value file, not only the delta.

---

## Downstream (tenant) overrides

Consumer repositories should place overrides next to their cluster definitions, under the same **`tenant_path`** as in the cluster definition (for example `config/karpenter_nodepools/dev.yaml` for a cluster named `dev`).

You can mirror the platform layout:

- Broad defaults: `config/karpenter_nodepools/all.yaml`
- Region or cloud-specific: `config/karpenter_nodepools/aws.yaml`
- One cluster: `config/karpenter_nodepools/<cluster_name>.yaml`

Editing **`config/karpenter_nodepools/aws.yaml` in the tenant repo** follows the same rules as the platform file of that name: it layers on top of platform `all.yaml` / `aws.yaml` and tenant `all.yaml`, and is merged before per-cluster files.

---

## Example: spot-only pools

To use **only Spot** capacity for a cluster, narrow the `karpenter.sh/capacity-type` requirement. Because `requirements` is a list, include every constraint you need in that override file.

```yaml
# <tenant_path>/config/karpenter_nodepools/dev.yaml
nodePools:
  amd64:
    spec:
      template:
        spec:
          requirements:
            - key: eks.amazonaws.com/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: eks.amazonaws.com/instance-cpu
              operator: In
              values: ["4", "8", "16", "32"]
            - key: eks.amazonaws.com/instance-generation
              operator: Gt
              values: ["4"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
  arm64:
    spec:
      template:
        spec:
          requirements:
            - key: eks.amazonaws.com/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: eks.amazonaws.com/instance-cpu
              operator: In
              values: ["4", "8", "16", "32"]
            - key: eks.amazonaws.com/instance-generation
              operator: Gt
              values: ["4"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: kubernetes.io/arch
              operator: In
              values: ["arm64"]
```

Pools you omit from `nodePools` in that file keep their merged definition from earlier value files.

---

## Example: adding an `arm64` pool

If your effective defaults only defined `amd64` (for example after a fork), add an **`arm64`** key. New map keys **add** a new `NodePool`; you do not need to repeat `amd64` unless you also change it.

```yaml
# <tenant_path>/config/karpenter_nodepools/all.yaml
nodePools:
  arm64:
    metadata:
      labels:
        karpenter.sh/nodepool: graviton
        karpenter.sh/nodepool-class: default
      annotations:
        karpenter.sh/nodepool-version: "1.2.1"
        karpenter.sh/nodepool-provider: aws
    spec:
      template:
        spec:
          nodeClassRef:
            group: eks.amazonaws.com
            kind: NodeClass
            name: default
          requirements:
            - key: eks.amazonaws.com/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: eks.amazonaws.com/instance-cpu
              operator: In
              values: ["4", "8", "16", "32"]
            - key: eks.amazonaws.com/instance-generation
              operator: Gt
              values: ["4"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["arm64"]
      weight: 50
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
```

Combining **Graviton** with **Spot-only** is a matter of using `kubernetes.io/arch: arm64` and `values: ["spot"]` on `karpenter.sh/capacity-type` in the same full `requirements` list (as in the previous example) for that pool.

---

## Related paths in this repository

| Path | Role |
| --- | --- |
| `charts/karpenter-nodepools/` | Helm chart templates |
| `config/karpenter_nodepools/` | Platform value defaults |
| `addons/helm/cloud/aws.yaml` | Standalone-style Helm discovery (includes `karpenter_nodepools`) |
| `addons/helm/aws/helm.yaml` | Hub-style Helm discovery for the same feature |
