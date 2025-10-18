
locals {
  ## Additional pod identity configuration
  ## Documentation: https://registry.terraform.io/providers/terraform-aws-modules/eks/latest/docs/modules/pod_identity
  pod_identity = merge(var.pod_identity, {})
}
