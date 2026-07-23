# AWS External Secrets — Secrets Manager path convention

When the platform AWS addon installs a `ClusterSecretStore` (`addons/kustomize/aws/external_secrets/`), every workload namespace can talk to the same store. To keep tenants from pointing `ExternalSecret` objects at another team’s Secrets Manager names, the platform can enforce a **cluster-scoped path layout** with Kyverno (`deny-external-secrets`).

## Path layout

Use this hierarchy in **AWS Secrets Manager secret names** (the `remoteRef.key` / `dataFrom.extract.key` values):

| Scope | Prefix pattern | Who may reference it |
| ----- | -------------- | -------------------- |
| Cluster shared | `eks/<clusterName>/global/` + secret name | Any namespace |
| Namespace-owned | `eks/<clusterName>/<namespace>/` + secret name | Only that same Kubernetes namespace |

Examples for cluster `dev`:

- Allowed from any namespace: `eks/dev/global/platform-ca-bundle`
- Allowed only from namespace `frontend`: `eks/dev/frontend/api-token`
- Denied from namespace `frontend`: `eks/dev/backend/db` (another namespace’s subtree) or `dev/frontend/api-token` (missing the `eks` root)

Every segment must be whole — the trailing `/` is the boundary, so namespace `front` cannot reach `eks/dev/frontend/…` and cluster `dev` cannot reach `eks/dev-staging/…`.

The segment names are configurable in Helm values under `policies.denyExternalSecrets.aws`:

| Value | Default | Effect |
| ----- | ------- | ------ |
| `rootPrefix` | `eks` | Leading segment before the cluster name. Set to `""` to start the path at `<clusterName>`. |
| `globalSegment` | `global` | Name of the cluster-shared namespace segment. |
| `secretsPrefix` | `""` | Optional marker segment after the namespace. Set to e.g. `SECRETS` to require `eks/<cluster>/<namespace>/SECRETS/…` and reserve the rest of the namespace subtree for non-secret data. |

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
      rootPrefix: eks
      globalSegment: global
      secretsPrefix: ""
```

## IAM (defence in depth)

Kyverno only controls what users **declare** in Kubernetes. Mirror the same boundaries in **IAM** for the role used by External Secrets. `terraform/main.tf` scopes the platform grants to the same hierarchy:

```hcl
external_secrets = {
  enable               = true
  ssm_parameter_arns   = ["arn:aws:ssm:${local.region}:${local.account_id}:parameter/eks/${local.cluster_name}/*"]
  secrets_manager_arns = ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:eks/${local.cluster_name}/*"]
}
```

That bounds the controller to one cluster’s subtree; Kyverno provides the per-namespace split inside it, since the controller role itself cannot distinguish which namespace an `ExternalSecret` came from. Secrets Manager appends a random six-character suffix to every ARN, so the trailing `*` is required. Keep the two in sync — if you change `rootPrefix`, change these ARNs too.

## Limitations

- The rule keys off `spec.secretStoreRef` only. If that field is omitted and each `data[]` entry uses `sourceRef.storeRef` instead, the AWS path check is skipped for that object; prefer a single top-level `secretStoreRef` when using the platform `ClusterSecretStore`.
- Validation applies to `spec.data[].remoteRef.key` and to `dataFrom[].extract.key`. Entries that use only `find`, `rewrite`, or generators are not covered by the key prefix checks; use a dedicated store or additional policies if those patterns must be locked down.
- Admission-time only (`background: false` for this policy); clusters must run the Kyverno webhook for enforcement.

## Legacy (non-AWS) behaviour

If AWS path mode is off or `clusterName` is empty, `deny-external-secrets` uses rule `namespace-prefix-keys`: each key must start with `<namespace>/`, which matches the previous namespace-prefix model for non-AWS setups.
