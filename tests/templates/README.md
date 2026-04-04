# ApplicationSet template tests

This package exercises the `spec.templatePatch` Go templates used by platform ApplicationSets under `apps/`. Patch bodies are **generated** into `fixtures_test.go` from the live YAML. Representative merged-generator **JSON** parameters are **hand-maintained** as raw string constants in `template_test.go`.

## What is tested

For each of the six ApplicationSets that define `templatePatch`:

1. **Render** – Argo CD’s `applicationset/utils.Render.Replace` runs the embedded template with the JSON from `template_test.go` (same Sprig + `normalize` / `toJson` / `dig` behaviour as the controller), with `missingkey=error`.
2. **YAML** – The rendered string must be non-empty and parse as YAML into a non-empty document (typically a `spec:` fragment).

Assertions use **Ginkgo** / **Gomega** in `template_test.go` (`Context` / `When` / `It`).

## Run tests

From the repository root:

```bash
make test-templates
```

Or from this directory:

```bash
go test ./... -count=1
```

## Regenerate embedded patch strings

When you change `spec.templatePatch` in any of:

- `apps/system/system-helm.yaml`
- `apps/system/system-kustomize.yaml`
- `apps/tenant/apps-helm.yaml`
- `apps/tenant/apps-kustomize.yaml`
- `apps/tenant/system-helm.yaml`
- `apps/tenant/system-kustomize.yaml`

rebuild `fixtures_test.go` from the repo root (requires [`yq`](https://github.com/mikefarah/yq)):

```bash
make generate-template-fixtures
```

That runs `scripts/generate-template-fixtures.py`, which extracts each `spec.templatePatch` with `yq` and overwrites **only** the `patch*` constants in `embedded_fixtures_test.go`.

To change the **JSON** passed into templates (e.g. new keys required by a template change), edit the `params*` raw string constants at the top of `template_patch_test.go`. You do **not** need to run the generator for JSON-only edits.

## Files

| File                        | Role                                                                            |
| --------------------------- | ------------------------------------------------------------------------------- |
| `suite_test.go`             | Ginkgo entrypoint (`TestTemplates`).                                            |
| `template_patch_test.go`    | BDD specs, YAML validation helper, and **hand-edited** `params*` JSON fixtures. |
| `helpers_test.go`           | Render helper, `missingkey=error`, parameter defaults for small fixtures.       |
| `embedded_fixtures_test.go` | **Generated** `patch*` template strings only.                                   |
| `go.mod` / `go.sum`         | Go module (Argo CD `applicationset/utils`, Ginkgo, Gomega).                     |

## Dependencies

- **Go** – see `go` directive in `go.mod` (CI uses the same minor line as the workflow).
- **yq** – only needed for `make generate-template-fixtures`, not for `go test`.
