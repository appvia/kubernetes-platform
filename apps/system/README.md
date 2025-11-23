# System ApplicationSets

This directory contains ArgoCD ApplicationSets that automatically generate and manage ArgoCD Applications for system-level platform components. These ApplicationSets use a combination of Git file generators and cluster selectors to dynamically create Applications based on configuration files in the platform repository.

## Overview

The ApplicationSets in this directory follow a common pattern:

1. **Matrix Generators**: Combine Git file discovery with cluster selection
2. **RollingSync Strategy**: Control deployment ordering using phase labels
3. **Go Templates**: Use Go templating for flexible Application generation
4. **Template Patches**: Apply dynamic patches using context-aware value extraction

For more information on ApplicationSets, see the [ArgoCD ApplicationSet documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/).

## ApplicationSets

### system-helm

The `system-helm` ApplicationSet manages Helm chart deployments for platform components.

**Purpose**: Automatically discovers and deploys Helm charts defined in the platform repository's `addons/helm/` directory.

**Key Features**:

- Discovers Helm charts from Git repository paths
- Filters charts based on cluster labels and feature flags
- Supports multi-source configurations with tenant and platform repositories
- Dynamic value file resolution based on cluster and cloud vendor

**Generator Configuration**:

- **Git Generator**: Scans for Helm chart definitions in:
  - `addons/helm/cloud/**/*.yaml`
  - `addons/helm/*.yaml`
- **Cluster Generator**: Matches clusters with:
  - `environment` label exists
  - `enable_{{ .feature }}` label equals `"true"`

**Sync Wave**: `1` (deployed early in the sync process)

**Documentation References**:

- [ApplicationSet Git Generator](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Generators-Git/)
- [ApplicationSet Cluster Generator](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Generators-Cluster/)
- [ApplicationSet Matrix Generator](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Generators-Matrix/)

### system-kustomize

The `system-kustomize` ApplicationSet manages Kustomize-based deployments for platform components.

**Purpose**: Automatically discovers and deploys Kustomize applications defined in the platform repository's `addons/kustomize/` directory.

**Key Features**:

- Discovers Kustomize applications from Git repository paths
- Filters applications based on cluster labels and feature flags
- Supports external repositories for Kustomize overlays
- Dynamic patch generation using JSON path extraction

**Generator Configuration**:

- **Git Generator**: Scans for Kustomize definitions in:
  - `addons/kustomize/CLOUD_VENDOR/**/kustomize.yaml`
  - `addons/kustomize/oss/**/kustomize.yaml`
- **Cluster Generator**: Matches clusters with:
  - `environment` label exists
  - `enable_{{ .kustomize.feature }}` label equals `"true"`

**Sync Wave**: `5` (deployed after Helm charts)

**Documentation References**:

- [ApplicationSet Git Generator](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Generators-Git/)
- [ApplicationSet Cluster Generator](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Generators-Cluster/)
- [ApplicationSet Matrix Generator](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Generators-Matrix/)

## RollingSync Strategy

Both ApplicationSets use a `RollingSync` strategy to control the order of Application creation and synchronization. This ensures that Applications are deployed in phases:

1. **Primary Phase**: Applications with `phase: primary` label
2. **Secondary Phase**: Applications with `phase: secondary` label
3. **Remaining Applications**: All other Applications (without primary or secondary phase)

This phased approach allows for dependencies to be resolved in the correct order. For example, core infrastructure components can be deployed before dependent services.

**Documentation References**:

- [ApplicationSet RollingSync Strategy](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Application-Set-Controller/#rollingsync-strategy)

## Templating System

The ApplicationSets use Go templates for generating Application manifests. The templating system provides access to context data from both the Git generator (chart/kustomize definitions) and the cluster generator (cluster metadata).

### Template Context

The template context (`.`) contains merged data from:

- **Git Generator**: Data extracted from YAML files in the repository (e.g., `feature`, `version`, `repository`, `namespace`)
- **Cluster Generator**: Cluster metadata (e.g., `server`, `metadata.labels.cluster_name`, `metadata.labels.cloud_vendor`)

### Template Functions

The templates use several helper functions:

- `normalize`: Normalizes strings for use in Kubernetes resource names
- `default`: Provides default values when fields are missing
- `dig`: Extracts nested values from the context (see Template Patches section)
- `toJson` / `fromJson`: Converts between JSON and Go data structures
- `splitList`: Splits strings into lists
- `trimPrefix`: Removes prefixes from strings
- `printf`: Formats strings

**Documentation References**:

- [ArgoCD Go Templates](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Go-Template/)
- [Go Template Functions](https://pkg.go.dev/text/template#hdr-Functions)

## Template Patches

The most complex part of the templating system is the `templatePatch` section, which dynamically modifies the Application spec based on context data. This section uses advanced templating techniques to extract and inject values.

### How Template Patches Work

Template patches are applied **after** the base template, allowing for dynamic modification of the Application specification. The patch uses Go templates with access to the full context.

### Context Preservation

Both ApplicationSets start their template patches by preserving the context:

```yaml
{{- $context := toJson . | fromJson }}
```

This creates a copy of the entire context that can be safely manipulated without affecting the original template context. This is necessary because the `dig` function requires a reference to the context object.

### Value Extraction with `dig`

The `dig` function is used to safely extract nested values from the context using dot-notation paths. It's similar to JSONPath but works with Go data structures.

**Syntax**: `dig path1 path2 path3 ... default`

The function traverses the context object using the provided path segments. If any part of the path doesn't exist, it returns the default value.

#### Example: Helm Parameters

In `system-helm.yaml`, parameters are extracted from the context:

```yaml
{{- $params := splitList "." (trimPrefix "." $param.value) }}
{{- $value := default $param.default "" }}
{{- if eq (len $params) 1 }}
{{- $value = dig (index $params 0) "" $context }}
{{- else if eq (len $params) 2 }}
{{- $value = dig (index $params 0) (index $params 1) "" $context }}
{{- else if eq (len $params) 3 }}
{{- $value = dig (index $params 0) (index $params 1) (index $params 2) "" $context }}
{{- else if eq (len $params) 4 }}
{{- $value = dig (index $params 0) (index $params 1) (index $params 2) (index $params 3) "" $context }}
{{- end }}
```

**How it works**:

1. The parameter value is a dot-notation path (e.g., `.metadata.labels.cluster_name`)
2. The path is split into segments (e.g., `["metadata", "labels", "cluster_name"]`)
3. Based on the number of segments, `dig` is called with the appropriate number of arguments
4. The extracted value is used, or the default if the path doesn't exist

**Example paths**:

- `.metadata.labels.cluster_name` → `dig "metadata" "labels" "cluster_name" "" $context`
- `.server` → `dig "server" "" $context`
- `.kustomize.feature` → `dig "kustomize" "feature" "" $context`

#### Example: Kustomize Patches

In `system-kustomize.yaml`, patches use similar logic to extract values for JSON patch operations:

```yaml
{{- $params := splitList "." $patch.key }}
{{- $value := $patch.default }}
{{- if eq (len $params) 1 }}
{{- $value = dig (index $params 0) "" $context }}
{{- else if eq (len $params) 2 }}
{{- $value = dig (index $params 0) (index $params 1) "" $context }}
{{- else if eq (len $params) 3 }}
{{- $value = dig (index $params 0) (index $params 1) (index $params 2) "" $context }}
{{- else if eq (len $params) 4 }}
{{- $value = dig (index $params 0) (index $params 1) (index $params 2) (index $params 3) "" $context }}
{{- end }}
```

The extracted value can then be used in JSON patch operations to modify Kubernetes resources.

### Multi-Source Configuration (Helm)

The `system-helm` ApplicationSet supports multiple repository sources:

1. **Chart Repository**: The Helm chart repository (from `.repository`)
2. **Values Repository**: Platform repository containing default values (ref: `values`)
3. **Tenant Repository**: Tenant-specific repository containing overrides (ref: `tenant`)

Value files are resolved in order of precedence (most specific to least specific):

1. `$tenant/{{ tenant_path }}/config/{{ feature }}/{{ cluster_name }}.yaml`
2. `$tenant/{{ tenant_path }}/config/{{ feature }}/{{ cloud_vendor }}.yaml`
3. `$tenant/{{ tenant_path }}/config/{{ feature }}/all.yaml`
4. `$values/config/{{ feature }}/{{ cloud_vendor }}.yaml`
5. `$values/config/{{ feature }}/all.yaml`

This allows for:

- Cluster-specific overrides
- Cloud vendor-specific configurations
- Global defaults

**Documentation References**:

- [ApplicationSet Template Patches](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Application-Set-Controller/#template-patches)
- [ArgoCD Multi-Source Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)

### Dynamic Patch Generation (Kustomize)

The `system-kustomize` ApplicationSet supports dynamic JSON patches that can modify Kubernetes resources based on context values.

**Patch Structure**:

```yaml
patches:
  - target:
      kind: Deployment
      name: my-app
    patch:
      - op: replace
        path: /spec/replicas
        value: 3
```

The `value` field in patches can be dynamically extracted from the context using the `dig` function, allowing patches to be parameterized based on cluster metadata, feature flags, or other context data.

**Documentation References**:

- [Kustomize Patches](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/)
- [JSON Patch RFC 6902](https://tools.ietf.org/html/rfc6902)

## Common Patterns

### Feature Flag Pattern

Both ApplicationSets use feature flags to enable/disable deployments:

- Label: `enable_{{ .feature }}` or `enable_{{ .kustomize.feature }}`
- Value: `"true"` to enable

This allows selective deployment of features per cluster.

### Namespace Resolution

Namespaces are resolved from the chart/kustomize definition:

- Helm: Uses `.namespace` from the chart definition
- Kustomize: Uses `.namespace.name` from the kustomize definition

### Sync Wave Control

Applications can control their sync wave using:

- Annotation: `argocd.argoproj.io/sync-wave`
- Default: `"10"` for Helm, `"15"` for Kustomize
- Can be overridden in chart/kustomize definitions

**Documentation References**:

- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

## Best Practices

1. **Feature Flags**: Always use feature flags (`enable_{{ feature }}`) to control deployments
2. **Sync Waves**: Use appropriate sync waves to ensure dependencies are met
3. **Phase Labels**: Use `phase: primary` or `phase: secondary` for critical components
4. **Value Files**: Follow the value file hierarchy for Helm charts
5. **Context Paths**: Use dot-notation paths consistently in parameter definitions
6. **Default Values**: Always provide default values for `dig` operations

## Troubleshooting

### Applications Not Created

- Check that feature flags are set: `enable_{{ feature }}: "true"`
- Verify cluster labels match selector requirements
- Ensure Git generator paths match file locations
- Check ApplicationSet controller logs

### Template Errors

- Verify Go template syntax
- Check that context paths exist in the merged data
- Ensure `dig` function paths match the context structure
- Validate JSON patch syntax for Kustomize patches

### Sync Issues

- Check sync wave ordering
- Verify phase labels for RollingSync
- Review sync policy settings
- Check Application sync status in ArgoCD UI

**Documentation References**:

- [ApplicationSet Troubleshooting](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/Troubleshooting/)
