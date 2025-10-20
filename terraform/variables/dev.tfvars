## Path to the cluster definition
cluster_path = "../release/standalone-aws/clusters/dev.yaml"
## Override revision or branch for the platform and tenant repositories
revision_overrides = {
  # The revision to use for the platform repository
  platform_revision = "main"
  # The revision to use for the tenant repository
  tenant_revision = "main"
}

# Network configuration
vpc_cidr = "10.90.0.0/16"

## Kubecost configuration
kubecosts = {
  enable = true
  federated_storage = {
    create_bucket = true
    federated_bucket_arn = "arn:aws:s3:::kubecost-federated-eu-west-2"
  }
}

## Tags to apply to the EKS cluster
tags = {
  # Name of the environment we are deploying to
  Environment = "Development"
  # The Git repository we are deploying from
  GitRepo = "https://github.com/appvia/kubernetes-platform"
  # The owner of the environment
  Owner = "Engineering"
  # The product of the environment
  Product = "EKS"
  # The provisioner of the environment
  Provisioner = "Terraform"
}
