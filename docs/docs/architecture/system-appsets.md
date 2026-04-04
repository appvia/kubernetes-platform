# :material-application-cog: System ArgoCD Application Sets

All the application set which compose the platform can be found in

- The [apps/](https://github.com/appvia/kubernetes-platform/tree/main/apps) directory, contains the bulk to the system and tenant appsets.
- The [kustomize/overlays/standalone](https://github.com/appvia/kubernetes-platform/tree/main/kustomize/overlays/standalone) entrypoint.
- The [kustomize/overlays/hub](https://github.com/appvia/kubernetes-platform/tree/main/kustomize/overlays/hub) entrypoint.

### :material-application-array-outline: Platform Application Set

The platform application sets are the entrypoint application sets for the standalone and hub cluster types. These can be found under the [kustomize/overlays](https://github.com/appvia/kubernetes-platform/tree/main/kustomize/overlays) directory. They are solely responsible for sourcing the following application sets details below, applying kustomize patches where required.

### :material-application-array-outline: Cluster Registration Application Set

The [system-registration](https://github.com/appvia/kubernetes-platform/tree/main/apps/registration/standalone) and the [hub version](https://github.com/appvia/kubernetes-platform/tree/main/apps/registration/hub) are responsible for sourcing the cluster definitions from the tenant repository and producing a cluster secret, using the [charts/cluster-registration](https://github.com/appvia/kubernetes-platform/tree/main/charts/cluster-registration) helm chart.

### :material-application-array-outline: System Helm Application Set

The [system-helm](https://github.com/appvia/kubernetes-platform/tree/main/apps/system/system-helm.yaml) application set is responsible for installing the core platform components.

This application set merges the [addons](https://github.com/appvia/kubernetes-platform/tree/main/addons), and then filters the applications using the labels attached within the cluster.

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: PLATFORM_REPO
            revision: PLATFORM_REVISION
            files:
              - path: "addons/helm/cloud/**/*.yaml"
              - path: "addons/helm/*.yaml"
          selector:
            matchExpressions:
              - key: version
                operator: Exists
              - key: repository
                operator: Exists
              - key: namespace
                operator: Exists
        - clusters:
            selector:
              matchExpressions:
                - key: environment
                  operator: Exists
                - key: "enable_{{ .feature }}"
                  operator: In
                  values: ["true"]
```

The [addons](https://github.com/appvia/kubernetes-platform/tree/main/addons) are a collection of helm application definitions i.e

```YAML
- feature: metrics_server
  chart: metrics-server
  repository: https://kubernetes-sigs.github.io/metrics-server
  version: "3.12.2"
  namespace: kube-system

- feature: volcano
  chart: volcano
  repository: https://volcano-sh.github.io/helm-charts
  version: "1.9.0"
  namespace: volcano-system
```

Assuming the cluster selected has a label `enable_metrics_server=true` and `enable_volcano=true` in the cluster definition, the helm applications will be installed.

Each generated Application uses **three sources**: the Helm chart (first source), the **platform** repository as `ref: values` (so `$values/...` paths resolve), and the **tenant** repository as `ref: tenant` (so `$tenant/...` paths resolve). The chart source is templated in two ways:

- When the addon definition sets `repository: platform`, the chart is loaded from the platform repository (`repoURL` / `targetRevision` from the cluster definition) using `path` (and no `chart` field).
- Otherwise, the chart is loaded from the external Helm repository (`repository`, `version`, `chart`, optional `repository_path`).

`valueFiles` are always attached to the **first** source. They are listed below in merge order. Argo CD Helm merges these files in order; **later files override earlier ones** for the same keys.

```yaml
sources:
  # First source: chart from platform path OR external Helm repo (see templatePatch in system-helm.yaml)
  - repoURL: "<platform or chart repository>"
    targetRevision: "<revision>"
    # chart: "<chart>"   # present for external repos; omitted when repository is platform
    path: "<optional path to chart in repo>"
    helm:
      releaseName: "{{ normalize (default .feature .release_name) }}"
      ignoreMissingValueFiles: true
      valueFiles:
        - "$values/config/{{ .feature }}/all.yaml"
        - "$values/config/{{ .feature }}/{{ .metadata.labels.cloud_vendor }}.yaml"
        - "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/all.yaml"
        - "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/{{ .metadata.labels.cloud_vendor }}.yaml"
        - "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/{{ .metadata.labels.cluster_name }}.yaml"
  - repoURL: "{{ .metadata.annotations.platform_repository }}"
    targetRevision: "{{ .metadata.annotations.platform_revision }}"
    ref: values
  - repoURL: "{{ .metadata.annotations.tenant_repository }}"
    targetRevision: "{{ .metadata.annotations.tenant_revision }}"
    ref: tenant
```

!!! note "Tenant overrides"

    Tenant value files live under `<tenant_path>/config/<feature>/` in the tenant repository, using the addon **`feature`** name (the same identifier as in `enable_<feature>`), not necessarily the Helm chart name—for example `config/cert_manager/all.yaml`.

---

#### :material-cog: Helm Values and Configuration

Default Helm values for addons shipped with the platform live in this repository under [config/](https://github.com/appvia/kubernetes-platform/tree/main/config), in directories named after the addon **`feature`** (for example `config/cert_manager/all.yaml`). Tenant repositories mirror that layout under their `tenant_path` to override or extend defaults.

**Merge order** (first file is the base; each subsequent file overrides overlapping keys):

1. `$values/config/<feature>/all.yaml` (platform)
2. `$values/config/<feature>/<cloud_vendor>.yaml` (platform)
3. `$tenant/<tenant_path>/config/<feature>/all.yaml`
4. `$tenant/<tenant_path>/config/<feature>/<cloud_vendor>.yaml`
5. `$tenant/<tenant_path>/config/<feature>/<cluster_name>.yaml`

So the strongest tenant override is the cluster-specific file; missing files are skipped because `ignoreMissingValueFiles` is true.

The canonical template is in [apps/system/system-helm.yaml](https://github.com/appvia/kubernetes-platform/blob/main/apps/system/system-helm.yaml).

Another way to pass values to the Helm applications is via `parameters` i.e

```
- feature: volcano
  chart: volcano
  repository: https://volcano-sh.github.io/helm-charts
  version: "1.9.0"
  namespace: volcano-system
  parameters:
    - name: serviceAccount.annotations.test
      value: default_value

    # Reference metadata from the cluster definition (leading dot triggers lookup)
    - name: serviceAccount.annotations.test2
      value: .metadata.labels.cloud_vendor
```

#### Helm values key points

- Value file paths use **`feature`**, not the chart name, unless they happen to be the same in a given addon definition.
- After value files are merged, the addon definition may also supply inline Helm `values` and `parameters` (including values pulled from cluster metadata); those are applied as part of the same Helm source.

## :material-application-array-outline: System Kustomize Application Set

The [system-kustomize](https://github.com/appvia/kubernetes-platform/blob/main/apps/system/system-kustomize.yaml) is responsible for provisioning any kustomize related functionality from the system. The application set use's a [git generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/) to source all the `kustomize.yaml` files from the [addons/kustomize](https://github.com/appvia/kubernetes-platform/tree/main/addons/kustomize) directory.

Kustomize applications are defined in a similar manner to helm applications, with the following fields:

```YAML
---
kustomize:
  ## Human friendly description
  description: ""
  ## The feature flag used to enable the feature
  feature: <FEATURE>
  ## The path to the kustomize overlay
  path: base
  ## Optional patches to apply to the kustomize overlay
  patches:
    - target:
        kind: <KIND>
        name: <NAME>
      path: <PATH>
      key: <KEY>
      default: <DEFAULT>

  ## Optional labels applied to all resources
  commonLabels:
    app.kubernetes.io/managed-by: argocd

  ## Optional annotations applied to all resources
  commonAnnotations:
    argocd.argoproj.io/sync-options: Prune=false

## The namespace options
namespace:
  ## The name of the namespace to deploy the application
  name: kube-system

## Synchronization options
sync:
  ## How to order the deployment of the resources
  phase: primary
```

Note, kustomize application support the use of patching, but taking fields from the cluster definitions labels and annotations, and using then as values in the patches.

```yaml
## Optional patches to apply to the kustomize overlay
patches:
  - target:
      kind: Namespace
      name: test
    path: /metadata/annotations/environment
    key: metadata.annotations.environment
    default: unknown
```

In the above example, the `metadata.annotations.environment` value from the cluster definition will be used as the value for the patch.

### External Kustomize Repository

System applications using Kustomize also support the option to source in an external repository. This can be used by definiting the following

```yaml
kustomize:
  ## The feature used to toggle the addon
  feature: kyverno
  ## The path inside the repositor
  path: kustomize
  ## External repository, else by default we use the platform repository and revision
  repository: https://github.com/appvia/exteranl-repository.git
  ## The revision for the above repository
  revision: HEAD
```
