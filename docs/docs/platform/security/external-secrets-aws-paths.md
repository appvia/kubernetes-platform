# AWS External Secrets — Secrets Manager path convention

When the platform AWS addon installs a `ClusterSecretStore` (`addons/kustomize/aws/external_secrets/`), every workload namespace can talk to the same store. To keep tenants from pointing `ExternalSecret` objects at another team’s Secrets Manager names, the platform can enforce a **cluster-scoped path layout** with Kyverno (`deny-external-secrets`).

## Path layout

Use this hierarchy in **AWS Secrets Manager secret names** (the `remoteRef.key` / `dataFrom.extract.key` values):

| Scope | Prefix pattern | Who may reference it |
| ----- | -------------- | -------------------- |
| Cluster shared | `<clusterName>/global/SECRETS` + suffix | Any namespace |
| Namespace-owned | `<clusterName>/<namespace>/SECRETS` + suffix | Only that same Kubernetes namespace |

Examples for cluster `dev`:

- Allowed from any namespace: `dev/global/SECRETS/platform-ca-bundle`
- Allowed only from namespace `frontend`: `dev/frontend/SECRETS/api-token`
- Denied from namespace `frontend`: `dev/backend/test` or `dev/backend/SECRETS/db` (not under `dev/global/SECRETS…` and not under `dev/frontend/SECRETS…`)

The fixed segments `global` and `SECRETS` default names can be changed in Helm values (`policies.denyExternalSecrets.aws.globalSegment` and `secretsPrefix`).

## What enforces this

1. **Kyverno** — Rule `aws-secrets-manager-paths` on policy `deny-external-secrets` runs only when:

   - `policies.denyExternalSecrets.useAwsSecretsManagerPaths` is `true`, and  
   - `policies.denyExternalSecrets.aws.clusterName` is non-empty, and  
   - The `ExternalSecret` uses `spec.secretStoreRef.kind: ClusterSecretStore` and the configured store name (default `secrets-store`).

   Other stores (for example a namespace `SecretStore`) are not checked by this rule.

2. **Cluster name** — For AWS clusters, the platform ApplicationSet passes `policies.denyExternalSecrets.aws.clusterName` from the cluster definition label `cluster_name` (see `addons/helm/oss.yaml` under `kyverno_policies`).

3. **Platform defaults** — `config/kyverno_policies/aws.yaml` turns on `useAwsSecretsManagerPaths`. Non-AWS clouds keep [legacy behaviour](#legacy-non-aws-behaviour) unless you enable the AWS-style paths in values.

## Enabling and tuning

In your workloads repo, merge values under `config/kyverno_policies/` as described in [Kyverno policy configuration](kyverno.md#customizing-kyverno-policies). Relevant keys:

```yaml
policies:
  denyExternalSecrets:
    enabled: true
    validationFailureAction: enforce
    useAwsSecretsManagerPaths: true
    aws:
      clusterName: "" # Usually injected from cluster metadata by the platform
      clusterSecretStoreName: secrets-store
      globalSegment: global
      secretsPrefix: SECRETS
```

## IAM (defence in depth)

Kyverno only controls what users **declare** in Kubernetes. Mirror the same boundaries in **IAM** for the role used by External Secrets (IRSA): allow `secretsmanager:GetSecretValue` (and any other required actions) on ARNs whose name matches `cluster/global/SECRETS*` and `cluster/*/SECRETS*` for the appropriate namespaces, or scope with a permission boundary your org prefers. Exact IAM wiring depends on how you attach the controller role; keep policy and IAM aligned.

## Limitations

- The rule keys off `spec.secretStoreRef` only. If that field is omitted and each `data[]` entry uses `sourceRef.storeRef` instead, the AWS path check is skipped for that object; prefer a single top-level `secretStoreRef` when using the platform `ClusterSecretStore`.
- Validation applies to `spec.data[].remoteRef.key` and to `dataFrom[].extract.key`. Entries that use only `find`, `rewrite`, or generators are not covered by the key prefix checks; use a dedicated store or additional policies if those patterns must be locked down.
- Admission-time only (`background: false` for this policy); clusters must run the Kyverno webhook for enforcement.

## Legacy (non-AWS) behaviour

If AWS path mode is off or `clusterName` is empty, `deny-external-secrets` uses rule `namespace-prefix-keys`: each key must start with `<namespace>/`, which matches the previous namespace-prefix model for non-AWS setups.
