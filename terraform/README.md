# Terraform

This folder contains the Terraform configuration for provisioning an EKS cluster and bootstrapping it with the Kubernetes platform. The code here is provided as an example implementation only, and not reflective of a production grade deployment.

The Terraform code will:

- Create a new EKS cluster in AWS
- Configure the necessary networking and IAM roles
- Bootstrap the cluster with the platform components
- Set up initial GitOps configuration

Note: This is intended as a reference implementation. For production use, you should carefully review and customize the configuration according to your requirements.

## Provision a Development Cluster

You can provision a development cluster using

```shell
terraform apply -var-file=variables/dev.tfvars
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.0.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks"></a> [eks](#module\_eks) | github.com/appvia/terraform-aws-eks.git | dev |
| <a name="module_network"></a> [network](#module\_network) | appvia/network/aws | 0.6.12 |
| <a name="module_platform"></a> [platform](#module\_platform) | appvia/eks/aws//modules/platform | 1.2.6 |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_path"></a> [cluster\_path](#input\_cluster\_path) | The name of the cluster | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to apply to all resources | `map(string)` | n/a | yes |
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | Map of access entries to add to the cluster. | <pre>map(object({<br/>    ## The kubernetes groups<br/>    kubernetes_groups = optional(list(string))<br/>    ## The principal ARN<br/>    principal_arn = string<br/>    ## The policy associations<br/>    policy_associations = optional(map(object({<br/>      # The policy arn to associate<br/>      policy_arn = string<br/>      # The access scope (namespace or clsuter)<br/>      access_scope = object({<br/>        # The namespaces to apply the policy to (optional)<br/>        namespaces = optional(list(string))<br/>        # The type of access (namespace or cluster)<br/>        type = string<br/>      })<br/>    })))<br/>  }))</pre> | `null` | no |
| <a name="input_argocd_repositories"></a> [argocd\_repositories](#input\_argocd\_repositories) | A collection of repository secrets to add to the argocd namespace | <pre>map(object({<br/>    ## The description of the repository<br/>    description = string<br/>    ## An optional password for the repository<br/>    password = optional(string, null)<br/>    ## The secret to use for the repository<br/>    secret = optional(string, null)<br/>    ## The secret manager ARN to use for the secret<br/>    secret_manager_arn = optional(string, null)<br/>    ## An optional SSH private key for the repository<br/>    ssh_private_key = optional(string, null)<br/>    ## The URL for the repository<br/>    url = string<br/>    ## An optional username for the repository<br/>    username = optional(string, null)<br/>  }))</pre> | `{}` | no |
| <a name="input_enable_public_access"></a> [enable\_public\_access](#input\_enable\_public\_access) | The public access to the cluster endpoint | `bool` | `true` | no |
| <a name="input_hub_account_id"></a> [hub\_account\_id](#input\_hub\_account\_id) | When using a hub deployment options, this is the account where argocd is running | `string` | `null` | no |
| <a name="input_hub_account_role"></a> [hub\_account\_role](#input\_hub\_account\_role) | The role to use for the hub account | `string` | `"argocd-pod-identity-hub"` | no |
| <a name="input_kubecosts"></a> [kubecosts](#input\_kubecosts) | The Kubecost configuration | <pre>object({<br/>    ## Indicates if we should enable the Kubecost platform<br/>    enable = optional(bool, false)<br/>    ## The namespace to deploy the Kubecost platform to<br/>    namespace = optional(string, "kubecosts")<br/>    ## The service account to deploy the Kubecost platform to<br/>    service_account = optional(string, "kubecosts")<br/>    ## Federated storage configuration<br/>    federated_storage = optional(object({<br/>      ## Indicates if we should create the federated bucket<br/>      create_bucket = optional(bool, false)<br/>      ## KMS key ARN to use for the federated bucket<br/>      kms_key_arn = optional(string, null)<br/>      ## The ARN of the federated bucket to use for the Kubecost platform<br/>      federated_bucket_arn = optional(string, null)<br/>      ## List of principals to allowed to write to the federated bucket<br/>      allowed_principals = optional(list(string), [])<br/>    }), {})<br/>    ## Cloud Costs feature<br/>    cloud_costs = optional(object({<br/>      ## Indicates if we should enable cloud costs via Athena<br/>      enable = optional(bool, false)<br/>      ## The ARN of the S3 bucket for Cost and Usage Report (CUR) data<br/>      cur_bucket_arn = string<br/>      ## The ARN of the S3 bucket for Athena query results<br/>      athena_bucket_arn = string<br/>      # The name of the Athena database for CUR data<br/>      athena_database_name = optional(string, null)<br/>      ## The ARN of the Athena table for CUR data<br/>      athena_table_arn = optional(string, null)<br/>    }), null)<br/>  })</pre> | `null` | no |
| <a name="input_kubecosts_agent"></a> [kubecosts\_agent](#input\_kubecosts\_agent) | The Kubecost Agent configuration | <pre>object({<br/>    ## Indicates if we should enable the Kubecost Agent platform<br/>    enable = optional(bool, false)<br/>    ## The namespace to deploy the Kubecost Agent platform to<br/>    namespace = optional(string, "kubecosts")<br/>    ## The service account to deploy the Kubecost Agent platform to<br/>    service_account = optional(string, "kubecosts")<br/>    ## The ARN of the federated bucket to use for the Kubecost Agent platform<br/>    federated_bucket_arn = string<br/>    ## List of principals to allowed to write to the federated bucket<br/>    allowed_principals = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The version of the cluster to provision | `string` | `"1.34"` | no |
| <a name="input_nat_gateway_mode"></a> [nat\_gateway\_mode](#input\_nat\_gateway\_mode) | The NAT gateway mode | `string` | `"single_az"` | no |
| <a name="input_pod_identity"></a> [pod\_identity](#input\_pod\_identity) | The pod identity configuration | <pre>map(object({<br/>    ## Indicates if we should enable the pod identity<br/>    enabled = optional(bool, true)<br/>    ## The namespace to deploy the pod identity to<br/>    description = optional(string, null)<br/>    ## The service account to deploy the pod identity to<br/>    service_account = optional(string, null)<br/>    ## The managed policy ARNs to attach to the pod identity<br/>    managed_policy_arns = optional(map(string), {})<br/>    ## The permissions boundary ARN to use for the pod identity<br/>    permissions_boundary_arn = optional(string, null)<br/>    ## The namespace to deploy the pod identity to<br/>    namespace = optional(string, null)<br/>    ## The name of the pod identity role<br/>    name = optional(string, null)<br/>    ## Additional policy statements to attach to the pod identity role<br/>    policy_statements = optional(list(object({<br/>      ## The statement ID<br/>      sid = optional(string, null)<br/>      ## The actions to allow<br/>      actions = optional(list(string), [])<br/>      ## The resources to allow<br/>      resources = optional(list(string), [])<br/>      ## The effect to allow<br/>      effect = optional(string, null)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_private_subnet_netmask"></a> [private\_subnet\_netmask](#input\_private\_subnet\_netmask) | The netmask for the private subnets | `number` | `24` | no |
| <a name="input_public_subnet_netmask"></a> [public\_subnet\_netmask](#input\_public\_subnet\_netmask) | The netmask for the public subnets | `number` | `24` | no |
| <a name="input_revision_overrides"></a> [revision\_overrides](#input\_revision\_overrides) | Revision overrides permit the user to override the revision contained in cluster definition | <pre>object({<br/>    ## The platform revision or branch to use<br/>    platform_revision = optional(string, null)<br/>    ## The tenant revision or branch to use<br/>    tenant_revision = optional(string, null)<br/>  })</pre> | `null` | no |
| <a name="input_sso_administrator_role"></a> [sso\_administrator\_role](#input\_sso\_administrator\_role) | The SSO administrator role ARN | `string` | `null` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | The ID of the Transit Gateway to use, when attaching to a Transit Gateway | `string` | `null` | no |
| <a name="input_transit_gateway_routes"></a> [transit\_gateway\_routes](#input\_transit\_gateway\_routes) | The routes to add to the Transit Gateway | `map(string)` | <pre>{<br/>  "private": "0.0.0.0/0"<br/>}</pre> | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | The CIDR block for the VPC, if not using an existing VPC | `string` | `"10.90.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_argocd_spoke_role_arn"></a> [argocd\_spoke\_role\_arn](#output\_argocd\_spoke\_role\_arn) | When provisioning a spoke, the is the IAM role the hub must assume |
| <a name="output_eks_cluster_certificate_authority_data"></a> [eks\_cluster\_certificate\_authority\_data](#output\_eks\_cluster\_certificate\_authority\_data) | The certificate authority of the EKS cluster |
| <a name="output_eks_cluster_endpoint"></a> [eks\_cluster\_endpoint](#output\_eks\_cluster\_endpoint) | The endpoint of the EKS cluster |
| <a name="output_eks_cluster_name"></a> [eks\_cluster\_name](#output\_eks\_cluster\_name) | The name of the EKS cluster |
<!-- END_TF_DOCS -->

