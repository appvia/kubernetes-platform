## Find the current account
data "aws_caller_identity" "current" {}

## Find the current region
data "aws_region" "current" {}

## Find the current canonical user id
data "aws_canonical_user_id" "current" {}
