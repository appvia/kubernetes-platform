# Platform Addons

Each addon is enabled from the cluster definition using the feature flag label `enable_<feature>` (shown below as `enable_...`).

## GitOps

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| argo-events | argocd | `enable_argo_events` | Event-driven workflow automation framework for Kubernetes. | [docs](https://argoproj.github.io/argo-events/) | `addons/helm/oss.yaml` |
| argo-rollouts | argocd-rollouts | `enable_argo_rollouts` | Progressive delivery controller for canary, blue-green, and experiments. | [docs](https://argoproj.github.io/argo-rollouts/) | `addons/helm/oss.yaml` |
| argo-workflows | argo-workflows | `enable_argo_workflows` | Workflow engine for orchestrating parallel jobs on Kubernetes. | [docs](https://argoproj.github.io/argo-workflows/) | `addons/helm/oss.yaml` |
| argo-cd | argocd | `enable_argocd` | Declarative GitOps continuous delivery tool for Kubernetes. | [docs](https://argo-cd.readthedocs.io/) | `addons/helm/oss.yaml` |
| argocd-notifications | argocd | `enable_argocd_notifications` | Enables ArgoCD to send notifications (Slack, Email, etc.) for application events. | [docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) | `addons/helm/oss.yaml` |
| argo-workflows | argocd | `enable_aws_argo_workflows_ingress` | Argo Workflows chart configured with AWS-oriented ingress patterns. | [docs](https://argoproj.github.io/argo-helm) | `addons/helm/cloud/aws.yaml` |
| argo-cd | argocd | `enable_aws_argocd` | Argo CD release tuned for AWS reference architectures. | [docs](https://argoproj.github.io/argo-helm) | `addons/helm/cloud/aws.yaml` |
| argo-cd | argocd | `enable_aws_argocd_ingress` | Argo CD with ingress settings for AWS load balancers and DNS. | [docs](https://argoproj.github.io/argo-helm) | `addons/helm/cloud/aws.yaml` |

## Security

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| aws-privateca-issuer | cert-manager | `enable_aws_privateca_issuer` | cert-manager issuer for AWS Private Certificate Authority. | [docs](https://cert-manager.github.io/aws-privateca-issuer/) | `addons/helm/cloud/aws.yaml` |
| secrets-store-csi-driver-provider-aws | kube-system | `enable_aws_secrets_store_csi_driver_provider` | AWS provider for the Secrets Store CSI Driver (Secrets Manager / Parameter Store). | [docs](https://github.com/aws/secrets-store-csi-driver-provider-aws) | `addons/helm/cloud/aws.yaml` |
| cert-manager | cert-manager | `enable_cert_manager` | Automates TLS certificate issuance and renewal in Kubernetes. | [docs](https://cert-manager.io/) | `addons/helm/oss.yaml` |
| external-secrets | external-secrets | `enable_external_secrets` | Integrates external secret stores with Kubernetes Secrets. | [docs](https://external-secrets.io/) | `addons/helm/oss.yaml` |
| kyverno | kyverno-system | `enable_kyverno` | Kubernetes-native policy engine for admission control and reporting. | [docs](https://kyverno.io/) | `addons/helm/oss.yaml` |
| kyverno-policies | kyverno-system | `enable_kyverno_policies` | Opinionated Kyverno policies for the platform (chart in this repository). | [docs](https://github.com/appvia/kubernetes-platform/tree/main/charts/kyverno-policies) | `addons/helm/oss.yaml` |
| secrets-store-csi-driver | kube-system | `enable_secrets_store_csi_driver` | Mounts secrets from external stores into pods as volumes. | [docs](https://secrets-store-csi-driver.sigs.k8s.io/) | `addons/helm/oss.yaml` |

### Kustomize

| Path | Namespace | Feature flag | Description | Link | Source |
|------|-----------|--------------|-------------|------|--------|
| base | cert-manager | `enable_cert_manager` | Patched cert-manager overlay including self-signed ClusterIssuer. | [docs](https://cert-manager.io/) | `addons/kustomize/oss/cert-manager/kustomize.yaml` |
| base | external-secrets | `enable_external_secrets` | AWS ClusterSecretStore and related wiring for External Secrets. | [docs](https://external-secrets.io/) | `addons/kustomize/aws/external_secrets/kustomize.yaml` |

## Networking

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| aws-gateway-controller-chart | kube-system | `enable_aws_gateway_api_controller` | AWS Gateway API controller for VPC Lattice-backed HTTP routes. | [docs](https://github.com/aws/aws-application-networking-k8s) | `addons/helm/cloud/aws.yaml` |
| aws-load-balancer-controller | ingress-system | `enable_aws_load_balancer` | AWS Load Balancer Controller for ALB/NLB and Gateway API integration. | [docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) | `addons/helm/cloud/aws.yaml` |
| cilium | cilium-system | `enable_cilium` | eBPF-based CNI, service mesh, and network security for Kubernetes. | [docs](https://cilium.io/) | `addons/helm/oss.yaml` |
| external-dns | kube-system | `enable_external_dns` | Synchronizes Kubernetes Services and Ingresses with DNS providers. | [docs](https://github.com/kubernetes-sigs/external-dns) | `addons/helm/oss.yaml` |

### Kustomize

| Path | Namespace | Feature flag | Description | Link | Source |
|------|-----------|--------------|-------------|------|--------|
| https://github.com/kubernetes-sigs/gateway-api@config/crd/experimental | kube-system | `enable_gateway_api` | Experimental Gateway API CRDs for ingress and mesh-style routing. | [docs](https://gateway-api.sigs.k8s.io/) | `addons/kustomize/oss/gateway_api_experimental/kustomize.yaml` |
| https://github.com/kubernetes-sigs/gateway-api@config/crd | kube-system | `enable_gateway_api` | Gateway API CRDs for ingress and mesh-style routing. | [docs](https://gateway-api.sigs.k8s.io/) | `addons/kustomize/oss/gateway_api/kustomize.yaml` |

## Observability

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| aws-cloudwatch-metrics | kube-system | `enable_aws_cloudwatch_metrics` | CloudWatch agent for cluster and node metrics on EKS. | [docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html) | `addons/helm/cloud/aws.yaml` |
| aws-fargate-fluentbit | kube-system | `enable_aws_fargate_fluentbit` | Fluent Bit configuration for Fargate log routing to CloudWatch. | [docs](https://github.com/gitops-bridge-dev/gitops-bridge) | `addons/helm/cloud/aws.yaml` |
| aws-for-fluent-bit | kube-system | `enable_aws_for_fluentbit` | Fluent Bit log router shipping container logs to CloudWatch Logs. | [docs](https://github.com/aws/aws-for-fluent-bit) | `addons/helm/cloud/aws.yaml` |
| kube-prometheus-stack | prometheus | `enable_kube_prometheus_stack` | Prometheus, Grafana, Alertmanager, and kube-state-metrics bundle. | [docs](https://github.com/prometheus-community/helm-charts) | `addons/helm/oss.yaml` |
| metrics-server | kube-system | `enable_metrics_server` | Cluster-wide aggregator of resource usage metrics for HPA and kubectl top. | [docs](https://github.com/kubernetes-sigs/metrics-server) | `addons/helm/oss.yaml` |
| prometheus-adapter | prometheus | `enable_prometheus_adapter` | Exposes Prometheus metrics as custom metrics for the Kubernetes HPA. | [docs](https://github.com/kubernetes-sigs/prometheus-adapter) | `addons/helm/oss.yaml` |

## Cost

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| kubecost | kubecost | `enable_kubecost` | Kubernetes cost monitoring and allocation. | [docs](https://www.kubecost.com/) | `addons/helm/oss.yaml` |
| opencost | opencost | `enable_opencost` | Open source cost monitoring for Kubernetes workloads. | [docs](https://www.opencost.io/) | `addons/helm/oss.yaml` |

## Storage

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| aws-ebs-csi-classes | kube-system | `enable_aws_ebs_csi_resources` | Default StorageClass and related helpers for AWS EBS CSI volumes. | [docs](https://github.com/gitops-bridge-dev/gitops-bridge) | `addons/helm/cloud/aws.yaml` |
| aws-efs-csi-driver | kube-system | `enable_aws_efs_csi_driver` | CSI driver for Amazon EFS file systems. | [docs](https://github.com/kubernetes-sigs/aws-efs-csi-driver) | `addons/helm/cloud/aws.yaml` |
| aws-fsx-csi-driver | kube-system | `enable_aws_fsx_csi_driver` | CSI driver for Amazon FSx for Lustre file systems. | [docs](https://github.com/kubernetes-sigs/aws-fsx-csi-driver) | `addons/helm/cloud/aws.yaml` |
| velero | velero | `enable_aws_velero` | Backup and migrate cluster resources and persistent volumes. | [docs](https://velero.io/) | `addons/helm/cloud/aws.yaml` |

### Kustomize

| Path | Namespace | Feature flag | Description | Link | Source |
|------|-----------|--------------|-------------|------|--------|
| base | kube-system | `enable_core` | Used to provision a storage class for data volumes | [docs](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) | `addons/kustomize/aws/storageclass/kustomize.yaml` |

## Compute

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| aws-node-termination-handler | kube-system | `enable_aws_node_termination_handler` | Gracefully drains nodes on EC2 spot interruption and maintenance events. | [docs](https://github.com/aws/aws-node-termination-handler) | `addons/helm/cloud/aws.yaml` |
| cluster-autoscaler | kube-system | `enable_cluster_autoscaler` | Automatically adjusts the number of nodes in a cluster. | [docs](https://github.com/kubernetes/autoscaler) | `addons/helm/oss.yaml` |
| karpenter-nodepools | kube-system | `enable_karpenter_nodepools` | Platform chart defining Karpenter NodePools and related objects. | [docs](https://github.com/appvia/kubernetes-platform/tree/main/charts/karpenter-nodepools) | `addons/helm/cloud/aws.yaml` |
| vpa | kube-system | `enable_vpa` | Automatically adjusts CPU and memory requests for running pods. | [docs](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) | `addons/helm/oss.yaml` |

## Workloads

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| keda | keda-system | `enable_keda` | Event-driven autoscaling for workloads and HTTP traffic. | [docs](https://keda.sh/) | `addons/helm/oss.yaml` |
| volcano | volcano-system | `enable_volcano` | Batch scheduler for high-performance workloads and AI/ML jobs. | [docs](https://volcano.sh/) | `addons/helm/oss.yaml` |

## AWS

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| aws-controllers-k8s/apigatewayv2-chart | ack-system | `enable_aws_ack_apigatewayv2` | ACK controller for Amazon API Gateway v2. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/dynamodb-chart | ack-system | `enable_aws_ack_dynamodb` | ACK controller for Amazon DynamoDB. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/eks-chart | ack-system | `enable_aws_ack_eks` | ACK controller for Amazon EKS. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/eventbridge-chart | ack-system | `enable_aws_ack_eventbridge` | ACK controller for Amazon EventBridge. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/iam-chart | ack-system | `enable_aws_ack_iam` | ACK controller for AWS IAM. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/prometheusservice-chart | ack-system | `enable_aws_ack_prometheusservice` | ACK controller for Amazon Managed Service for Prometheus. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/rds-chart | ack-system | `enable_aws_ack_rds` | ACK controller for Amazon RDS. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/s3-chart | ack-system | `enable_aws_ack_s3` | ACK controller for Amazon S3. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/ses-chart | ack-system | `enable_aws_ack_ses` | ACK controller for Amazon SES. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/sfn-chart | ack-system | `enable_aws_ack_sfn` | ACK controller for AWS Step Functions. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/sns-chart | ack-system | `enable_aws_ack_sns` | ACK controller for Amazon SNS. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| aws-controllers-k8s/sqs-chart | ack-system | `enable_aws_ack_sqs` | ACK controller for Amazon SQS. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/helm/cloud/aws.yaml` |
| crossplane-aws | crossplane-system | `enable_aws_crossplane_provider` | Crossplane AWS provider bundle for GitOps Bridge-style installs. | [docs](https://github.com/gitops-bridge-dev/gitops-bridge) | `addons/helm/cloud/aws.yaml` |
| crossplane-aws-upbound | crossplane-system | `enable_aws_crossplane_upbound_provider` | Upbound AWS provider family for Crossplane on EKS. | [docs](https://github.com/gitops-bridge-dev/gitops-bridge) | `addons/helm/cloud/aws.yaml` |

### Kustomize

| Path | Namespace | Feature flag | Description | Link | Source |
|------|-----------|--------------|-------------|------|--------|
| base | ack-system | `enable_aws_ack_dynamodb` | IAM roles and Pod Identity associations for the DynamoDB ACK controller. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/kustomize/aws/aws_ack_dynamodb/kustomize.yaml` |
| base | ack-system | `enable_aws_ack_prometheusservice` | IAM roles and Pod Identity associations for the Amazon Managed Prometheus ACK controller. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/kustomize/aws/aws_ack_prometheusservice/kustomize.yaml` |
| base | ack-system | `enable_aws_ack_s3` | IAM roles and Pod Identity associations for the S3 ACK controller. | [docs](https://aws-controllers-k8s.github.io/community/) | `addons/kustomize/aws/aws_ack_s3/kustomize.yaml` |

## Platform

### Helm

| Chart | Namespace | Feature flag | Description | Link | Source |
|-------|-----------|--------------|-------------|------|--------|
| — | kro-system | `enable_kro` | Kubernetes Resource Orchestrator for managing groups of custom resources. | [docs](https://kro.run/) | `addons/helm/oss.yaml` |
| terranetes-controller | terranetes-system | `enable_terranetes` | Terranetes controller for provisioning cloud resources from Kubernetes. | [docs](https://terranetes.appvia.io/) | `addons/helm/oss.yaml` |

### Kustomize

| Path | Namespace | Feature flag | Description | Link | Source |
|------|-----------|--------------|-------------|------|--------|
| base | kube-system | `enable_core` | Deploy priority classes to the kube-system namespace | [docs](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/) | `addons/kustomize/oss/priorityclass/kustomize.yaml` |
| base | terraform-system | `enable_terranetes` | Used to provision the various addons for the Terranetes platform | [docs](https://terranetes.appvia.io/) | `addons/kustomize/oss/terranetes/kustomize.yaml` |
| https://github.com/appvia/terranetes-cloudresources.git@cloudresources/aws/ | terraform-system | `enable_terranetes_crs` | A collection of Terranetes Cloud Resource Plans | [docs](https://github.com/appvia/terranetes-cloudresources) | `addons/kustomize/oss/terranetes-cr/kustomize.yaml` |

