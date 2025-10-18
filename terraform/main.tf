## Provision a network for the cluster
module "network" {
  source  = "appvia/network/aws"
  version = "0.6.12"

  availability_zones     = 3
  name                   = local.cluster_name
  nat_gateway_mode       = var.nat_gateway_mode
  private_subnet_netmask = var.private_subnet_netmask
  public_subnet_netmask  = var.public_subnet_netmask
  tags                   = local.tags
  transit_gateway_id     = var.transit_gateway_id
  transit_gateway_routes = var.transit_gateway_routes
  vpc_cidr               = var.vpc_cidr

  ## We tag the private subnets with the cluster name and the role internal-elb
  private_subnet_tags = merge(local.tags, {
    "karpenter.sh/discovery"                    = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"           = "1"
  })

  ## If public subnets are being provisioned, we tag them with the cluster name
  public_subnet_tags = var.public_subnet_netmask > 0 ? merge(local.tags, {
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                    = "1"
  }) : null
}

## Provision a EKS cluster for the hub
module "eks" {
  source = "appvia/eks/aws"
  version = "1.2.4"

  access_entries         = local.access_entries
  cluster_name           = local.cluster_name
  enable_private_access  = true
  enable_public_access   = var.enable_public_access
  kms_key_administrators = [local.root_account_arn]
  kubernetes_version     = var.kubernetes_version
  pod_identity           = local.pod_identity
  private_subnet_ids     = module.network.private_subnet_ids
  tags                   = local.tags
  vpc_id                 = module.network.vpc_id

  ## Hub-Spoke configuration - if the cluster is part of a hub-spoke architecture, update the
  ## following variables
  hub_account_id   = var.hub_account_id
  hub_account_role = var.hub_account_role

  ## EBS CSI driver configuration
  ebs_csi_driver = {
    enabled = var.enable_ebs_csi_driver
    version = var.ebs_csi_driver_version
  }

  ## Certificate manager configuration
  cert_manager = {
    enabled          = true
    namespace        = "cert-manager"
    service_account  = "cert-manager"
    hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]
  }

  ## ArgoCD configuration
  argocd = {
    enabled         = true
    namespace       = "argocd"
    service_account = "argocd"
  }

  external_secrets = {
    enabled              = true
    namespace            = "external-secrets"
    service_account      = "external-secrets"
    secrets_manager_arns = ["arn:aws:secretsmanager:::secret/*"]
    ssm_parameter_arns   = ["arn:aws:ssm:::parameter/eks/*"]
  }

  ## External DNS configuration
  external_dns = {
    enabled          = true
    namespace        = "external-dns"
    service_account  = "external-dns"
    hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]
  }

  ## Enable the terranetes platform
  terranetes = {
    enabled = var.enable_terranetes
  }
}

## Provision and bootstrap the platform using an tenant repository
module "platform" {
  count  = var.enable_platform ? 1 : 0
  source = "appvia/eks/aws//modules/platform"
  version = "1.2.4"

  ## Name of the cluster
  cluster_name = local.cluster_name
  # The type of cluster
  cluster_type = local.cluster_type
  # Any rrepositories to be provisioned
  repositories = var.argocd_repositories
  ## Revision overrides
  revision_overrides = var.revision_overrides
  ## The platform repository
  platform_repository = local.platform_repository
  # The location of the platform repository
  platform_revision = local.platform_revision
  # The location of the tenant repository
  tenant_repository = local.tenant_repository
  # You pretty much always want to use the HEAD
  tenant_revision = local.tenant_revision
  ## The tenant repository path
  tenant_path = local.tenant_path

  depends_on = [
    module.eks
  ]
}
