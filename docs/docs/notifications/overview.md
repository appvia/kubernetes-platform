# ArgoCD Notifications

ArgoCD Notifications enable your applications to send event-driven notifications to various notification services (Slack, email, webhooks, etc.) when application synchronization, health status, or other events occur.

## Overview

The ArgoCD Notifications feature allows downstream teams to:

- **Configure notification services** - Set up Slack webhooks or other notification destinations
- **Define notification triggers** - Specify which events should trigger notifications (sync success, sync failure, health degraded, etc.)
- **Customize notification messages** - Define custom message templates for different event types
- **Enable per-application notifications** - Control notifications via Application resource annotations

## Architecture

```
┌─────────────────────────────────────┐
│  Application Resource               │
│  (with notification annotations)    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  ArgoCD Notification Controller     │
│  (reads triggers & templates)       │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  ConfigMap: argocd-notifications-cm │
│  (triggers, templates, services)    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  ExternalSecret                     │
│  (fetches webhook URLs from         │
│   Secrets Manager)                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Secret: argocd-notifications-secret│
│  (webhook tokens, credentials)      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Notification Services              │
│  (Slack, Email, Webhooks, etc.)     │
└─────────────────────────────────────┘
```

## How It Works

1. **Cluster Definition** - A downstream team enables notifications in their cluster definition:

```yaml
metadata:
  labels:
    enable_argocd_notifications: "true"
```

2. **Configuration** - The team provides configuration in their tenant repository:
   ```
   config/
   └── argocd_notifications/
       ├── all.yaml              # Global defaults
       └── <cluster_name>.yaml   # Cluster-specific overrides
   ```

Create a environment or cluster-specific configuration file that defines the name of the secrets, note this **MUST** live in the `CLUSTER_NAME/global/SECRET_NAME` namespace within AWS Secrets Manager.

```yaml
externalSecret:
  # The name of the secret in the secrets manager that contains OAuth token for Slack.
  # The should be within the path /CLUSTER_NAME/global/SECRET_NAME
  secretName: /dev/global/argocd-slack-webhook
```

3. **Secret Management** - The notification webhook URL is stored in the cloud provider's secrets manager (AWS Secrets Manager, Azure Key Vault, etc.) following the policy path:

```

/CLUSTER_NAME/global/argocd-slack-webhook

```

4. **ExternalSecret Bridge** - The ArgoCD Notifications chart creates an `ExternalSecret` that fetches the webhook URL from the secrets manager and syncs it to a Kubernetes Secret

5. **Application Annotations** - Applications opt-in to notifications via annotations:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: "#deployments"
```

## Secret Policy

Secrets follow the platform's two-level policy:

### Global Secrets

**Path:** `/CLUSTER_NAME/global/SECRETS`

- Accessible by all namespaces within the cluster
- Use for cluster-wide configuration (notification webhooks, global credentials)
- Example: `/my-cluster/global/argocd-slack-webhook`

### Namespace Secrets

**Path:** `/CLUSTER_NAME/NAMESPACE_NAME/SECRETS`

- Accessible only from the specified namespace
- Use for namespace-specific configuration
- Example: `/my-cluster/argocd/custom-webhook`
- Protected by Kyverno policies

## Available Notification Services

The platform supports multiple notification services via ArgoCD Notifications:

- **Slack** - Send notifications to Slack channels
- **Email** - Send email notifications
- **Webhooks** - Send HTTP POST requests to custom endpoints
- **Opsgenie** - Send notifications to Opsgenie
- **Grafana** - Send annotations to Grafana
- And more...

See the specific service documentation for configuration details.

## Notification Triggers

Default triggers provided by the platform:

| Trigger              | Condition                                                | Event                          |
| -------------------- | -------------------------------------------------------- | ------------------------------ |
| `on-deployed`        | `app.status.operationState.phase in ['Succeeded']`       | Application sync succeeded     |
| `on-health-degraded` | `app.status.health.status == 'Degraded'`                 | Application health is degraded |
| `on-sync-failed`     | `app.status.operationState.phase in ['Error', 'Failed']` | Application sync failed        |

Custom triggers can be defined in tenant-level configuration overrides.

## Next Steps

- [Configure Slack Notifications](slack.md) - Set up Slack as your notification service
- [ArgoCD Notifications Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) - Official ArgoCD documentation
- [External Secrets Operator](https://external-secrets.io/) - Learn more about ExternalSecret bridge
