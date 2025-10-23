
locals {
  ## The current account ID
  account_id = data.aws_caller_identity.current.account_id
  ## The cluster configuration, decoded from the YAML file
  cluster = yamldecode(file(var.cluster_path))
  ## The cluster_name of the cluster
  cluster_name = local.cluster.cluster_name
  ## The cluster type
  cluster_type = local.cluster.cluster_type
  ## The platform repository
  platform_repository = local.cluster.platform_repository
  ## The platform revision
  platform_revision = local.cluster.platform_revision
  ## Collection of tags to apply to resources
  tags = merge(var.tags, {})
  ## The tenant path
  tenant_path = local.cluster.tenant_path
  ## The tenant repository
  tenant_repository = local.cluster.tenant_repository
  ## The tenant revision
  tenant_revision = local.cluster.tenant_revision
  ## The root account ARN
  root_account_arn = "arn:aws:iam::${local.account_id}:root"
}

