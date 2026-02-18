resource "mongodbatlas_project" "this" {
  name   = var.project_name
  org_id = var.org_id

  tags = var.tags

  lifecycle {
    ignore_changes = [region_usage_restrictions]
  }
}

# Local to reference the active cluster (free or paid)
locals {
  cluster = var.instance_size == "M0" || var.instance_size == "M2" || var.instance_size == "M5" ? mongodbatlas_advanced_cluster.this[0] : mongodbatlas_advanced_cluster.this_paid[0]
}

# Free tier cluster (M0/M2/M5) - cannot be updated via API
resource "mongodbatlas_advanced_cluster" "this" {
  count = var.instance_size == "M0" || var.instance_size == "M2" || var.instance_size == "M5" ? 1 : 0

  project_id   = mongodbatlas_project.this.id
  name         = var.cluster_name
  cluster_type = var.cluster_type

  replication_specs = [{
    region_configs = [{
      electable_specs = {
        instance_size = var.instance_size
      }
      provider_name         = "TENANT"
      backing_provider_name = var.cloud_provider
      priority              = 7
      region_name           = var.region
    }]
  }]

  # M0/M2/M5 limitations: ignore all computed/changed attributes
  lifecycle {
    ignore_changes = all
  }
}

# Paid tier cluster (M10+) - fully managed by Terraform
resource "mongodbatlas_advanced_cluster" "this_paid" {
  count = var.instance_size != "M0" && var.instance_size != "M2" && var.instance_size != "M5" ? 1 : 0

  project_id             = mongodbatlas_project.this.id
  name                   = var.cluster_name
  cluster_type           = var.cluster_type
  mongo_db_major_version = var.mongodb_version
  backup_enabled         = var.backup_enabled

  replication_specs = [{
    num_shards = 1
    region_configs = [{
      electable_specs = {
        instance_size = var.instance_size
        node_count    = 3
      }
      disk_size_gb = var.disk_size_gb
      auto_scaling = {
        disk_gb_enabled = var.auto_scaling_disk_enabled
      }
      provider_name = var.cloud_provider
      priority      = 7
      region_name   = var.region
    }]
  }]

  advanced_configuration = {
    javascript_enabled                   = var.advanced_config.javascript_enabled
    minimum_enabled_tls_protocol         = var.advanced_config.minimum_enabled_tls_protocol
    no_table_scan                        = var.advanced_config.no_table_scan
    oplog_size_mb                        = var.advanced_config.oplog_size_mb
    sample_size_bi_connector             = var.advanced_config.sample_size_bi_connector
    sample_refresh_interval_bi_connector = var.advanced_config.sample_refresh_interval_bi_connector
  }
}

# MongoDB Atlas Project IP Access List (Security Group Inbound Rules)
resource "mongodbatlas_project_ip_access_list" "this" {
  for_each = { for idx, rule in var.ip_access_list : idx => rule }

  project_id = mongodbatlas_project.this.id
  cidr_block = lookup(each.value, "cidr_block", null)
  ip_address = lookup(each.value, "ip_address", null)
  comment    = lookup(each.value, "comment", "Managed by Terraform")
}

# Automatically add VPC CIDR to IP access list when VPC peering is enabled
resource "mongodbatlas_project_ip_access_list" "vpc_cidr" {
  count = var.enable_vpc_peering ? 1 : 0

  project_id = mongodbatlas_project.this.id
  cidr_block = data.aws_vpc.this[0].cidr_block
  comment    = "AWS VPC CIDR (auto-added for VPC peering) - Managed by Terraform"
}

# VPC Peering - Network Container (Atlas VPC)
resource "mongodbatlas_network_container" "this" {
  count = var.enable_vpc_peering ? 1 : 0

  project_id       = mongodbatlas_project.this.id
  atlas_cidr_block = var.atlas_cidr_block
  provider_name    = var.cloud_provider
  region_name      = var.region
}

# VPC Peering - Atlas to AWS
resource "mongodbatlas_network_peering" "this" {
  count = var.enable_vpc_peering ? 1 : 0

  project_id     = mongodbatlas_project.this.id
  container_id   = mongodbatlas_network_container.this[0].container_id
  provider_name  = var.cloud_provider
  
  # AWS-specific fields (automatically retrieved from data sources)
  accepter_region_name   = data.aws_region.current[0].name
  aws_account_id         = data.aws_caller_identity.current[0].account_id
  vpc_id                 = var.aws_vpc_id
  route_table_cidr_block = data.aws_vpc.this[0].cidr_block
}

# Database User Creation
resource "random_password" "db_user" {
  count = var.create_user ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_"  # Only use hyphens and underscores (safe for connection strings)
}

resource "mongodbatlas_database_user" "this" {
  count = var.create_user ? 1 : 0

  project_id         = mongodbatlas_project.this.id
  auth_database_name = "admin"
  username           = var.db_username
  password           = random_password.db_user[0].result

  roles {
    role_name     = var.db_user_role
    database_name = var.db_user_database
  }

  lifecycle {
    ignore_changes = [password]
  }

  depends_on = [
    mongodbatlas_advanced_cluster.this,
    mongodbatlas_advanced_cluster.this_paid
  ]
}

# Store credentials in AWS Secrets Manager
resource "aws_secretsmanager_secret" "mongodb_credentials" {
  count = var.create_user ? 1 : 0

  name        = var.secrets_manager_secret_name
  description = "MongoDB Atlas connection credentials for ${var.cluster_name}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "mongodb_credentials" {
  count = var.create_user ? 1 : 0

  secret_id = aws_secretsmanager_secret.mongodb_credentials[0].id
  secret_string = jsonencode({
    username          = mongodbatlas_database_user.this[0].username
    password          = random_password.db_user[0].result
    connection_string = local.cluster.connection_strings.standard
    connection_string_private = var.enable_vpc_peering && length(try(local.cluster.connection_strings.private, "")) > 0 ? local.cluster.connection_strings.private : ""
    database          = var.db_user_database
    cluster_name      = var.cluster_name
    project_id        = mongodbatlas_project.this.id
  })

  lifecycle {
    ignore_changes = [secret_string]
  }

  depends_on = [mongodbatlas_database_user.this]
}
