# Provision a Standalone Cluster

## :octicons-stack-24: Overview

The following walks through the steps required to provision a standalone cluster in AWS and use it to validate platform changes before raising a pull request. Here we use the Terraform code in the `terraform/` directory to provision the infrastructure and bootstrap ArgoCD.

## :octicons-beaker-24: When to Use This Workflow

Use a cloud cluster to validate changes that cannot be fully tested with a local Kind cluster:

- IAM and pod identity integration
- Cloud-provider-specific add-ons (EBS CSI, load balancers, ACK controllers)
- Karpenter and cluster autoscaler
- Storage class and persistent volume provisioning
- Real DNS and certificate issuance

For changes that only affect YAML structure, ApplicationSet logic, or Kustomize overlays, the [local development workflow](local.md) is faster.

## :octicons-project-roadmap-24: How Branch-Based Validation Works

The platform's Terraform module accepts a `revision_overrides` variable that overrides the `platform_revision` and `tenant_revision` values normally sourced from the cluster definition YAML. This means ArgoCD is pointed at your feature branch from the moment the cluster is bootstrapped.

```
┌──────────────────────────────────────────────────────────────────┐
│  terraform apply                                                  │
│    └─ revision_overrides.platform_revision = "feat/my-change"    │
│                                                                   │
│  ArgoCD bootstrapped with bootstrap Application                  │
│    └─ Sources kustomize/overlays/standalone/                      │
│         └─ Creates system-platform ApplicationSet                 │
│               └─ Reads cluster definition from tenant repo        │
│                    └─ Creates platform Application                │
│                          ├─ apps/registration/standalone  (branch)│
│                          ├─ apps/system/                  (branch)│
│                          └─ apps/tenant/                  (branch)│
│                                                                   │
│  Every push to the branch → ArgoCD detects within ~3 minutes     │
│    └─ Diffs are applied automatically                             │
└──────────────────────────────────────────────────────────────────┘
```

Because `revision_overrides` is set in the Terraform `.tfvars` file rather than the cluster definition, you do not need to commit a revision change to the cluster YAML — the override is injected at bootstrap time and flows through every ApplicationSet the platform creates.

## :octicons-rocket-24: Provision the Cluster

### 1. Create a feature branch

```shell
git checkout -b feat/my-change
```

### 2. Set the revision override

Open `terraform/variables/dev.tfvars` (or copy it to a new file for an isolated environment) and set `revision_overrides` to your branch name:

```hcl
## Path to the cluster definition
cluster_path = "../release/standalone-aws/clusters/dev.yaml"

## Override revision or branch for the platform and tenant repositories
revision_overrides = {
  platform_revision = "feat/my-change"
  tenant_revision   = "feat/my-change"
}
```

If your change only affects the platform repository leave `tenant_revision` pointing at `main` (or the current stable branch). Set both when your change spans both repositories.

### 3. Provision the cluster

```shell
# Using the default dev.tfvars
make standalone-aws

# Or, using a custom variables file
terraform -chdir=terraform apply -var-file=variables/my-feature.tfvars
```

This runs `terraform init`, selects (or creates) the `dev` workspace, and provisions an EKS cluster with ArgoCD bootstrapped to your branch.

### 4. Authenticate to the cluster

```shell
# Using the Makefile helper
CLUSTER_NAME=dev make eks-login

# Or directly via the AWS CLI
aws eks update-kubeconfig --name dev --region eu-west-2
```

## :octicons-browser-24: Understanding the Bootstrap Flow

Once the cluster is provisioned, ArgoCD drives everything. The bootstrap sequence is:

### Step 1 — Bootstrap Application

Terraform creates a single ArgoCD `Application` named `bootstrap` in the `argocd` namespace. It sources `kustomize/overlays/standalone/` from the platform repository at your branch revision. This overlay renders the top-level `system-platform` `ApplicationSet`.

### Step 2 — system-platform ApplicationSet

`system-platform` reads cluster definitions from the tenant repository (filtered by `cluster_path`). For each cluster definition it creates a `platform` Application. The `revision_overrides` injected by Terraform are threaded through here so that all downstream sources target your branch.

### Step 3 — platform Application (three sources)

The `platform` Application has three sources, all targeting your branch:

| Source path | Purpose |
|-------------|---------|
| `apps/registration/standalone` | Registers the cluster and maintains the ArgoCD cluster secret |
| `apps/system/` | Deploys platform add-ons (from `addons/`) |
| `apps/tenant/` | Deploys tenant workloads |

### Step 4 — system-registration

`apps/registration/standalone/` creates the `system-registration` Application, which runs the `charts/cluster-registration` Helm chart. This chart reads the cluster definition YAML and writes (or updates) an ArgoCD cluster `Secret` in the `argocd` namespace. That secret carries all the `metadata.labels` from the cluster definition, including every `enable_*` feature flag.

### Step 5 — system-helm and system-kustomize ApplicationSets

`apps/system/system-helm.yaml` and `apps/system/system-kustomize.yaml` use a matrix generator that:

1. Discovers add-on definition files from `addons/helm/**` or `addons/kustomize/**`.
2. Cross-references each add-on's `feature` field against the cluster secret labels.
3. Creates an Argo CD `Application` only when the matching `enable_<feature>: "true"` label is present on the cluster secret.

```
cluster definition YAML
  └─ metadata.labels.enable_kyverno: "true"
       └─ cluster secret (maintained by system-registration)
            └─ system-kustomize ApplicationSet filter
                 └─ Application: system-kust-kyverno-dev  ✓ created
```

Add-on configuration is layered: platform defaults from `config/<feature>/all.yaml` are merged with cloud-specific overrides and then tenant-specific overrides.

## :octicons-sync-24: Iterating on Changes

Once the cluster is running, your iteration loop is:

1. Make a change locally.
2. Commit and push to your branch.
3. Wait for ArgoCD to poll the branch (approximately every 3 minutes).
4. ArgoCD detects the diff and applies it automatically.

You can also force an immediate sync from the CLI:

```shell
# Force refresh (re-fetch from Git without waiting for the poll interval)
kubectl -n argocd get applications
argocd app refresh platform --hard

# Or using kubectl
kubectl -n argocd patch application platform \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

!!! tip "Tip"
    Push your commits before starting Terraform provisioning — the cluster bootstraps against the branch HEAD, so any commits already there are applied on first sync.

## :octicons-eye-24: Monitoring the Cluster

### Check all applications

```shell
kubectl -n argocd get applications
```

A healthy standalone cluster looks like:

```
NAME                              SYNC STATUS   HEALTH STATUS
bootstrap                         Synced        Healthy
platform                          Synced        Healthy
system-registration-dev           Synced        Healthy
system-cert-manager-dev           Synced        Healthy
system-kust-cert-manager-dev      Synced        Healthy
system-kyverno-dev                Synced        Healthy
system-kust-kyverno-dev           Synced        Healthy
...
```

### Inspect a specific application

```shell
# Overview
kubectl -n argocd get application system-kust-kyverno-dev -o yaml

# Sync and health conditions
kubectl -n argocd describe application system-kust-kyverno-dev
```

### Verify the cluster secret labels

The cluster secret is the source of truth for which features are enabled:

```shell
kubectl -n argocd get secret cluster-dev -o jsonpath='{.metadata.labels}' | jq .
```

If a label is missing or wrong, the add-on selector won't match and the Application will not be created.

### Watch ArgoCD logs

```shell
kubectl -n argocd logs deployment/argocd-application-controller -f
kubectl -n argocd logs deployment/argocd-repo-server -f
```

## :octicons-tools-16: Enabling or Disabling Features

Feature flags live in the cluster definition YAML. For the standalone development environment this is `release/standalone-aws/clusters/dev.yaml`.

```yaml
metadata:
  labels:
    enable_cert_manager: "true"
    enable_kyverno: "true"
    enable_external_secrets: "true"
```

To toggle a feature:

1. Edit the cluster definition YAML.
2. Commit and push to your branch.
3. ArgoCD runs `system-registration`, which updates the cluster secret.
4. `system-kustomize` / `system-helm` reconcile and create or delete the Application.

!!! note
    Removing a label causes the ApplicationSet to delete the corresponding Application, which triggers Argo CD to prune all resources the Application owned.

## :octicons-verified-24: Pre-PR Checklist (Cloud Validation)

Before raising a pull request after cloud validation:

- [ ] All ArgoCD Applications show `Synced` and `Healthy`
- [ ] The specific feature you changed behaves correctly on the cluster
- [ ] Unrelated Applications were not affected (check for unexpected `OutOfSync`)
- [ ] `make test` passes locally (schema and lint checks)
- [ ] The `revision_overrides` in your `.tfvars` file are **not** committed — they are a local testing aid
- [ ] Cluster definition changes (if any) reflect the intended production values, not the branch name

## :octicons-trash-24: Cleanup

```shell
# Using the Makefile
make destroy-standalone-aws

# Or using Terraform directly
terraform -chdir=terraform destroy -var-file=variables/dev.tfvars
```

Always run cleanup when finished to avoid ongoing infrastructure costs.

## :octicons-link-external-24: Related Documentation

- [Local Development](local.md) — Kind-based development for fast iteration
- [Hub & Spoke](hub.md) — Cloud validation for multi-cluster hub/spoke topology
- [Validation](validation.md) — Full validation checklist and test suite
