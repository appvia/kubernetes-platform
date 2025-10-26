# Helm Add-ons

This directory contains the helm charts for the open source and cloud specific addons.

- `oss`: The open source helm charts.
- `cloud`: The cloud specific helm charts.

## Helm Entry Format

The helm entry format is as follows:

```yaml
- feature: enable_argo_workflows
  chart: argo-workflows
  repository: https://argoproj.github.io/argo-helm
  version: "0.45.8"
  namespace: argocd
  parameters:
    - name: global.settings
      value: MY_VALUE
    - name: global.settings.hostname
      value: .metadata.labels.cluster_name
      default: mydefault_value
  values: |
    my_value: hello    
```

The following fields are supported:

- `feature`: The feature is a label which must be defined on the cluster definition for the feature to be enabled.
- `chart`: Optional chart name to use for the release (assuming the repository is a helm repository).
- `repository`: The repository is the location of a helm repository to install the chart from.
- `path`: Optional path inside the repository to install the chart from (assuming the repository is a git repository).
- `version`: The version of the chart to install or the git reference to use (e.g. `main`, `HEAD`, `v0.1.0`).
- `namespace`: The namespace to install the chart into.
- `parameters`: A lsit of helm parameters to define on the application (these can reference metadata associated to the cluster)
  - name: Path inside the helm values which is being replaced.
  - value: A default or reference to the cluster metadata.
  - default: The value to use if the value is empty.
- `values`: A multiline string of helm values to add to the application.

All the fields are optional except for `path` and `chart`, as they are dependent on if the repository is a helm repository or a git repository.
