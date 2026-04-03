# Validate Schema Github Action

A composite GitHub Action that validates cluster definition and workload YAML files against the platform JSON schemas using [`check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema).

## Inputs

| Input           | Required | Default                      | Description                                                                        |
| --------------- | -------- | ---------------------------- | ---------------------------------------------------------------------------------- |
| `version`       | No       | `main`                       | Git ref (branch, tag, or commit) of the platform repository to fetch schemas from. |
| `clusters`      | No       | _(empty)_                    | Newline-separated list of paths to cluster definition YAML files or directories.   |
| `workloads`     | No       | _(empty)_                    | Newline-separated list of paths to workload/application YAML files or directories. |
| `exclude-dirs`  | No       | _(empty)_                    | Newline-separated list of directory names to skip during recursive discovery.      |
| `exclude-files` | No       | _(empty)_                    | Newline-separated list of file names to skip during recursive discovery.           |
| `schema_repo`   | No       | `appvia/kubernetes-platform` | Owner/repo of the platform repository containing the schemas.                      |

At least one of `clusters` or `workloads` must be provided, otherwise the action does nothing.

## What gets validated

| Input       | Schema used                 | Expected YAML shape                                                                 |
| ----------- | --------------------------- | ----------------------------------------------------------------------------------- |
| `clusters`  | `schemas/clusters.json`     | Cluster definitions with `cluster_name`, `cloud_vendor`, `environment`, `labels`, … |
| `workloads` | `schemas/applications.json` | Tenant application definitions with `helm` and/or `kustomize` blocks.               |

## Usage

### Minimal — validate everything in a directory

```yaml
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate cluster and workload definitions
        uses: appvia/kubernetes-platform/.github/actions/validate-schemas@main
        with:
          clusters: clusters/
          workloads: workloads/
```

### Pin to a specific platform release

```yaml
- uses: appvia/kubernetes-platform/.github/actions/validate-schemas@v1.2.0
  with:
    clusters: release/standalone/clusters/
    workloads: release/standalone/workloads/
```

### Use a self-hosted or forked platform repository

```yaml
- uses: my-org/kubernetes-platform/.github/actions/validate-schemas@main
  with:
    schema_repo: my-org/kubernetes-platform
    clusters: environments/prod/
```

### Validate individual files

```yaml
- uses: appvia/kubernetes-platform/.github/actions/validate-schemas@main
  with:
    clusters: |
      clusters/dev.yaml
      clusters/prod.yaml
    workloads: workloads/my-app.yaml
```

## What the action does

1. Installs `check-jsonschema` via `pip`.
2. Downloads the relevant schema file(s) from GitHub raw content at the specified `version`.
3. Recursively finds every `.yaml` / `.yml` file under each provided directory (or validates individual files).
4. Runs `check-jsonschema --schemafile` against each file.
5. Collects all failures and prints a summary before exiting with code 1 if any file is invalid.
