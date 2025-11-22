## Disable the NAT gateway
nat_gateway_mode = "none"
## Transit Gateway Routes
transit_gateway_routes = {
  private = "0.0.0.0/0"
}
## Transit Gateway ID
transit_gateway_id = "tgw-0c5994aa363b1e132"
## The SSO administrator role ARN
sso_administrator_role = "AWSReservedSSO_Administrator_fbb916977087a86f"
## Indicates if we should enable the AWS Managed Prometheus
enable_aws_managed_prometheus = false

## OpenCost configuration
opencost = {
  enable_spot_feed = false
}
