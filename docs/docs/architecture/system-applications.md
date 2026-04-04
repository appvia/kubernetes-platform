# Platform Applications

All of the platform applications are effectively sourced in via these two application sets

- [Helm Application](https://github.com/appvia/kubernetes-platform/blob/main/apps/system/system-helm.yaml): is responsible for reading the helm application definition, and installing the applications on all clusters who have the `enable_FEATURE` label.
- [Kustomize Applications](https://github.com/appvia/kubernetes-platform/blob/main/apps/system/system-kustomize.yaml): is responsible for installing any Kustomize applications from the Platform, again using the feature labels as a toggle.

## Helm Applications

All the helm applications deployable by the platform can be found in the [addons](https://github.com/appvia/kubernetes-platform/tree/main/addons) directory. For Helm applications

```shell
$ tree addons/helm -L2
addons/helm
├── README.md
├── cloud
│   └── aws.yaml
└── oss.yaml
```

The application set will sources all the `oss.yaml` items, and using the `{{ .cloud_vendor }}` attribute associated to the cluster, the appropriate cloud vendor file. Each of the files is a collection of Helm entries i.e

```YAML
- feature: metrics_server
  chart: metrics-server
  repository: https://kubernetes-sigs.github.io/metrics-server
  version: "3.12.2"
  namespace: kube-system
```

The following fields are supported:

- `feature`: The feature is a label which must be defined on the cluster definition for the feature to be enabled.
- `chart`: Optional chart name to use for the release (assuming the repository is a helm repository).
- `repository`: The repository is the location of a helm repository to install the chart from.
- `path`: Optional path inside the repository to install the chart from (assuming the repository is a git repository).
- `version`: The version of the chart to install or the git reference to use (e.g. `main`, `HEAD`, `v0.1.0`).
- `namespace`: The namespace to install the chart into.

All the fields are optional except for `path` and `chart`, as they are dependent on if the repository is a helm repository or a git repository.

Default Helm values for each addon **`feature`** live in the platform repository under `config/<feature>/` (for example `config/cert_manager/all.yaml`). The tenant repository can add matching paths under `<tenant_path>/config/<feature>/` to override or extend those defaults.

## Tenant overrides

The [system-helm](https://github.com/appvia/kubernetes-platform/blob/main/apps/system/system-helm.yaml) ApplicationSet uses three sources (`chart` + `ref: values` + `ref: tenant`) and merges value files in list order; **later** files override **earlier** ones. The `valueFiles` on the chart source are:

```yaml
valueFiles:
  - "$values/config/{{ .feature }}/all.yaml"
  - "$values/config/{{ .feature }}/{{ .metadata.labels.cloud_vendor }}.yaml"
  - "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/all.yaml"
  - "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/{{ .metadata.labels.cloud_vendor }}.yaml"
  - "$tenant/{{ .metadata.annotations.tenant_path }}/config/{{ .feature }}/{{ .metadata.labels.cluster_name }}.yaml"
```

So tenant cluster-specific and cloud-specific files override tenant `all.yaml`, which overrides platform defaults. See [System Application Sets](system-appsets.md) for the full template and behavior.
