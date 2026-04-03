# Kyverno Policies

## Overview

Kyverno is a policy engine designed for Kubernetes that validates, mutates, and generates configurations using policies as Kubernetes resources. It provides key features like:

- Policy validation and enforcement
- Resource mutation and generation
- Image verification and security controls
- Audit logging and reporting
- Admission control webhooks

The following policies are shipped by default in this platform to enforce security best practices, resource management, and operational standards.

For detailed information about Kyverno's capabilities, refer to the [official documentation](https://kyverno.io/docs/) or [policy library](https://kyverno.io/policies/).

---

## Enabling Kyverno Policies

Kyverno policies are deployed as a Helm chart and are separate from the Kyverno controller installation.

### Enable in Cluster Definition

In your cluster definition, enable both the controller and the policies:

```yaml
metadata:
  labels:
    enable_kyverno: "true"              # Install Kyverno controller
    enable_kyverno_policies: "true"     # Deploy policies
```

---

## Customizing Kyverno Policies

Kyverno policy Helm values are customized from YAML files under `config/kyverno_policies/` (note the **underscore** in the directory name). In a typical setup, that directory lives in your **workloads repository**—the Git repo and path referenced by the cluster’s tenant settings (`tenant_repository` / `tenant_path`, for example `release/standalone-aws`). The platform ships defaults in this repository under `config/kyverno_policies/`; your workloads repo can override them without forking the whole chart.

### Choosing which policies are enabled

To turn individual policies on or off (or change enforce vs audit), edit the `policies` map. Each key matches the Helm values in the `kyverno-policies` chart (see [Per-Policy Configuration](#per-policy-configuration) and the chart’s `values.yaml`).

Use two files in your workloads repo to scope changes:

| File | Purpose |
|------|---------|
| `config/kyverno_policies/all.yaml` | Defaults for **every** cluster that uses this tenant path—shared baseline. |
| `config/kyverno_policies/<cluster_name>.yaml` | Overrides for **one** cluster only. `<cluster_name>` is the cluster’s `cluster_name` field from its cluster definition (for example `dev`, `prod`, `production-east-1`). |

You only need to declare policies you want to change; those settings are merged over broader layers (see below). Set `enabled: false` to stop deploying a policy, or `enabled: true` to opt in (for example `restrictImageRegistries`).

**Example — global opt-outs in `all.yaml`:**

```yaml
# config/kyverno_policies/all.yaml
policies:
  denyNodeportService:
    enabled: false
  denyLatestImage:
    enabled: false
```

**Example — stricter enforcement on one cluster:**

```yaml
# config/kyverno_policies/prod.yaml
policies:
  denyLatestImage:
    enabled: true
    validationFailureAction: enforce
```

The `policies` map uses the same camelCase keys as the chart values, for example: `denyDefaultNamespace`, `denyEksResources`, `denyEmptyIngress`, `denyExternalSecrets`, `denyLatestImage`, `denyNoLabels`, `denyNoLimits`, `denyNoPodProbes`, `denyNoTrafficDistribution`, `denyNodeportService`, `mutateEcrCache`, `mutatePsaLabels`, `mutateTrafficDistribution`, and `restrictImageRegistries`. See the chart’s `values.yaml` for the authoritative list and defaults.

### Configuration resolution order (precedence)

Values are layered; **more specific files override the same keys** from less specific ones. From **highest** to **lowest** precedence:

1. **Cluster-specific (workloads repo)**: `config/kyverno_policies/<cluster_name>.yaml`
2. **Cloud-specific (workloads repo)**: `config/kyverno_policies/<cloud_vendor>.yaml`
3. **Global tenant (workloads repo)**: `config/kyverno_policies/all.yaml`
4. **Cloud-specific (platform repo)**: `config/kyverno_policies/<cloud_vendor>.yaml`
5. **Global platform defaults**: `config/kyverno_policies/all.yaml` in the platform repository

So your workloads repository always wins over platform defaults when both define the same setting.

### Global Configuration Options

All policies inherit configuration from the global settings:

```yaml
# config/kyverno_policies/all.yaml
globalExclusions:
  # These namespaces are always excluded (cannot be overridden)
  always:
    - kube-system
    - argocd
  
  # Additional namespaces to exclude globally
  # (merged across all policies)
  additional:
    - cert-manager
    - external-secrets
```

### Per-Policy Configuration

Each policy can be individually enabled/disabled and configured:

```yaml
# config/kyverno_policies/all.yaml
policies:
  denyLatestImage:
    enabled: true
    validationFailureAction: enforce  # enforce | audit

  denyNoLimits:
    enabled: true
    validationFailureAction: enforce

  denyDefaultNamespace:
    enabled: false  # Disable for this environment
```

### Example 1: Audit Mode by Environment

Start with audit mode in development, enforce in production:

```yaml
# config/kyverno_policies/dev.yaml
policies:
  denyLatestImage:
    validationFailureAction: audit    # Test first
  denyNoLimits:
    validationFailureAction: audit

# config/kyverno_policies/prod.yaml
policies:
  denyLatestImage:
    validationFailureAction: enforce  # Enforce in prod
  denyNoLimits:
    validationFailureAction: enforce
```

### Example 2: Cloud-Specific Defaults

Enable AWS-specific policies in AWS environments:

```yaml
# config/kyverno_policies/aws.yaml
policies:
  denyEksResources:
    enabled: true
    validationFailureAction: enforce
```

### Example 3: Restrict Image Registries

Configure which container registries are allowed. The registry restriction policy supports two modes.

#### Simple Mode (Single Registry List)

```yaml
# config/kyverno_policies/all.yaml
policies:
  restrictImageRegistries:
    enabled: true
    useComplexConfig: false
    validationFailureAction: audit
    allowedRegistries:
      - gcr.io
      - docker.io
      - quay.io
```

#### Complex Mode (Per-Registry Namespace Rules)

```yaml
# config/kyverno_policies/prod.yaml
policies:
  restrictImageRegistries:
    enabled: true
    useComplexConfig: true
    validationFailureAction: enforce
    registries:
      # Only images from ECR allowed in prod/staging
      - name: ecr.aws
        allowedNamespaces:
          - prod
          - staging
      
      # Only images from GCR allowed in prod
      - name: gcr.io
        allowedNamespaces:
          - prod
      
      # Docker Hub images allowed everywhere except global exclusions
      - name: docker.io
        allowedNamespaces: []  # Empty = all except exclusions
```

### Example 4: Cluster-Specific Customization

Override settings for a specific cluster:

```yaml
# config/kyverno_policies/production-east-1.yaml
globalExclusions:
  additional:
    - cert-manager
    - external-secrets
    - monitoring

policies:
  denyLatestImage:
    validationFailureAction: enforce
  
  denyNoLabels:
    validationFailureAction: enforce
  
  restrictImageRegistries:
    enabled: true
    useComplexConfig: true
    validationFailureAction: enforce
    registries:
      - name: ecr.aws
        allowedNamespaces:
          - prod
          - staging
          - system
```

### Example 5: Disable Specific Policies

Some policies may conflict with your workloads. Disable them as needed:

```yaml
# config/kyverno_policies/dev.yaml
policies:
  # Allow NodePort in development
  denyNodeportService:
    enabled: false
  
  # Allow latest images for development
  denyLatestImage:
    enabled: false
```

### Example 6: Multi-Environment Configuration

Structure your config directory for multiple environments. File names such as `dev.yaml` and `prod-east-1.yaml` must match each cluster’s `cluster_name` when you want per-cluster overrides.

```
config/kyverno_policies/
├── all.yaml              # Global defaults for this tenant path
├── aws.yaml              # AWS cloud_vendor overrides
├── dev.yaml              # cluster_name dev
├── staging.yaml          # cluster_name staging
├── prod.yaml             # cluster_name prod
├── prod-east-1.yaml      # cluster_name prod-east-1
└── prod-west-2.yaml      # cluster_name prod-west-2
```

---

## Namespace Exclusion Precedence

Namespaces are excluded in this order:

1. **Always excluded** (hardcoded, cannot override):
   - `kube-system`
   - `argocd`

2. **Global additional exclusions**: `globalExclusions.additional`
   - Applied to all policies

3. **Per-policy exclusions**: `policies.<name>.excludeNamespaces`
   - Applied only to that specific policy

### Example: Complex Exclusion Strategy

```yaml
globalExclusions:
  additional:
    - cert-manager
    - external-secrets

policies:
  denyLatestImage:
    excludeNamespaces:
      - development-tools

  restrictImageRegistries:
    excludeNamespaces:
      - image-builder
```

Result: The following namespaces are excluded from all policies:
- `kube-system` (always)
- `argocd` (always)
- `cert-manager` (global)
- `external-secrets` (global)

Additional exclusions by policy:
- `deny-latest-image`: Also excludes `development-tools`
- `restrict-image-registries`: Also excludes `image-builder`

---

## Validation

Validate your Kyverno policy configuration before deployment:

```bash
# Run full validation including tests
bash scripts/validate-kyverno.sh

# Generate policy documentation
bash scripts/generate-policies.sh > docs/policies.md
```
---