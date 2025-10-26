## Find the current account
data "aws_caller_identity" "current" {}

## Find the current region
data "aws_region" "current" {}
