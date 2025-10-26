#
## AWS Managed Prometheus
# 

## Provision a cloudwatch metrics log group for prometheus
resource "aws_cloudwatch_log_group" "prometheus" {
  count = var.enable_aws_managed_prometheus ? 1 : 0

  name              = "/aws/prometheus/${local.cluster_name}/metrics"
  retention_in_days = 30
  tags              = local.tags
}

## Provision the AWS Managed Prometheus workspace
resource "aws_prometheus_workspace" "prometheus" {
  count = var.enable_aws_managed_prometheus ? 1 : 0

  alias = format("%s-%s", local.cluster_name, "prometheus")
  tags  = local.tags

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.prometheus[0].arn}:*"
  }
}
