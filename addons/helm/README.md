# Helm Add-ons

This directory contains the Helm add-on definitions for open source and cloud-specific add-ons.

- `oss`: The open source helm charts.
- `cloud`: The cloud specific helm charts.

## Helm Entry Format

The helm entry format is as follows:

```yaml
- feature: argo_workflows
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
  sync:
    wave: NUMBER
```

The following fields are supported:

- `feature`: The feature name used for enablement. Clusters enable the add-on by setting label `enable_<feature>: "true"`.
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

At minimum, each entry must include `feature`, `repository`, `namespace`, `version`, and one of `chart` or `path`.
