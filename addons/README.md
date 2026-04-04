# Deployment Formats

The following describes the different formats that can be used to deploy the platform.

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

## Helm

You can deploy using a helm chart, by adding a `helm.yaml`.

1. Create a folder (by default this becomes the namespace)
2. Add a `helm.yaml` file

## Helm Entry Format

The helm entry format is as follows:

```yaml
helm:
  # (Required) A feature flag to enable/disable the deployment. The cluster
  # labels are used to determine if the cluster should have the application
  # deployed to it.
  feature: enable_application
  ## (Optional) The chart to use for the deployment.
  chart: ./charts/platform
  ## (Optional) The path inside a repository to the chart to use for the deployment.
  path: ./charts/platform
  ## (Required) The release name to use for the deployment.
  release_name: platform
  ## (Required) The version of the chart to use for the deployment.
  version: 0.1.0
  ## (Optional) An override for the namespace to use for the deployment.
  namespace: override-namespace
  ## (Optional) A collection of parameters
  parameters:
    # Here the value is hard-coded to 'MY_VALUE'
    - name: global.settings
      value: MY_VALUE
    # Here the value is dynamically resolved from cluster definition annotations (NOTE the prefix '/'.')
    - name: global.settings.hostname
      value: .metadata.labels.cluster_name
      default: mydefault_value
  values: |
    my_value: hello
  ## (Optional) Ignore difference on resources
  ignoreDifferences:
    - group: ""
      name: "test"
      kind: "Secret"
      jsonPointers:
        - /spec/replicas
      managedFieldManagers:
        - test

## Sync Options
sync:
  # (Optional) The phase to use for the deployment, used to determine the order of the deployment.
  phase: primary|secondary
  # (Optional) The duration to use for the deployment.
  duration: 30s
  # (Optional) The max duration to use for the deployment.
  max_duration: 5m
```

### Ignoring diff drift (optional)

Optional `ignoreDifferences` at the **root** of the definition (next to `helm` / `sync`) is copied onto the generated Argo CD Application `spec.ignoreDifferences`. Syntax matches [Argo CD diffing customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/) (`group`, `kind`, `name`, `namespace`, `jsonPointers`, `jqPathExpressions`, `managedFieldsManagers`). Omit `group` or set it to `""` for core API resources.

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/replicas
```

The following fields are supported:

- `feature`: The feature name used for enabling. Clusters enable the add-on by setting label `enable_<feature>: "true"`.
- `chart`: Chart name when `repository` is a Helm repo (e.g., `argo-workflows`).
- `repository`: Helm repository URL (e.g., `https://...`) or OCI registry host (e.g., `public.ecr.aws`).
- `path`: Path inside a Git repository when sourcing charts from Git (mutually exclusive with `chart`).
- `version`: Chart version (Helm/OCI) or Git revision (e.g., `main`, `HEAD`, `v0.1.0`).
- `namespace`: Namespace to install the chart into.
- `parameters`: A list of Helm parameters for the resulting Argo CD Application.
  - `name`: Path inside the Helm values to set (e.g., `aws.region`).
  - `value`: Literal value, or a reference into cluster metadata using dot notation (e.g., `.metadata.annotations.region`).
  - `default`: Value to use if the referenced metadata is empty or missing.
- `values`: A multi-line string of Helm values to add to the Application.
- `sync`: Sync options for the resulting Argo CD Application.
  - `wave`: Optional wave number to set for the Application. Applications with lower wave numbers are deployed first.
- `ignoreDifferences`: Optional list of Argo CD diff ignore rules for the generated Application (see [diffing customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)).

At minimum, each entry must include `feature`, `repository`, `namespace`, `version`, and one of `chart` or `path`.

## Helm Values

The platform also supports the use of helm values located within the `config` directory. Within this directory each folder maps to an add-on. Both [system-helm]() and [tenant-helm]() support multiple layers of merging i.e. they are consume values from the platform, AS WELL as override from the tenant repository. Note the order, those at the bottom of the list have the highest precedence i.e. `CLUSTER_NAME.yaml` in the tenant repository has the ability to overload values from the platform itself.

```yaml
- "$values/config/{{ .feature }}/all.yaml"
- "$values/config/{{ .feature }}/{{ .metadata.labels.cloud_vendor }}.yaml"
- "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/all.yaml"
- "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/{{ .metadata.labels.cloud_vendor }}.yaml"
- "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/{{ .metadata.labels.cluster_name }}.yaml"
```

From the above, and assuming the `feature` was karpenter, and the cluster was name `dev`, the following paths will be merged into the helm values.

```
- "$values/config/karpenter/all.yaml"
- "$values/config/karpenter/aws.yaml"
- "$tenant/config/karpenter/all.yaml"
- "$tenant/config/karpenter/aws.yaml"
- "$tenant/config/karpenter/dev.yaml"
```

- `$values` are folders located within the platform repository.
- `$tenant` are folders located within the tenant repository.

## Helm with Multiple Charts

Similar to the helm deployment, create a folder for your deployments. Taking the example of two charts, frontend and backend, you would create a folder called `frontend` and `backend`.

1. Create a folder called for the application, e.g. `myapp`
2. Create two folders inside the `myapp` folder, `frontend` and `backend`
3. Add a `helm.yaml` file to the `frontend` folder.
4. You can use the same format as above for the `helm.yaml` file.
5. Add a `values` folder to the `frontend` folder, and add a `all.yaml` file to the values folder.
6. Add a `values` folder to the `backend` folder, and add a `all.yaml` file to the values folder.

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
          key: .metadata.annotations.validation_mode
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

  ## (Optional) Ignore difference on resources
  ignoreDifferences:
    - group: ""
      name: "test"
      kind: "Secret"
      jsonPointers:
        - /spec/replicas
      managedFieldManagers:
        - test

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

## Optional: ignore live vs desired diffs (root level, next to kustomize / namespace / sync)
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/replicas
```

See [Argo CD diffing customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/) for `jsonPointers`, `jqPathExpressions`, and `managedFieldsManagers`.

## Field Reference

### `kustomize` Section

| Field               | Type   | Required | Description                                                   |
| ------------------- | ------ | -------- | ------------------------------------------------------------- |
| `description`       | string | No       | Human-friendly description of the addon                       |
| `feature`           | string | Yes      | Feature name; enabled by label `enable_<feature>: "true"`     |
| `path`              | string | Yes      | Path to the kustomize overlay relative to the addon directory |
| `repository`        | string | No       | Git URL of external kustomize repository                      |
| `revision`          | string | No       | Git branch, tag, or commit SHA for external repository        |
| `patches`           | array  | No       | Kustomize patches to apply                                    |
| `commonLabels`      | object | No       | Labels to apply to all resources                              |
| `commonAnnotations` | object | No       | Annotations to apply to all resources                         |

### `patches` Item Reference

| Field           | Type   | Required | Description                                                                      |
| --------------- | ------ | -------- | -------------------------------------------------------------------------------- |
| `target.kind`   | string | Yes      | Kubernetes resource kind to patch (e.g., Deployment, ClusterPolicy)              |
| `target.name`   | string | No       | Name of the specific resource to patch                                           |
| `patch.op`      | string | Yes      | JSON Patch operation: `add`, `replace`, `remove`                                 |
| `patch.path`    | string | Yes      | JSON Pointer path to the field (e.g., `/spec/validationFailureAction`)           |
| `patch.key`     | string | No       | Cluster definition path to lookup a value (e.g., `.metadata.annotations.region`) |
| `patch.default` | string | No       | Default value if the key is not found or empty                                   |
| `patch.prefix`  | string | No       | String prefix to prepend to the resolved value                                   |

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

### Root-level `ignoreDifferences`

| Field               | Type  | Required | Description                                                                                  |
| ------------------- | ----- | -------- | -------------------------------------------------------------------------------------------- |
| `ignoreDifferences` | array | No       | Passed through to the generated Application `spec.ignoreDifferences` (same shape as Argo CD) |

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
          key: .metadata.annotations.validation_mode
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
        key: .metadata.annotations.region
        default: "us-east-1"
```

This will resolve the value from the cluster definition at `.metadata.annotations.region`, or use `"us-east-1"` if not found.

Multi-level paths are supported:

```yaml
key: metadata.labels.environment # Looks up .metadata.labels.environment
```

3. The `system-kustomize` ApplicationSet will automatically deploy matching addons

## Creating a New Kustomize Addon

1. Create a new directory under `addons/kustomize/oss/` or `addons/kustomize/aws/`
2. Add your Kubernetes manifests to a `base/` subdirectory
3. Create a `kustomize.yaml` file defining the addon metadata
4. Reference your cluster definition values in patches if needed
5. Test by adding the feature label to a cluster definition and deploying
