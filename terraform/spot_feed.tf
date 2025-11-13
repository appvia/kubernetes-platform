#
## Spot Feed Data used by OpenCost
# 

locals {
  ## Auto generate the spot feed bucket name if not provided
  auto_generated_spot_feed_bucket_name = format("opencost-spot-data-feed-%s", local.account_id)
  ## Name of the spot feed bucket else we auto generate one
  spot_feed_bucket_name = var.opencost.spot_feed_bucket_name != null ? var.opencost.spot_feed_bucket_name : local.auto_generated_spot_feed_bucket_name
  ## The expected spot feed bucket arn
  expected_spot_feed_bucket_arn = format("arn:aws:s3:::%s", local.spot_feed_bucket_name)
}

data "aws_iam_policy_document" "spot_feed_bucket_policy" {
  count = var.opencost.enable_spot_feed ? 1 : 0

  statement {
    sid     = "AllowSpotFeedWriteAccess"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    resources = [
      format("%s/*", local.expected_spot_feed_bucket_arn),
    ]
  }

  statement {
    sid     = "AllowSpotFeedListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    resources = [
      local.expected_spot_feed_bucket_arn,
      format("%s/*", local.expected_spot_feed_bucket_arn),
    ]
  }

  statement {
    sid    = "AllowGetObject"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.root_account_arn]
    }
    actions = ["s3:GetObject"]
    resources = [
      local.expected_spot_feed_bucket_arn,
      format("%s/*", local.expected_spot_feed_bucket_arn),
    ]
  }

  statement {
    sid     = "AllowPutObject"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    principals {
      type        = "AWS"
      identifiers = [local.root_account_arn]
    }
    resources = [
      local.expected_spot_feed_bucket_arn,
      format("%s/*", local.expected_spot_feed_bucket_arn),
    ]
  }

  statement {
    sid     = "AllowListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    principals {
      type        = "AWS"
      identifiers = [local.root_account_arn]
    }
    resources = [
      local.expected_spot_feed_bucket_arn,
      format("%s/*", local.expected_spot_feed_bucket_arn),
    ]
  }
}

## Provision the bucket for the spot feed
module "spot_feed_bucket" {
  count   = var.opencost.enable_spot_feed ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.10.0"

  bucket                                = local.spot_feed_bucket_name
  attach_deny_insecure_transport_policy = true
  attach_policy                         = true
  attach_require_latest_tls_policy      = true
  force_destroy                         = true
  object_ownership                      = "ObjectWriter"
  policy                                = data.aws_iam_policy_document.spot_feed_bucket_policy[0].json
  tags                                  = merge(local.tags, { "Name" = local.spot_feed_bucket_name })

  grant = [
    {
      type       = "CanonicalUser"
      permission = "FULL_CONTROL"
      id         = data.aws_canonical_user_id.current.id
    }
  ]

  lifecycle_rule = [
    {
      ## Indicates if we should enable the lifecycle rule
      enabled = true
      ## The id of the lifecycle rule
      id = "delete-non-current-versions"
      # Remove non-current versions after 7 days
      noncurrent_version_expiration = {
        ## The number of days to retain non-current versions
        days = 7
      }
    }
  ]

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

## Provision the spot feed, and direct towards to the bucket
resource "aws_spot_datafeed_subscription" "default" {
  count = var.opencost.enable_spot_feed ? 1 : 0

  bucket = local.spot_feed_bucket_name
  prefix = var.opencost.spot_feed_prefix

  depends_on = [
    module.spot_feed_bucket,
  ]
}

## Provision the pod identity for the spot feed
module "spot_feed_pod_identity" {
  count   = var.opencost.enable_spot_feed ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.2.0"

  name = "${local.cluster_name}-spot-feed"
  ## The description for the role assumed by the Spot Feed
  description = "Role assumed by the Spot Feed for the ${local.cluster_name} cluster"
  ## The description for the custom policy for the Spot Feed
  custom_policy_description = "Permissions to access the S3 bucket for the Spot Feed for the ${local.cluster_name} cluster"
  ## The tags for the Spot Feed pod identity
  tags = local.tags
  ## Default association for the Spot Feed pod identity
  association_defaults = {
    namespace       = "opencost"
    service_account = "opencost"
  }

  ## Policy Statements for the Spot Feed pod identity
  policy_statements = [
    {
      sid     = "AllowGetObject"
      effect  = "Allow"
      actions = ["s3:GetObject"]
      resources = [
        format("%s/*", module.spot_feed_bucket[0].s3_bucket_id),
      ]
    },
    {
      sid     = "AllowListBucket"
      effect  = "Allow"
      actions = ["s3:ListBucket"]
      resources = [
        module.spot_feed_bucket[0].s3_bucket_id,
        format("%s/*", module.spot_feed_bucket[0].s3_bucket_id),
      ]
    }
  ]

  ## Pod Identity Associations
  associations = {
    addon = {
      cluster_name = module.eks.cluster_name
    }
  }
}
