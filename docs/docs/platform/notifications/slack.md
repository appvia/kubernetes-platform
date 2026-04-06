# Slack Notifications

This guide walks you through setting up Slack as your ArgoCD notification service.

## Prerequisites

- ArgoCD is installed on your cluster (typically with `enable_argocd: "true"` in your cluster definition)
- External Secrets Operator is installed (typically with `enable_external_secrets: "true"`)
- You have a Slack workspace where you can create applications
- You have permissions to store secrets in your cloud provider's secrets manager

## Step 1: Create a Slack OAuth Token

### In Your Slack Workspace

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **"Create New App"** → **"From scratch"**
3. Name your app (e.g., "ArgoCD Notifications")
4. Select your workspace and click **"Create App"**
5. Go to **"OAuth & Permissions"** in the left sidebar
6. Under **"Scopes"**, add the following bot token scopes:
   - `chat:write` - Send messages
   - `chat:write.public` - Post to public channels
7. Under **"OAuth Tokens for Your Workspace"**, click **"Install to Workspace"**
8. Review the permissions and click **"Allow"**
9. Copy the **"Bot User OAuth Token"** (starts with `xoxb-`)

**Important:** Keep this OAuth token secret. Anyone with this token can post messages to your Slack workspace within the scope of the permissions granted.

## Step 2: Store OAuth Token in Secrets Manager

Store the OAuth token in your cloud provider's secrets manager following the global secrets path.

### AWS Secrets Manager

```bash
# Create the secret with the OAuth token
# Format: /CLUSTER_NAME/global/argocd-slack-token
aws secretsmanager create-secret \
  --name /my-cluster/global/argocd-slack-token \
  --secret-string '{"slack-token": "xoxb-YOUR_BOT_TOKEN"}'
```

Alternatively, use the AWS Console:

1. Go to **AWS Secrets Manager**
2. Click **"Store a new secret"**
3. Choose **"Other type of secret"**
4. Configure as follows:
   - **Key/value pairs:**
     - Key: `slack-token`
     - Value: (paste your OAuth bot token starting with `xoxb-`)
5. Click **"Next"**
6. **Secret name:** `/my-cluster/global/argocd-slack-token`
7. Click **"Store"**

### Azure Key Vault

```bash
# Create the secret in Azure Key Vault
az keyvault secret set \
  --vault-name my-keyvault \
  --name my-cluster-global-argocd-slack-token \
  --value '{"slack-token": "xoxb-YOUR_BOT_TOKEN"}'
```

## Step 3: Enable ArgoCD Notifications in Your Cluster Definition

Edit your cluster definition in your tenant repository:

```yaml
# clusters/my-cluster.yaml
apiVersion: v1
kind: Cluster
metadata:
  name: my-cluster
  labels:
    enable_argocd: "true"
    enable_external_secrets: "true"
    enable_argocd_notifications: "true" # Enable notifications
  annotations:
    # Secret path to the Slack OAuth token in Secrets Manager
    argocd_notifications_secret_name: "my-cluster/global/argocd-slack-token"
spec:
  # ... rest of cluster definition
```

## Step 4: Configure Slack Service in Tenant Repository

Create notification configuration in your tenant repository:

```yaml
# config/argocd_notifications/all.yaml
externalSecret:
  secretName: "my-cluster/global/argocd-slack-token"
  key: "slack-token"
  namespace: argocd

notifications:
  enabled: true

  slack:
    serviceName: slack
    channel: "#argocd-notifications" # Can be overridden per app
    username: "ArgoCD"
    iconEmoji: ":rocket:"

  triggers:
    - name: on-deployed
      enabled: true
      when: app.status.operationState.phase in ['Succeeded'] and app.status.operationState.finishedAt != ''
      oncePer: app.status.operationState.finishedAt
      template: app-deployed

    - name: on-health-degraded
      enabled: true
      when: app.status.health.status == 'Degraded'
      oncePer: app.status.health.status
      template: app-health-degraded

    - name: on-sync-failed
      enabled: true
      when: app.status.operationState.phase in ['Error', 'Failed']
      oncePer: app.status.operationState.finishedAt
      template: app-sync-failed
```

### Cluster-Specific Overrides

For cluster-specific configuration, create:

```yaml
# config/argocd_notifications/my-cluster.yaml
externalSecret:
  secretName: "my-cluster/global/argocd-slack-token"
  key: "slack-token"

notifications:
  slack:
    channel: "#my-cluster-deployments" # Different channel for this cluster
```

## Step 5: Enable Notifications on Your Applications

Add annotations to your Application resources to subscribe to notification triggers:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  annotations:
    # Subscribe to on-deployed trigger for the default channel
    notifications.argoproj.io/subscribe.on-deployed.slack: "true"

    # Subscribe to specific channels per trigger
    notifications.argoproj.io/subscribe.on-deployed.slack: "#deployments"
    notifications.argoproj.io/subscribe.on-sync-failed.slack: "#alerts"
    notifications.argoproj.io/subscribe.on-health-degraded.slack: "#alerts"
spec:
  # ... rest of application definition
```

Annotation format: `notifications.argoproj.io/subscribe.<trigger>.<service>: "<channel>"`

- `<trigger>`: `on-deployed`, `on-sync-failed`, `on-health-degraded`, or custom trigger name
- `<service>`: `slack` (for Slack service)
- `<channel>`: Slack channel name or `true` to use default channel from config

## Step 6: Commit and Sync

Commit your changes to your tenant repository. The platform will:

1. Detect the `enable_argocd_notifications: "true"` label in your cluster definition
2. Deploy the ArgoCD Notifications chart
3. Create an ExternalSecret to fetch the webhook URL from Secrets Manager
4. Create the ConfigMap with notification triggers and templates
5. Configure ArgoCD to send notifications to Slack

## Notification Examples

### Successful Deployment Notification

```
✔ Application my-app deployment is healthy.
Application details: https://argocd.example.com/applications/my-app

Sync Status: Synced
Repository: https://github.com/my-org/my-repo
```

### Health Degraded Notification

```
⚠️ Application my-app health status is Degraded
Application details: https://argocd.example.com/applications/my-app

Health Status: Degraded
Repository: https://github.com/my-org/my-repo
```

### Sync Failed Notification

```
❌ Application my-app sync is Failed.
Application details: https://argocd.example.com/applications/my-app

Sync Status: Failed
Repository: https://github.com/my-org/my-repo
```

## Troubleshooting

### Notifications Not Sending

1. **Check the ExternalSecret is synced:**

   ```bash
   kubectl get externalsecret -n argocd
   kubectl describe externalsecret argocd-notifications-secret -n argocd
   ```

2. **Verify the Secret was created:**

   ```bash
   kubectl get secret argocd-notifications-secret -n argocd
   kubectl get secret argocd-notifications-secret -n argocd -o jsonpath='{.data.slack-token}' | base64 -d
   ```

3. **Check the ConfigMap:**

   ```bash
   kubectl get configmap argocd-notifications-cm -n argocd
   ```

4. **Review ArgoCD Notifications logs:**

   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications -f
   ```

5. **Verify Application annotations:**
   ```bash
   kubectl get application my-app -n argocd -o yaml
   ```

### Invalid OAuth Token

If you see errors like "Invalid token" or "Invalid Slack token" in ArgoCD Notifications logs:

1. Verify the OAuth token in Secrets Manager is correct and starts with `xoxb-`
2. Ensure the secret path in `argocd_notifications_secret_name` annotation matches the stored secret
3. Verify the key name in `externalSecret.key` matches the JSON key in the secret (`slack-token`)
4. Verify the OAuth token has the required scopes: `chat:write` and `chat:write.public`

### Secret Not Syncing

If the ExternalSecret is not syncing:

1. Verify External Secrets Operator is installed and running
2. Check that the ClusterSecretStore is configured correctly
3. Ensure IAM/RBAC permissions allow reading from your secrets manager
4. Review External Secrets Operator logs:
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f
   ```

## Customization

### Custom Message Templates

Override the default message templates in your `config/argocd_notifications/all.yaml`:

```yaml
notifications:
  templates:
    appDeployed: |
      🎉 Deployment Success!
      App: {{.app.metadata.name}}
      Status: {{.app.status.sync.status}}
      Details: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}
```

### Additional Triggers

Add custom triggers based on application state:

```yaml
notifications:
  triggers:
    - name: on-sync-running
      enabled: true
      when: app.status.operationState.phase in ['Running']
      oncePer: app.metadata.name
      template: app-sync-running
```

### Multiple Notification Services

The ArgoCD Notifications framework supports multiple services. Configure additional services in your `config/argocd_notifications/all.yaml`.

See [ArgoCD Notifications Services Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/services/) for all available services.

## Reference

- [ArgoCD Notifications Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks)
- [External Secrets Operator](https://external-secrets.io/)
- [Platform Secrets Policy](../platform/secrets.md)
