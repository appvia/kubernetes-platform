
locals {
#  ## The SSO Administrator role ARN
#  sso_role_name = "AWSReservedSSO_Administrator_fbb916977087a86f"
#
#  ## Additional access entries to add to the cluster
#  ## Documentation: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_access_settings
#  access_entries = merge(var.access_entries, {
#    admin = {
#      principal_arn = format("arn:aws:iam::%s:role/aws-reserved/sso.amazonaws.com/eu-west-2/%s", local.account_id, local.sso_role_name)
#      policy_associations = {
#        cluster_admin = {
#          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
#          access_scope = {
#            type = "cluster"
#          }
#        }
#      }
#    }
#  })
  access_entries = var.access_entries
}
