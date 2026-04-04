# Standalone Deployment

!!! note "Note"

    This documentation is a work in progress and is subject to change. Please check back regularly for updates.

The following describes a typical standalone deployment. For a complete walk-through and a repository you can fork or clone, use the **[Kubernetes Platform Template](https://github.com/appvia/kubernetes-platform-template)**. Its [README](https://github.com/appvia/kubernetes-platform-template/blob/main/README.md) (same content as the [raw README](https://raw.githubusercontent.com/appvia/kubernetes-platform-template/refs/heads/main/README.md)) explains how to consume this platform, provision clusters, and wire GitOps—including **promotion-style workflows** across environments.

## :octicons-cross-reference-24: Example scenario

Using the following scenario, we have:

| Feature                       | Description                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Multiple Environments         | Two Kubernetes clusters (`dev` and `prod`) representing different environments in the application life cycle |
| Independent Platform Upgrades | Each cluster runs its own version of the platform, allowing independent platform upgrades and testing        |
| GitOps Workflows              | Application teams can deploy and manage their applications using GitOps workflows                            |
| Controlled Promotion          | Changes to both platform and applications can be promoted between environments in a controlled manner        |
| Version Tracking              | Platform versions are defined in code, enabling clear tracking of what's running where                       |
| Team Autonomy                 | Application teams have autonomy to deploy, test, and promote                                                 |

## Template overview

The [Kubernetes Platform Template](https://github.com/appvia/kubernetes-platform-template) is a **baseline tenant repository**: it shows how to point clusters at this platform, lay out `clusters/`, `workloads/`, and `config/`, and optionally drive AWS EKS with Terraform. It also ships **GitHub Actions** that validate changes and enforce **Helm chart version ordering** between environment files so promotions stay auditable. You do not have to use every environment; the checks walk a configurable promotion chain and only validate Helm workloads that declare `helm.version`.

## :octicons-cpu-24: Required binaries

- Kind (<https://kind.sigs.k8s.io/docs/user/quick-start/#installation>)
- kubectl (<https://kubernetes.io/docs/tasks/tools/#kubectl>)
- Terraform (<https://developer.hashicorp.com/terraform/downloads>)

## :octicons-project-roadmap-24: Set up your tenant repository

### 1. Create a copy in your organization

Use GitHub’s “Use this template” on [appvia/kubernetes-platform-template](https://github.com/appvia/kubernetes-platform-template), or clone and push to a new repository under your org:

```shell
git clone https://github.com/appvia/kubernetes-platform-template.git
cd kubernetes-platform-template
# Add your remote and push, or rename the origin after creating an empty repo
git remote set-url origin https://github.com/<your-org>/<your-tenant-repo>.git
git push -u origin main
```

### 2. Point cluster definitions at your repository

Edit each file under `clusters/` (for example `clusters/dev.yaml`) and set **`tenant_repository`** and **`tenant_revision`** to your repository URL and branch (or tag/commit):

```yaml
tenant_repository: https://github.com/<your-org>/<your-tenant-repo>.git
tenant_revision: main
```

Argo CD ApplicationSets on the platform read these fields so workloads and config are sourced from **your** repo. **`platform_repository`** usually stays on the upstream [kubernetes-platform](https://github.com/appvia/kubernetes-platform) unless you maintain a fork.

### 3. Customize and push

Adjust `config/` to override [platform defaults in `kubernetes-platform/config`](https://github.com/appvia/kubernetes-platform/tree/main/config), add or remove apps under `workloads/applications/` and `workloads/system/`, and set Terraform values under `terraform/values/` if you use the included EKS flow. Commit and push to your default branch.

### Folder structure (template)

The template layout is documented in its README; in short:

- **clusters/** — cluster definition YAML per environment
- **workloads/** — Argo CD application definitions. The **`applications/`** and **`system/`** paths are not arbitrary: the platform maps them to different **Argo CD AppProjects** so each class of workload runs under a different permission model. Those projects are defined in [`apps/argocd/projects.yaml`](https://raw.githubusercontent.com/appvia/kubernetes-platform/refs/heads/main/apps/argocd/projects.yaml).
  - **`workloads/applications/`** — ordinary tenant apps. They are synced under the **`tenant-apps`** project, which restricts cluster-scoped resources (for example only `Namespace` is allowed on the cluster scope) so workloads cannot destabilize platform namespaces or install arbitrary cluster-wide objects.
  - **`workloads/system/`** — tenant-managed **system** workloads that need **higher privilege** than the default platform addons cover: operators, CRDs, and similar components. These sync under the **`tenant-system`** project, which allows broader cluster-scoped permissions than `tenant-apps`, so you can run capabilities the platform does not ship while still keeping them separate from unrestricted platform control plane projects.
- **config/** — overrides for platform defaults (for example Kyverno policies, Argo CD settings)
- **terraform/** — optional AWS/EKS provisioning and platform bootstrap
- **.github/** — CI workflows (validation, promotion checks)

## Cluster definitions

A typical cluster definition matches the shape used in the template, for example [clusters/dev.yaml](https://github.com/appvia/kubernetes-platform-template/blob/main/clusters/dev.yaml):

```yaml
## The name of the tenant cluster
cluster_name: dev
## The cloud vendor to use for the tenant cluster
cloud_vendor: aws
## The environment to use for the tenant cluster
environment: dev
## The repository containing the tenant configuration (your copy of the template)
tenant_repository: https://github.com/<your-org>/<your-tenant-repo>.git
## The revision to use for the tenant repository
tenant_revision: main
## The path inside the tenant repository to use for the tenant cluster
tenant_path: ""
## The repository containing the platform configuration
platform_repository: https://github.com/appvia/kubernetes-platform.git
## The revision to use for the platform repository
platform_revision: main
## The path inside the platform repository (fixed for the platform; do not change)
platform_path: overlays/release
## The type of cluster we are (standalone, spoke or hub)
cluster_type: standalone
## The name of the tenant
tenant: tenant
## We use labels to enable/disable features in the tenant cluster
labels:
  enable_cert_manager: "true"
  enable_external_dns: "false"
  enable_external_secrets: "true"
  enable_kro: "true"
  # Enable the Kyverno admission controller
  enable_kyverno: "true"
  # Enable the default policies
  enable_kyverno_policies: "true"
  # Enable the metrics service
  enable_metrics_server: "true"
```

Noteworthy fields include **`labels`**: the platform uses them to decide whether each capability is installed (see the [system Helm ApplicationSet](https://github.com/appvia/kubernetes-platform/blob/main/apps/system/system-helm.yaml) for the pattern).

## Platform upgrade flow

**Platform team** — The owners of [kubernetes-platform](https://github.com/appvia/kubernetes-platform) validate, test, and publish a **known artifact**: a branch, tag, or commit that others can rely on. Consumers do not guess at moving targets; they pin to that artifact in Git.

**Your responsibility (tenant / cluster team)** — Each cluster’s definition declares which artifact to run via **`platform_repository`** (usually the upstream platform repo, or your fork) and **`platform_revision`** (branch, tag, or SHA).

**Promoting through environments** — It is **your** team’s job to roll platform revisions through your lifecycle (for example dev, then staging, then production). Typical flow:

1. Adopt a new `platform_revision` on a **lower** environment first; let Argo CD reconcile and exercise the change.
2. After validation, update **`platform_revision`** on the next environment’s cluster definition file in your tenant repository.
3. Merge to Git; **GitOps** applies the new revision without ad-hoc cluster surgery.

Clusters can intentionally run **different** `platform_revision` values so non-production leads production—matching the “Independent Platform Upgrades” idea in the scenario table above.

## Standalone topology

Under standalone:

- Argo CD runs on the same cluster it manages.
- The tenant repository pins the platform revision and holds the application stack.

## CI checks and environment promotion

The template’s **Validation** workflow (`.github/workflows/ci.yml`) runs on pushes and pull requests. Jobs typically include YAML validation, Terraform validate/lint, scripts, schema checks, and on pull requests **commitlint**. Configure **branch protection** on `main` to require these checks before merge; the template README lists the job names to require.

### Promotion validation (composite action)

The **Validate Promotion** job uses the [`kubernetes-platform-promotion`](https://github.com/appvia/appvia-cicd-workflows/blob/main/.github/actions/kubernetes-platform-promotion/README.md) composite action from [appvia-cicd-workflows](https://github.com/appvia/appvia-cicd-workflows). The same documentation is available in [raw form](https://raw.githubusercontent.com/appvia/appvia-cicd-workflows/refs/heads/main/.github/actions/kubernetes-platform-promotion/README.md). For Helm apps under `workloads/applications/`, each environment file (for example `dev.yaml`, `staging.yaml`, `prod.yaml`) carries `helm.version`. The validator uses a configurable **promotion order** (defaults include `dev,qa,staging,uat,prod`; the template may pass a different `promotion-order` in `.github/workflows/ci.yml`). For each changed env file it finds the nearest existing **predecessor** in that order and compares semver: the changed environment’s version must **not be greater than** the predecessor’s—so you cannot **skip ahead** (for example landing `prod.yaml` at `2.0.0` while `staging.yaml` is still `1.0.0`) unless you also raise the predecessor in the same pull request. A downstream version **below** upstream still passes while a promotion is in progress. Kustomize-only files are skipped; invalid or missing semver on Helm files can fail the check. For hotfixes, add the `promotion/skip-validation` label on the PR to bypass validation—see the action README for inputs, permissions, workflow examples, and edge cases.
