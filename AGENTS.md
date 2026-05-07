# AGENTS.md

## Purpose

This repository is a GitOps platform baseline for managing Kubernetes clusters with Argo CD.
It is designed to be consumed by a separate tenant repository that holds cluster definitions,
application definitions, and environment-specific overrides.

The platform supports two operating models:

- Standalone: the platform manages the same cluster it runs on.
- Hub and spoke: a hub cluster runs the control plane and manages spoke clusters.

At runtime, cluster definitions from the tenant repository drive which platform components,
tenant applications, and system workloads are rendered and deployed.

## How The Platform Works

The control flow is:

1. A cluster is bootstrapped with an Argo CD `bootstrap` application.
2. That bootstrap application points at one of the platform overlays in `kustomize/overlays/`.
3. The overlay renders a top-level `system-platform` `ApplicationSet`.
4. `system-platform` reads cluster definitions from the tenant repository.
5. From each cluster definition, the platform installs:
   - registration resources from `apps/registration/`
   - system platform application sets from `apps/system/`
   - tenant-facing application sets from `apps/tenant/`
6. The `apps/system/` ApplicationSets discover platform addons from `addons/`.
7. The `apps/tenant/` ApplicationSets discover tenant workloads from the tenant repository.

The key mechanism throughout is Argo CD `ApplicationSet` matrix generation plus cluster label
selection. Feature flags are usually expressed as cluster labels such as `enable_kyverno: "true"`.

## Repository Overview

- `apps/`: Argo CD `ApplicationSet` and registration definitions.
- `addons/`: platform-managed addon definitions.
- `config/`: default values for platform Helm addons.
- `kustomize/`: overlays that bootstrap the platform in different topologies.
- `release/`: example tenant-style content used for local testing and demos.
- `scripts/`: validation and local bootstrap scripts.
- `docs/`: published documentation site.
- `terraform/`: AWS-oriented infrastructure and bootstrap helpers.

## Code Structure

### `apps/system/`

This is the platform addon engine.

- `system-helm.yaml`: discovers Helm addon definitions and creates Argo CD Applications.
- `system-kustomize.yaml`: discovers Kustomize addon definitions and creates Argo CD Applications.

Important behavior:

- Both use a matrix of Git file discovery plus cluster selection.
- Both require `environment` to exist on the cluster secret metadata.
- Both use `enable_*` style cluster labels to decide whether an addon is installed.
- Both support `RollingSync` with `phase: primary|secondary`.

### `apps/tenant/`

This is the tenant workload engine.

- `apps-helm.yaml`: deploys tenant application Helm releases from the tenant repository.
- `apps-kustomize.yaml`: deploys tenant application Kustomize workloads.
- `system-helm.yaml`: deploys tenant-managed system Helm releases.
- `system-kustomize.yaml`: deploys tenant-managed system Kustomize workloads.
- `namespace/`: baseline namespace manifests, labels, bindings, and policies applied before tenant workloads.

The tenant application sets derive namespace names from the tenant repository path layout. Regular tenant applications use folder structure at `workloads/applications/<namespace>/...` where the namespace is derived from the folder name. However, system applications at `workloads/system/<folder>/...` require explicit `namespace.name` specification in the workload definition.

### `apps/registration/`

This is the bridge between cluster definitions and Argo CD cluster registration.

- `standalone/`: registration flow for self-managed clusters.
- `hub/`: registration flow for hub/spoke mode.

### `addons/`

This is where platform-managed capabilities live.

- `addons/kustomize/oss/`: cloud-agnostic addons.
- `addons/kustomize/aws/`: AWS-specific addons.
- `addons/helm/`: Helm addon definitions referenced by `apps/system/system-helm.yaml`.

The repository currently has rich documentation and examples for Kustomize addons. Helm addon
support exists in the application sets and config layout, but the current tree appears to have no
checked-in `addons/helm/**/helm.yaml` addon definitions.

### `config/`

Default values for platform Helm addons.

The folder name maps to the addon feature name. `apps/system/system-helm.yaml` resolves values in
this order:

1. Tenant repo cluster-specific override
2. Tenant repo cloud-specific override
3. Tenant repo global override
4. Platform repo cloud-specific default in `config/<feature>/`
5. Platform repo global default in `config/<feature>/all.yaml`

### `kustomize/overlays/`

Bootstrap entrypoints for different deployment topologies.

- `standalone/`: self-managed cluster bootstrap.
- `hub/`: hub control-plane bootstrap.

These overlays patch the top-level `system-platform` application set so that it points at the
correct tenant repository, cluster definition path, and platform revision.

### `release/`

This acts like a mock tenant repository for local development and examples.

Useful examples:

- `release/standalone/clusters/dev.yaml`: sample standalone cluster definition
- `release/standalone/workloads/applications/helm-app/dev.yaml`: sample tenant Helm app
- `release/standalone/workloads/applications/kustomize-app/dev.yaml`: sample tenant Kustomize app
- `release/standalone/workloads/system/ingress-system/dev.yaml`: sample tenant system app

## Cluster Definition Model

The cluster definition is the core input into the platform. It typically contains:

- cluster identity: `cluster_name`, `cluster_type`, `environment`, `cloud_vendor`
- source repositories: `tenant_repository`, `tenant_revision`, `platform_repository`, `platform_revision`
- repository paths: `tenant_path`, `platform_path`
- tenant metadata: `tenant`, `annotations`, `cluster_authentication`
- feature flags: `labels.enable_*`

Feature flags are the main switch for platform addons. Examples from the repository include:

- `enable_cert_manager`
- `enable_external_secrets`
- `enable_kyverno`
- `enable_gateway_api`
- `enable_kube_prometheus_stack`

The application sets rely heavily on these labels, so any guide or automation added to this repo
should treat the cluster definition as the primary API.

## How To Add Addons

### Add a Kustomize addon

This is the clearest supported extension model in the current repository.

1. Create a directory under `addons/kustomize/oss/<name>/` or `addons/kustomize/aws/<name>/`.
2. Add a `kustomize.yaml` file.
3. Add the manifests or overlay referenced by `kustomize.path`, usually `base/`.
4. Define:
   - `kustomize.feature`: feature name used by the application set selector
   - `kustomize.path`: path to the overlay
   - `namespace.name`: destination namespace
   - optional `sync.phase`, `commonLabels`, `commonAnnotations`, `patches`
5. Enable it in the cluster definition using `labels.enable_<feature>: "true"`.

Example shape:

```yaml
kustomize:
  feature: external_secrets
  path: base
  patches:
    - target:
        kind: ClusterSecretStore
        name: secrets-store
      patch:
        - op: replace
          path: /spec/provider/aws/region
          key: .metadata.annotations.region
          default: unknown

namespace:
  name: external-secrets

sync:
  phase: secondary
```

Notes:

- The application set turns `kustomize.feature` into a selector key `enable_<feature>`.
- Patches can pull values from cluster metadata using dot-paths such as `.metadata.labels.cluster_name`.
- Use `phase: secondary` when the addon depends on earlier components.

### Add a Helm addon

The repository supports Helm-driven platform addons through `apps/system/system-helm.yaml` and
`config/`, even though the current tree does not include concrete Helm addon definition files.

To add one:

1. Create an addon definition under `addons/helm/` or a cloud-specific subdirectory used by your overlay.
2. Define the chart source and feature name.
3. Add default values under `config/<feature>/all.yaml` and optionally `config/<feature>/<cloud>.yaml`.
4. Enable it from cluster definitions via `labels.enable_<feature>: "true"`.

Expected definition shape:

```yaml
feature: cert_manager
chart: cert-manager
repository: https://charts.jetstack.io
version: 1.16.0
namespace: cert-manager
parameters:
  - name: clusterName
    value: .metadata.labels.cluster_name
    default: dev
```

The system Helm application set supports:

- inline `values`
- parameter substitution from cluster metadata
- tenant-side overrides in `config/<feature>/`
- cloud-specific and cluster-specific value file resolution

## How To Customize

Customization is intentionally split between platform defaults in this repository and environment-
specific state in the tenant repository.

### Customize platform behavior per cluster

Edit the tenant cluster definition.

Typical changes:

- turn platform features on or off with `labels.enable_*`
- provide patch values through cluster labels or annotations
- move a cluster to a different platform release with `platform_revision`
- switch deployment topology using `cluster_type` and `platform_path`

### Customize platform Helm addon values

Put value files in the tenant repository under:

- `config/<feature>/<cluster_name>.yaml`
- `config/<feature>/<cloud_vendor>.yaml`
- `config/<feature>/all.yaml`

These override this repository's defaults under `config/<feature>/`.

### Customize tenant applications

Put workload definitions in the tenant repository.

Application workloads:

- `workloads/applications/<namespace>/<app>/<cluster>.yaml`
- `workloads/applications/<namespace>/<cluster>.yaml`

System workloads:

- `workloads/system/<folder>/<app>/<cluster>.yaml`
- `workloads/system/<folder>/<cluster>.yaml`

**Important:** For system workloads, each definition file must include a `namespace.name` field that explicitly specifies
the namespace where the application will be deployed. The folder structure is organizational only for system applications;
namespace names are no longer derived from the folder path for system workloads.

Helm tenant apps can add values files under a sibling `values/` directory. The application sets
look for:

- `<cluster_name>.yaml`
- `<environment>.yaml`
- `<tenant>.yaml`
- `all.yaml`

### Customize Kustomize workloads with cluster metadata

Both platform and tenant Kustomize flows support patches that resolve values from the merged
ApplicationSet context. Common examples:

- `.metadata.labels.cluster_name`
- `.metadata.labels.environment`
- `.metadata.annotations.region`
- `.server`

If the path does not exist, provide a `default`.

### Customize Kyverno policies

Kyverno policies are deployed via a Helm chart at `charts/kyverno-policies/`. They are feature-flagged
with `enable_kyverno_policies` (separate from `enable_kyverno` which installs the controller).

**Enable policies in cluster definition:**

```yaml
metadata:
  labels:
    enable_kyverno: "true" # Install Kyverno controller
    enable_kyverno_policies: "true" # Deploy policies
```

**Customize policies at tenant level:**

1. **Global environment defaults** - `config/kyverno_policies/all.yaml`:
   - Enable/disable policies cluster-wide
   - Set global namespace exclusions (e.g., exclude `cert-manager` from all policies)

2. **Cloud-specific defaults** - `config/kyverno_policies/aws.yaml`:
   - AWS-specific policy settings (e.g., enable `denyEksResources`)

3. **Cluster-specific overrides** - `config/kyverno_policies/<cluster_name>.yaml`:
   - Override policies for a specific cluster
   - Configure registry restrictions with allowed registries

**Example: Enable registry restriction policy in simple mode**

```yaml
# release/standalone-aws/config/kyverno_policies/dev.yaml
policies:
  restrictImageRegistries:
    enabled: true
    useComplexConfig: false
    validationFailureAction: audit
    allowedRegistries:
      - gcr.io
      - docker.io
      - ecr.aws
```

**Example: Enable registry restriction with per-registry namespace rules (complex mode)**

```yaml
policies:
  restrictImageRegistries:
    enabled: true
    useComplexConfig: true
    validationFailureAction: enforce
    registries:
      - name: gcr.io
        allowedNamespaces:
          - prod
          - staging
      - name: docker.io
        allowedNamespaces: [] # Empty = allowed in all namespaces (minus global exclusions)
      - name: ecr.aws
        allowedNamespaces:
          - prod
```

**How policies resolve configuration:**

Policy values are resolved in this order (first match wins):

1. Tenant cluster-specific: `config/kyverno_policies/<cluster_name>.yaml`
2. Tenant cloud-specific: `config/kyverno_policies/<cloud_vendor>.yaml`
3. Tenant global: `config/kyverno_policies/all.yaml`
4. Platform cloud-specific: `config/kyverno_policies/<cloud_vendor>.yaml` (in this repo)
5. Platform global: `config/kyverno_policies/all.yaml` (in this repo)

This allows tenant repositories to override any policy setting while inheriting platform defaults.

## Development And Validation

Useful commands from `Makefile`:

- `make standalone`: boot a local standalone kind environment
- `make hub`: boot a local hub environment
- `make spoke`: create a local spoke cluster
- `make validate`: run the main validation suite
- `make lint`: lint YAML and platform applications
- `make e2e`: run local end-to-end validation
- `make serve-docs`: run the docs site locally

Validation scripts worth knowing:

- `scripts/validate-cluster-definitions.sh`
- `scripts/validate-helm-addons.sh`
- `scripts/validate-kustomize.sh`
- `scripts/validate-kyverno.sh`
- `scripts/validate-helm-charts.sh`

CI in `.github/workflows/ci.yml` runs the same categories of checks on pull requests.

## Guidance For Future Agents

- Treat the tenant cluster definition as the primary contract for platform behavior.
- When changing `apps/system/system-*.yaml`, also inspect the related overlay patching in
  `kustomize/overlays/*/platform.yaml` because those files rewrite generator paths and revisions.
- Keep addon changes minimal and label-driven; the platform is built around feature discovery,
  not hard-coded application lists.
- Prefer extending existing `ApplicationSet` patterns over introducing new bootstrap paths.
- Use `release/` as a concrete, repo-local example of how a tenant repository is expected to look.

## Practical Summary

This codebase is not an application in the traditional sense. It is a GitOps framework composed of:

- bootstrap overlays
- ApplicationSets
- addon definitions
- default values
- example tenant content

If you are adding capability, usually the right place is one of:

- `addons/` for platform-managed shared features
- `apps/system/` for system-level deployment logic
- `apps/tenant/` for tenant workload orchestration logic
- `config/` for default Helm values
- tenant repository content for environment-specific customization
