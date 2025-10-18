
variable "access_entries" {
  description = "Map of access entries to add to the cluster."
  type = map(object({
    ## The kubernetes groups
    kubernetes_groups = optional(list(string))
    ## The principal ARN
    principal_arn = string
    ## The policy associations
    policy_associations = optional(map(object({
      # The policy arn to associate
      policy_arn = string
      # The access scope (namespace or clsuter)
      access_scope = object({
        # The namespaces to apply the policy to (optional)
        namespaces = optional(list(string))
        # The type of access (namespace or cluster)
        type = string
      })
    })))
  }))
  default = null
}

variable "sso_administrator_role" {
  description = "The SSO administrator role ARN"
  type        = string
  default     = null
}

variable "revision_overrides" {
  description = "Revision overrides permit the user to override the revision contained in cluster definition"
  type = object({
    ## The platform revision or branch to use
    platform_revision = optional(string, null)
    ## The tenant revision or branch to use
    tenant_revision = optional(string, null)
  })
  default = null
}

variable "argocd_repositories" {
  description = "A collection of repository secrets to add to the argocd namespace"
  type = map(object({
    ## The description of the repository
    description = string
    ## An optional password for the repository
    password = optional(string, null)
    ## The secret to use for the repository
    secret = optional(string, null)
    ## The secret manager ARN to use for the secret
    secret_manager_arn = optional(string, null)
    ## An optional SSH private key for the repository
    ssh_private_key = optional(string, null)
    ## The URL for the repository
    url = string
    ## An optional username for the repository
    username = optional(string, null)
  }))
  default = {}
}

variable "enable_public_access" {
  description = "The public access to the cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_path" {
  description = "The name of the cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "The version of the cluster to provision"
  type        = string
  default     = "1.34"
}

variable "hub_account_id" {
  description = "When using a hub deployment options, this is the account where argocd is running"
  type        = string
  default     = null
}

variable "hub_account_role" {
  description = "The role to use for the hub account"
  type        = string
  default     = "argocd-pod-identity-hub"
}


variable "nat_gateway_mode" {
  description = "The NAT gateway mode"
  type        = string
  default     = "single_az"
}

variable "private_subnet_netmask" {
  description = "The netmask for the private subnets"
  type        = number
  default     = 24
}

variable "public_subnet_netmask" {
  description = "The netmask for the public subnets"
  type        = number
  default     = 24
}

variable "tags" {
  description = "The tags to apply to all resources"
  type        = map(string)
}

variable "transit_gateway_id" {
  description = "The ID of the Transit Gateway to use, when attaching to a Transit Gateway"
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "The routes to add to the Transit Gateway"
  type        = map(string)
  default = {
    private = "0.0.0.0/0"
  }
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC, if not using an existing VPC"
  type        = string
  default     = "10.90.0.0/16"
}

variable "pod_identity" {
  description = "The pod identity configuration"
  type = map(object({
    ## Indicates if we should enable the pod identity
    enabled = optional(bool, true)
    ## The namespace to deploy the pod identity to
    description = optional(string, null)
    ## The service account to deploy the pod identity to
    service_account = optional(string, null)
    ## The managed policy ARNs to attach to the pod identity
    managed_policy_arns = optional(map(string), {})
    ## The permissions boundary ARN to use for the pod identity
    permissions_boundary_arn = optional(string, null)
    ## The namespace to deploy the pod identity to
    namespace = optional(string, null)
    ## The name of the pod identity role
    name = optional(string, null)
    ## Additional policy statements to attach to the pod identity role
    policy_statements = optional(list(object({
      ## The statement ID
      sid = optional(string, null)
      ## The actions to allow
      actions = optional(list(string), [])
      ## The resources to allow
      resources = optional(list(string), [])
      ## The effect to allow
      effect = optional(string, null)
    })), [])
  }))
  default = {}
}
