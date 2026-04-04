# Addon's Overview

The **catalog** lists platform addons this repository can install: Helm charts under `addons/helm/` and Kustomize bundles under `addons/kustomize/`. The generated [Addons](features.md) page is the authoritative table of each addon’s **feature name**, **category**, and documentation links.

Nothing from the catalog is installed automatically. You choose what runs on a cluster by editing that cluster’s **cluster definition** in your tenant repository.

## Cluster definitions

A cluster definition is a YAML file (for example under `<tenant_path>/clusters/` in the tenant repo) that describes one cluster: identity, Git coordinates for the tenant and platform repositories, and metadata the platform uses when rendering ApplicationSets.

Among other fields, the definition includes `labels`. The platform treats several of those labels as **feature flags**: string labels whose names start with `enable_` and whose value is typically `"true"` or `"false"`.

Example (abbreviated):

```yaml
cluster_name: dev
cloud_vendor: kind
environment: release
tenant_repository: https://github.com/example/tenant.git
tenant_revision: main
tenant_path: clusters/prod
platform_repository: https://github.com/appvia/kubernetes-platform.git
platform_revision: main
platform_path: overlays/release
cluster_type: standalone
tenant: acme
labels:
  enable_cert_manager: "true"
  enable_kyverno: "true"
  enable_gateway_api: "true"
  enable_metrics_server: "true"
```

The exact keys required in a cluster definition are validated by the platform schema; see the [cluster definition model](https://github.com/appvia/kubernetes-platform/blob/main/AGENTS.md#cluster-definition-model) in `AGENTS.md` for the full contract.

## Enabling addons with `enable_<feature>`

Each addon declares a **`feature`** name in its definition (for example `cert_manager` or `gateway_api`). The platform wires that name to a cluster label:

| Label pattern      | Meaning                                                                                                                               |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `enable_<feature>` | When set to `"true"`, the matching system ApplicationSet may create an Argo CD Application for that addon on clusters that select it. |

So for `feature: cert_manager` you set:

```yaml
labels:
  enable_cert_manager: "true"
```

For `feature: gateway_api` (a Kustomize addon) you set:

```yaml
labels:
  enable_gateway_api: "true"
```

The [Addons](features.md) page lists the precise **`enable_…`** flag for every Helm and Kustomize entry.

### Helm and Kustomize

- **Helm addons** are discovered from `addons/helm/**/*.yaml`. The `feature` field on each list item drives the `enable_<feature>` label.
- **Kustomize addons** use `kustomize.feature` in each `addons/kustomize/**/kustomize.yaml` file; the same `enable_<feature>` convention applies.

Other keys on those definitions (chart source, namespace, patches, and so on) are used by the system ApplicationSets to render the Argo CD Application; they are not duplicated in the cluster definition unless the platform documents patch-from-metadata behavior for a specific addon.

## Choosing addons for an environment

1. Open the [Addons](features.md) catalog and note the **feature flag** column for each capability you need.
2. In the **cluster definition** for that environment, under `labels`, set `enable_<feature>: "true"` for each addon you want.
3. Commit to the tenant repository and let GitOps sync. Argo CD will reconcile the generated system applications for that cluster.

Disable an addon by removing the label or setting it to a value other than `"true"` (the ApplicationSets expect `"true"` for installation).

## Cloud and overlay considerations

Some addons only appear in certain platform layouts (for example AWS-oriented Helm files under `addons/helm/cloud/`). Your cluster’s `cloud_vendor`, `platform_path`, and the platform overlay still determine which generators run and which addon files are visible. If an addon does not apply to your cloud or topology, enabling its feature flag will have no effect until the matching definitions are included in your bootstrap overlay.

For deeper mechanics (ApplicationSets, matrix generators, and label selectors), see [System Application Sets](../architecture/system-appsets.md).
