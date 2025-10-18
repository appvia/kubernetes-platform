
locals {
  ## Additional access entries to add to the cluster
  ## Documentation: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_access_settings
  access_entries = merge(var.access_entries, var.sso_administrator_role != null ? {
    admin = {
      principal_arn = format("arn:aws:iam::%s:role/aws-reserved/sso.amazonaws.com/eu-west-2/%s", local.account_id, var.sso_administrator_role)
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  } : {})
}
