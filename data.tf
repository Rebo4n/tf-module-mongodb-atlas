# Get current AWS account ID
data "aws_caller_identity" "current" {
  count = var.enable_vpc_peering ? 1 : 0
}

# Get current AWS region
data "aws_region" "current" {
  count = var.enable_vpc_peering ? 1 : 0
}

# Get VPC details to retrieve CIDR block
data "aws_vpc" "this" {
  count = var.enable_vpc_peering ? 1 : 0
  id    = var.aws_vpc_id
}
