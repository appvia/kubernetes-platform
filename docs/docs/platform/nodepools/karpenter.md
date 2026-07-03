# Karpenter node pools

## Overview

The platform can install optional **Karpenter `NodePool`** and **EKS `NodeClass`** resources for AWS (EKS) clusters via the in-repo Helm chart `charts/karpenter-nodepools`. Pools reference an EKS **NodeClass** (`nodeClassRef` on `eks.amazonaws.com`, typically named `default`) and express instance constraints through **`spec.template.spec.requirements`**. Node classes define infrastructure settings such as subnets, security groups, IAM role, and EC2 tags.

Enable the addon on a cluster with the feature label:

```yaml
metadata:
  labels:
    enable_karpenter_nodepools: "true"
```

Argo CD deploys the chart as a system Helm application (for example `system-karpenter-nodepools-<cluster_name>`). You need the Karpenter controller (or EKS Auto Mode) running in the cluster; the chart manages **`NodePool`** and optional **`NodeClass`** CRs delivered through Helm values.

---

## Platform defaults

Configuration is supplied through two top-level Helm value maps:

- **`nodePools`** — keyed by the Kubernetes `NodePool` name (for example `amd64`, `arm64`). Each entry has optional **`metadata`** (`labels`, `annotations`) and a **`spec`** that mirrors the Karpenter `NodePool` API (`template`, `weight`, `disruption`, and so on).
- **`nodeClasses`** — keyed by the Kubernetes `NodeClass` name. Each entry has optional **`metadata`** and a **`spec`** that mirrors the EKS Auto Mode `NodeClass` API (`role`, `subnetSelectorTerms`, `securityGroupSelectorTerms`, `tags`, and so on).

In this repository, defaults and comments live under:

- **`config/karpenter_nodepools/all.yaml`** — optional global platform file (merged first when present; missing files are skipped).
- **`config/karpenter_nodepools/aws.yaml`** — AWS (`cloud_vendor: aws`) defaults and field documentation. As shipped, it defines two pools:
  - **`amd64`** — `c` / `m` / `r` families, selected CPU sizes and generations, **spot and on-demand**, **`kubernetes.io/arch: amd64`**, weight `100`.
  - **`arm64`** — same instance constraints for Graviton, **spot and on-demand**, **`kubernetes.io/arch: arm64`**, weight `50`.

Both pools point at **`nodeClassRef.name: default`**, the NodeClass that EKS Auto Mode creates when built-in node pools are enabled. The platform does **not** ship a custom `NodeClass`; leave the built-in **`default`** class untouched and define your own class in the workload repository when you need custom EC2 tags or other infrastructure settings (see [Custom EC2 tags on provisioned nodes](#custom-ec2-tags-on-provisioned-nodes)).

---

## How value files are merged

The **system Helm** ApplicationSet passes a fixed list of value files (later files override earlier ones). For this feature, `feature` is `karpenter_nodepools`, so paths resolve to `config/karpenter_nodepools/…` in each repository:

1. Platform repo: `config/karpenter_nodepools/all.yaml`
2. Platform repo: `config/karpenter_nodepools/<cloud_vendor>.yaml` (for AWS, `aws.yaml`)
3. Tenant repo: `<tenant_path>/config/karpenter_nodepools/all.yaml`
4. Tenant repo: `<tenant_path>/config/karpenter_nodepools/<cloud_vendor>.yaml`
5. Tenant repo: `<tenant_path>/config/karpenter_nodepools/<cluster_name>.yaml`

Missing files are ignored (`ignoreMissingValueFiles: true`).

**Maps** (such as `nodePools`, `nodeClasses`, and per-pool or per-class objects) are merged deeply by Helm: you can override a single field for one pool or class without repeating unrelated keys.

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

## Custom EC2 tags on provisioned nodes

EKS Auto Mode applies a fixed set of tags to EC2 instances launched through the built-in **`default`** NodeClass. To add your own tags—for cost allocation, ownership, environment labelling, and so on—define a **separate NodeClass** in your workload repository and point your NodePools at it.

**Do not modify or replace the built-in `default` NodeClass.** EKS Auto Mode manages that resource when built-in node pools are enabled. AWS also recommends against naming a custom class `default`. Instead:

1. Add a **`nodeClasses`** entry under `config/karpenter_nodepools/` in your workload repository (for example `all.yaml`, `aws.yaml`, or `<cluster_name>.yaml`).
2. Set **`spec.tags`** on that class with the EC2 tags you want on every instance the class launches.
3. Copy the networking and IAM settings from the built-in class (`role`, `subnetSelectorTerms`, `securityGroupSelectorTerms`) so nodes join the cluster correctly.
4. Update each **`nodePools`** entry to reference your class via **`spec.template.spec.nodeClassRef.name`**.

The chart renders both maps: `nodeClasses` become `eks.amazonaws.com/v1` `NodeClass` objects; `nodePools` become `karpenter.sh/v1` `NodePool` objects.

### Example configuration

A complete example is published at [platform/nodepools/karpenter/all.yaml](https://appvia.github.io/kubernetes-platform/platform/nodepools/karpenter/all.yaml). The shape is:

```yaml
# <tenant_path>/config/karpenter_nodepools/all.yaml
nodeClasses:
  platform:
    spec:
      role: KarpenterNodeRole # copy from: kubectl get nodeclass default -o jsonpath='{.spec.role}'
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: "<cluster_name>"
            kubernetes.io/role/internal-elb: "1"
      securityGroupSelectorTerms:
        - tags:
            aws:eks:cluster-name: "<cluster_name>"
      tags:
        Environment: production
        CostCenter: "123456"
        ManagedBy: karpenter

nodePools:
  amd64:
    spec:
      template:
        spec:
          nodeClassRef:
            group: eks.amazonaws.com
            kind: NodeClass
            name: platform
  arm64:
    spec:
      template:
        spec:
          nodeClassRef:
            group: eks.amazonaws.com
            kind: NodeClass
            name: platform
```

Replace `<cluster_name>` with the cluster name from your cluster definition. Adjust subnet and security-group selector tags to match how your VPC and EKS cluster were provisioned.

Because Helm deep-merges maps, you only need to set `nodeClassRef` (and any other fields you are changing) for each pool. Requirements, weights, and disruption settings from platform defaults are preserved unless you override them in the same file.

### Restricted tag keys

EKS Auto Mode rejects certain tag keys on `NodeClass.spec.tags`, including Karpenter-managed keys such as `karpenter.sh/nodepool`, `karpenter.sh/nodeclaim`, and `eks.amazonaws.com/nodeclass`, as well as `kubernetes.io/cluster/*` prefixes. Use your own keys for cost and ownership metadata.

### IAM permissions

Applying user-defined EC2 tags requires extra permissions on the **cluster IAM role**. Attach a policy that allows `ec2:CreateTags`, `ec2:DeleteTags`, and `ec2:DescribeTags` on the instances your node class launches. See [Custom AWS tags for EKS Auto resources](https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html#auto-cluster-iam-role-tags) in the Amazon EKS User Guide.

### Access entries

If your custom NodeClass uses a **different IAM role** than the built-in `default` class, create an EKS **access entry** for that role with the `AmazonEKSAutoNodePolicy` access policy so nodes can join the cluster. When you reuse the same role as `default` (as in the example above), the access entry EKS created at cluster bootstrap already covers your custom class.

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

| Path                                                | Role                                                             |
| --------------------------------------------------- | ---------------------------------------------------------------- |
| `charts/karpenter-nodepools/`                       | Helm chart templates (`NodePool` and `NodeClass`)                |
| `config/karpenter_nodepools/`                       | Platform value defaults                                          |
| `docs/static/platform/nodepools/karpenter/all.yaml` | Published example for custom EC2 tags                            |
| `addons/helm/cloud/aws.yaml`                        | Standalone-style Helm discovery (includes `karpenter_nodepools`) |
| `addons/helm/aws/helm.yaml`                         | Hub-style Helm discovery for the same feature                    |
