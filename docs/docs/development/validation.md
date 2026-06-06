# Validating Your Build

## Overview

Before creating a pull request, you should validate that your changes don't break the platform configuration or the cluster deployment. The platform provides several validation tools to help you catch issues early.

This guide walks through the validation steps, from quick configuration checks to full end-to-end cluster testing.

## Quick Validation

The fastest way to validate your changes is to run the configuration validation checks:

```shell
make test
```

This executes:

- **Configuration validation** — Validates YAML schemas, cluster definitions, and workload configurations
- **Linting** — Checks YAML syntax and formatting
- **Template testing** — Validates ApplicationSet templatePatch rendering

These checks catch most common configuration errors and run in under a minute.

### What Gets Validated

| Check | Command | Purpose |
|-------|---------|---------|
| YAML Syntax | `yamllint .` | Checks YAML formatting and structure |
| Helm Charts | `scripts/validate-helm-charts.sh` | Validates Helm chart definitions |
| Kustomize | `scripts/validate-kustomize.sh` | Validates Kustomize overlays |
| Cluster Definitions | `scripts/validate-cluster-definitions.sh` | Validates cluster configuration schemas |
| Kyverno Policies | `scripts/validate-kyverno.sh` | Validates Kyverno policy definitions |
| Schema Validation | `scripts/validate-schema.sh` | Validates cluster and workload schemas |
| Addon Schemas | `scripts/validate-addon-schemas.sh` | Validates addon configurations |
| Template Rendering | `cd tests/templates && go test ./...` | Tests ApplicationSet template patches |

If any validation fails, fix the errors and run `make test` again.

## Full End-to-End Validation

For changes that affect cluster behavior, add-ons, workloads, or ArgoCD applications, run the full end-to-end test suite. This validates that the platform provisions correctly and all components function as expected.

### Local Validation (Kind)

To validate locally with a Kind cluster:

```shell
# Provision a Kind cluster and run e2e tests
make standalone
```

This command:

1. Provisions a local Kubernetes cluster using Kind
2. Installs the platform components
3. Runs the full e2e test suite to validate the cluster

The process takes approximately 10-15 minutes. Once complete, you can access the cluster:

```shell
kubectl cluster-info
kubectl get ns
kubectl -n argocd get applications
```

### Remote Validation (AWS)

For testing features that require cloud provider resources (IAM, load balancers, storage classes, etc.), provision a cluster in AWS:

```shell
# Set up AWS credentials first
export AWS_PROFILE=your-profile

# Provision an EKS cluster and the platform
make standalone-aws
```

See [Provision a Standalone Cluster](standalone.md) for detailed AWS setup instructions.

To clean up:

```shell
make destroy-standalone-aws
```

## Understanding the E2E Test Structure

The e2e test suite uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) to validate cluster deployment and behavior.

### Test Organization

Tests are organized by concern and location:

```
tests/e2e/integration/
├── setup.sh                    # Bootstrap tests (cluster, argocd, namespaces)
├── common/                     # Tests that run on all cluster types
│   ├── bootstrap.sh           # ArgoCD and cluster bootstrap
│   ├── platform.sh            # Platform core components
│   ├── argocd.sh              # ArgoCD integration
│   ├── applicationsets.sh      # ApplicationSet functionality
│   └── cert-manager.sh        # Certificate management
├── standalone/                 # Standalone cluster-specific tests
│   ├── registration.sh        # Cluster registration
│   ├── applicationsets.sh      # Standalone ApplicationSets
│   ├── tenant-namespace.sh    # Tenant namespace setup
│   ├── tenant-helm-apps.sh    # Helm-based tenant applications
│   ├── tenant-kustomize-apps.sh # Kustomize-based tenant applications
│   ├── cilium.sh              # Cilium networking
│   ├── kyverno.sh             # Kyverno policy engine
│   ├── kyverno-policies.sh    # Custom Kyverno policies
│   ├── cert-manager.sh        # Cert-manager validation
│   └── kind/                  # Kind-specific tests
│       ├── storage-classes.sh # Storage class validation
│       └── cilium.sh          # Kind-specific Cilium tests
└── hub/                        # Hub cluster-specific tests
    └── Similar structure to standalone
```

### Test Format

Each test file is a BATS test suite. Tests follow a consistent pattern:

```bash
@test "Description of what is being tested" {
  # Run kubectl commands to validate cluster state
  kubectl "get namespace argocd"
}
```

Tests use helper functions from `tests/e2e/lib/helper.bash`:

| Function | Purpose |
|----------|---------|
| `kubectl` | Runs kubectl commands with automatic retries (up to 50 attempts) |
| `kubectl_argocd` | Runs kubectl commands in the argocd namespace with retries |
| `retry` | Retries a command N times with 5-second delays |
| `runit` | Convenience wrapper for 50 retries |

The retry mechanism handles temporary timing issues during cluster startup.

## Debugging Test Failures

When tests fail, the output shows the failing command and the error message. Here's how to debug:

### 1. Review the Test Output

The output shows:

- Which test failed
- The command that was executed
- The actual result or error

Example:

```
not ok 5 Ensure all the services are ready
   (from function `kubectl' in file tests/e2e/lib/helper.bash, line 64,
    in test file tests/e2e/integration/standalone/setup.sh, line 29)
     `kubectl "-n argocd wait --for=condition=Ready pods --all...`
   Output:
   error: timed out waiting for the condition
```

### 2. Check Cluster State Manually

Connect to your cluster and investigate:

```shell
# Check Pod status
kubectl -n argocd get pods

# Check Pod logs
kubectl -n argocd logs deployment/argocd-server

# Check ArgoCD applications
kubectl -n argocd get applications

# Check application sync status
kubectl -n argocd get application bootstrap -o yaml
```

### 3. Common Failure Patterns

| Failure | Likely Cause | Investigation |
|---------|--------------|-----------------|
| Setup tests fail immediately | Cluster provisioning issue | Check Kind/EKS provisioning output, cluster logs |
| Pod startup timeouts | Insufficient resources or image issues | Check `kubectl top nodes`, `kubectl describe pods`, image pull errors |
| ArgoCD application sync failures | Configuration or resource issues | Check `kubectl -n argocd logs <pod>`, application status |
| Resource creation failures | Schema validation or RBAC issues | Check resource definitions, cluster roles, CRDs |

### 4. Re-run Specific Tests

To run a single test file while debugging:

```shell
cd tests/e2e/integration
bats standalone/setup.sh
```

To run a specific test:

```shell
bats standalone/setup.sh -f "Ensure we have the argocd namespace"
```

### 5. Preserve Cluster State for Investigation

By default, the cluster is deleted after tests complete. To preserve it for investigation:

```shell
# Run the standalone provisioning without cleanup
make standalone
# The cluster stays running so you can investigate
kind get clusters
kubectl get nodes
```

To clean up when done:

```shell
make clean
```

## Pre-Pull Request Validation Checklist

Before creating a pull request, ensure:

- [ ] **Quick validation passes**: `make test` completes without errors
- [ ] **Code changes are committed**: All changes are staged and ready to commit
- [ ] **Branch is created**: You're on a feature branch, not main
- [ ] **E2E tests pass** (for behavior changes):
  - Local validation: `make standalone` passes all tests OR
  - Remote validation: `make standalone-aws` passes all tests
- [ ] **Manual validation** (if applicable):
  - Test the specific feature you changed
  - Verify related features still work
  - Check ArgoCD application syncs are healthy
- [ ] **Documentation is updated**: If you changed behavior, update relevant docs
- [ ] **Commit message is clear**: Use conventional commit format (feat:, fix:, docs:, etc.)

## When to Run Which Validation

| Scenario | Validation | Why |
|----------|-----------|-----|
| YAML/configuration changes | `make test` | Fast feedback on syntax and schema |
| Kustomize/Helm changes | `make test` | Validates template rendering |
| Addon configuration changes | `make standalone` | Ensures addon deploys correctly |
| Application behavior changes | `make standalone` | Validates cluster-wide behavior |
| Cloud-specific features | `make standalone-aws` | Tests cloud provider integration |
| Documentation-only changes | `make test` | Quick validation sufficient |
| New feature with cluster impact | `make standalone` + `make standalone-aws` | Validate on both platforms |

## Related Documentation

- [Local Development](local.md) — Set up your local development environment
- [Provision a Standalone Cluster](standalone.md) — Deploy to AWS for testing
- [Remote Development](overview.md) — Overview of remote development scenarios
