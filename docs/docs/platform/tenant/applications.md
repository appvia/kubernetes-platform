# :material-application-cog: Tenant Applications

!!! note "Note"

    Please refer to the [architectural overview](../../architecture/overview.md) for an understanding on tenant and platform repositories

Applications for tenants can be deployed using a GitOps approach directly from the tenant repository. The workloads folder contains two main directories:

- **workloads/applications/** - Contains standard application definitions that run under the tenant's ArgoCD project with regular permissions
- **workloads/system/** - Contains system-level application definitions that run under a privileged ArgoCD project with elevated permissions

By simply adding Helm charts or Kustomize configurations into the appropriate directory structure, applications can be:

- Easily deployed to the cluster
- Upgraded through GitOps workflows
- Promoted between environments in a controlled manner

This separation of applications and system components allows for proper access control while maintaining a simple deployment model.

## :material-application-array-outline: Helm Applications

You can deploy using a helm chart, by adding a `CLUSTER_NAME.yaml`.

1. Create a folder (by default this becomes the namespace)
2. Add a `CLUSTER_NAME.yaml` file

```yaml
helm:
  ## (Required) The Helm chart repository URL.
  repository: https://charts.example.com
  ## (Required) The version of the chart to use for the deployment.
  version: 0.1.0
  ## (Optional) The chart name or path within the repository.
  chart: my-chart
  ## (Optional) The path inside the repository to the chart.
  repository_path: ./charts
  ## (Required) The release name to use for the deployment.
  release_name: platform
  ## (Optional) A collection of additional parameters - note these can reference metadata
  ## from the selected cluster definition.
  parameters:
    - name: serviceAccount.annotations.test
      value: default_value
    # When referencing cluster metadata, the value MUST begin with a dot (.)
    # Supported metadata paths: .metadata.labels.*, .metadata.annotations.*, .server
    - name: serviceAccount.annotations.test2
      value: .metadata.labels.cloud_vendor
  ## (Optional) Inline Helm values as a string
  values: |
    key: value

## Sync Options
sync:
  # (Optional) The phase to use for the deployment, used to determine the order of the deployment.
  phase: primary|secondary
  # (Optional) The duration to use for the deployment.
  duration: 30s
  # (Optional) The max duration to use for the deployment.
  max_duration: 5m
```

### Helm Values Resolution

Helm values are resolved in the following order (first match wins):

1. `values/{{ .metadata.labels.cluster_name }}.yaml` - cluster-specific values
2. `values/{{ .metadata.labels.environment }}.yaml` - environment-specific values
3. `values/{{ .metadata.annotations.tenant }}.yaml` - tenant-specific values
4. `values/all.yaml` - default values for all deployments
5. Inline `helm.values` if provided

To use helm values:

1. Create a folder called `values` inside the folder created in step 1.
2. Add value files for different scopes (`all.yaml`, environment-specific like `dev.yaml`, tenant-specific, or cluster-specific values).

## :material-application-array-outline: Helm with Multiple Charts

Similar to the helm deployment, create a folder for your deployments. Taking the example of two charts, frontend and backend, you would create a folder called `frontend` and `backend`.

1. Create a folder called for the application, e.g. `myapp`
2. Create two folders inside the `myapp` folder, `frontend` and `backend`
3. Add a `CLUSTER_NAME.yaml` file to the `frontend` and `backend` folders.
4. Use the same format as the basic Helm example for each file.
5. Add a `values` folder to the `frontend` folder, and add value files as needed.
6. Add a `values` folder to the `backend` folder, and add value files as needed.

Example structure:

```
myapp/
  frontend/
    dev.yaml
    values/
      all.yaml
  backend/
    dev.yaml
    values/
      all.yaml
```

Each `CLUSTER_NAME.yaml` file follows the helm format shown in the Helm Applications section.

## :material-application-array-outline: Kustomize

You can deploy using kustomize, by adding a `CLUSTER_NAME.yaml`.

1. Create a folder (by default this becomes the namespace)
2. Add the `CLUSTER_NAME.yaml` file

```yaml
kustomize:
  # (Required) The path to the kustomize base.
  path: kustomize
  # (Optional) Override the namespace to use for the deployment.
  namespace: override-namespace
  # (Required) Details the revision to point; this is a revision within the repository and
  # is used to control a point in time of the manifests.
  revision: <GIT_SHA>
  # (Optional) Patches to apply to the deployment.
  patches:
    - target:
        kind: Deployment
        name: frontend
      patch:
        - op: replace
          path: /spec/template/spec/containers/0/image
          ## When referencing cluster metadata, the key MUST begin with a dot (.)
          ## Supported metadata paths: .metadata.labels.*, .metadata.annotations.*, .server
          key: .metadata.annotations.image
          ## This is the default value to use if the key is not found.
          default: nginx:1.21.3
        - op: replace
          path: /spec/template/spec/containers/0/version
          ## Keys referencing metadata must start with a dot
          key: .metadata.annotations.version
          default: "1.21.3"
          ## An optional prefix can be prepended to the resolved value
          ## If both are specified, final value = prefix + resolved_value
          prefix: v-
        - op: replace
          path: /spec/template/spec/containers/0/registry
          ## Literal values (without metadata lookup) should NOT start with a dot
          value: my-registry.example.com
          default: registry.example.com

  ## Optional labels applied to all resources
  commonLabels:
    app.kubernetes.io/managed-by: argocd

  ## Optional annotations applied to all resources
  commonAnnotations:
    argocd.argoproj.io/sync-options: Prune=false
```

Unlike Helm where versions are managed externally through chart repositories, Kustomize manifests are typically stored directly in your repository. While Kustomize overlays provide environment-specific customization, changes to shared base configurations could potentially affect all environments simultaneously.

To provide better control and safety, the `revision` field is used to pin Kustomize deployments to a specific Git commit or branch in the tenant repository. This allows you to:

- Make changes to manifests in the main branch without affecting production
- Control the rollout of changes across environments by updating revisions
- Roll back to previous versions by reverting to earlier commits
- Test changes in lower environments before promoting to production

**Example workflow:**

1. Develop and commit Kustomize changes to main branch
2. Test in dev environment by updating dev cluster's revision
3. Promote to staging/prod by updating their revisions after validation
4. Roll back if needed by reverting to previous commit SHA

## :material-application-array-outline: Kustomize with External Source

By default, Kustomize manifests are sourced from the tenant repository at the path you specify. However, you can also reference Kustomize configurations from external repositories for greater flexibility in managing deployment configurations and enabling independent versioning strategies.

To use an external Kustomize repository:

1. Create a folder for your application (this becomes the namespace by default)
2. Add the `CLUSTER_NAME.yaml` file with external repository configuration:

```yaml
kustomize:
  # (Required) The URL to the external kustomize repository
  repository: https://github.com/example/kustomize-configs.git
  # (Required) The path inside the repository to the kustomize base
  path: overlays/dev
  # (Required) The Git revision (can be a commit SHA, branch, or tag)
  # A common pattern is to use floating tags to represent environments (e.g., 'dev', 'staging', 'prod')
  revision: dev
```

When `repository` is specified, Kustomize manifests are pulled from that external repository. When `repository` is not specified, manifests are sourced from the tenant repository at the same path as the CLUSTER_NAME.yaml file.

## :material-application-array-outline: Combinational Deployment

You can combine both helm and kustomize deployments in a single file. This allows you to deploy applications that require both deployment methods.

1. Create a folder for your application, e.g. `myapp`
2. Add a `CLUSTER_NAME.yaml` file that contains both helm and kustomize configurations

```yaml
helm:
  ## (Required) The Helm chart repository URL.
  repository: https://charts.example.com
  ## (Required) The version of the chart to use for the deployment.
  version: 0.1.0
  ## (Optional) The chart name or path within the repository.
  chart: my-chart
  ## (Optional) The path inside the repository to the chart.
  repository_path: ./charts
  ## (Required) The release name to use for the deployment.
  release_name: platform

kustomize:
  # (Required) The path to the kustomize base.
  path: kustomize
  # (Optional) Override the namespace to use for the deployment.
  namespace: override-namespace
  # (Required) Git revision
  revision: git+sha
```
