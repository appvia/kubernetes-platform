# Kustomize Addons

This directory contains the kustomize manifests for the open source and cloud specific add-ons.

## Directory Structure

Kustomize addon definitions are organized by category:

- `oss/` — Cloud-agnostic open source addons (e.g., kyverno, cert-manager, metrics-server)
- `aws/` — AWS-specific addons and integrations (e.g., EBS CSI, external-secrets with AWS Secrets Manager)

Each addon is a subdirectory containing a `kustomize.yaml` file that defines the addon metadata and deployment configuration.

## Kustomize Addon Schema

A kustomize addon is defined using a `kustomize.yaml` file in the addon's directory. The schema is as follows:

```yaml
---
kustomize:
  ## Human friendly description (optional)
  description: "Brief description of what this addon does"

  ## The feature name used for enablement (required)
  ## Clusters enable the addon by setting label `enable_<feature>: "true"`
  ## Example: feature: kyverno  -> label: enable_kyverno: "true"
  feature: kyverno

  ## The path to the kustomize overlay (required)
  ## This is relative to the addon directory
  path: base

  ## Location of an external kustomize repository (optional)
  ## If specified, kustomize overlays are fetched from this URL
  repository: https://github.com/example/kustomize-repo.git

  ## The revision/branch/tag of the external repository (optional)
  ## Only used if 'repository' is specified
  revision: main

  ## Optional patches to apply to the kustomize overlay (optional).
  ## Patch operations can reference cluster definition values via `key`.
  patches:
    - target:
        kind: ClusterPolicy
        name: deny-default-namespace
      patch:
        - op: replace
          path: /spec/validationFailureAction
          ## Reference a value from the cluster definition
          key: metadata.annotations.validation_mode
          ## Default value if the key is not found
          default: "audit"
          ## Optional prefix to prepend to the resolved value
          prefix: "mode-"

  ## Common labels to apply to all resources (optional)
  commonLabels:
    addon: kyverno

  ## Common annotations to apply to all resources (optional)
  commonAnnotations:
    app.kubernetes.io/managed-by: platform

## Namespace configuration (required)
namespace:
  ## The name of the namespace where this addon will be deployed (required)
  name: kyverno-system

  ## Pod Security Standards level for this namespace (optional)
  ## Valid values: restricted, baseline, privileged
  pod_security: restricted

## Synchronization options (optional)
sync:
  ## Deployment phase - controls ArgoCD RollingSync order (optional)
  ## Valid values: primary (default), secondary
  ## Use 'secondary' for addons that depend on others being deployed first
  phase: secondary
  ## Allows the user to control the sync wave of the resulting application
  wave: NUMBER
```

## Field Reference

### `kustomize` Section

| Field               | Type   | Required | Description                                                         |
| ------------------- | ------ | -------- | ------------------------------------------------------------------- |
| `description`       | string | No       | Human-friendly description of the addon                             |
| `feature`           | string | Yes      | Feature name; enabled by label `enable_<feature>: "true"`           |
| `path`              | string | Yes      | Path to the kustomize overlay relative to the addon directory       |
| `repository`        | string | No       | Git URL of external kustomize repository                            |
| `revision`          | string | No       | Git branch, tag, or commit SHA for external repository              |
| `patches`           | array  | No       | Kustomize patches to apply                                          |
| `commonLabels`      | object | No       | Labels to apply to all resources                                    |
| `commonAnnotations` | object | No       | Annotations to apply to all resources                               |

### `patches` Item Reference

| Field           | Type   | Required | Description                                                                     |
| --------------- | ------ | -------- | ------------------------------------------------------------------------------- |
| `target.kind`   | string | Yes      | Kubernetes resource kind to patch (e.g., Deployment, ClusterPolicy)             |
| `target.name`   | string | No       | Name of the specific resource to patch                                          |
| `patch.op`      | string | Yes      | JSON Patch operation: `add`, `replace`, `remove`                                |
| `patch.path`    | string | Yes      | JSON Pointer path to the field (e.g., `/spec/validationFailureAction`)          |
| `patch.key`     | string | No       | Cluster definition path to lookup a value (e.g., `metadata.annotations.region`) |
| `patch.default` | string | No       | Default value if the key is not found or empty                                  |
| `patch.prefix`  | string | No       | String prefix to prepend to the resolved value                                  |

### `namespace` Section

| Field          | Type   | Required | Description                                                             |
| -------------- | ------ | -------- | ----------------------------------------------------------------------- |
| `name`         | string | Yes      | Kubernetes namespace where the addon deploys                            |
| `pod_security` | string | No       | Pod Security Standards label: `restricted`, `baseline`, or `privileged` |

### `sync` Section

| Field   | Type   | Required | Description                                          |
| ------- | ------ | -------- | ---------------------------------------------------- |
| `phase` | string | No       | Deployment order: `primary` (default) or `secondary` |
| `wave`  | number | No       | Controls the sync wave of the resulting application  |

## Example: Kyverno Addon

```yaml
---
kustomize:
  description: "Policy engine for Kubernetes"
  feature: kyverno
  path: base
  patches:
    - target:
        kind: ClusterPolicy
        name: deny-latest-image
      patch:
        - op: replace
          path: /spec/validationFailureAction
          key: metadata.annotations.validation_mode
          default: "audit"

namespace:
  name: kyverno-system
  pod_security: restricted

sync:
  phase: secondary
```

## Patching with Cluster Definition Values

You can reference values from the cluster definition YAML in patches using the `key` field:

```yaml
patches:
  - target:
      kind: ConfigMap
      name: app-config
    patch:
      - op: replace
        path: /data/region
        key: metadata.annotations.region
        default: "us-east-1"
```

This will resolve the value from the cluster definition at `metadata.annotations.region`, or use `"us-east-1"` if not found.

Multi-level paths are supported:

```yaml
key: metadata.labels.environment # Looks up .metadata.labels.environment
```

## Deployment Order (Phases)

Addons can specify a deployment phase to control ordering:

- **`primary`** (default): Deploy in the first wave. Use for foundational components (network policies, RBAC, CSI drivers)
- **`secondary`**: Deploy after primary addons. Use for components that depend on others (e.g., Kyverno depends on cert-manager)

## Finding and Enabling Addons

Addons are automatically discovered and enabled by the platform:

1. Find the addon's feature name (e.g., `kyverno`)
2. Add `enable_<feature>: "true"` to your cluster definition's labels:

```yaml
labels:
  enable_kyverno: "true"
  enable_cert_manager: "true"
```

3. The `system-kustomize` ApplicationSet will automatically deploy matching addons

## Creating a New Kustomize Addon

1. Create a new directory under `addons/kustomize/oss/` or `addons/kustomize/aws/`
2. Add your Kubernetes manifests to a `base/` subdirectory
3. Create a `kustomize.yaml` file defining the addon metadata
4. Reference your cluster definition values in patches if needed
5. Test by adding the feature label to a cluster definition and deploying

See `kustomize.yaml.sample` for a full template.
