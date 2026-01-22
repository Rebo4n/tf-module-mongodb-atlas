output "project_id" {
  description = "MongoDB Atlas Project ID"
  value       = mongodbatlas_project.this.id
}

output "cluster_id" {
  description = "MongoDB Atlas Cluster ID"
  value       = local.cluster.cluster_id
}

output "cluster_name" {
  description = "MongoDB Atlas Cluster Name"
  value       = local.cluster.name
}

output "connection_string_standard" {
  description = "Standard connection string (public)"
  value       = local.cluster.connection_strings.standard
  sensitive   = true
}

output "connection_string_private" {
  description = "Private connection string (via VPC peering)"
  value       = var.enable_vpc_peering && length(try(local.cluster.connection_strings.private, "")) > 0 ? local.cluster.connection_strings.private : null
  sensitive   = true
}

output "connection_string_private_srv" {
  description = "Private SRV connection string (via VPC peering)"
  value       = var.enable_vpc_peering && length(try(local.cluster.connection_strings.private_srv, "")) > 0 ? local.cluster.connection_strings.private_srv : null
  sensitive   = true
}

output "mongodb_server_list" {
  description = "Comma-separated list of MongoDB server hostnames (uses private endpoints if VPC peering enabled)"
  value       = var.enable_vpc_peering && length(try(local.cluster.connection_strings.private, "")) > 0 ? trimsuffix(replace(regex("mongodb://([^?]+)", local.cluster.connection_strings.private)[0], "mongodb://", ""), "/") : trimsuffix(replace(regex("mongodb://([^?]+)", local.cluster.connection_strings.standard)[0], "mongodb://", ""), "/")
}

output "state_name" {
  description = "Current state of the cluster"
  value       = local.cluster.state_name
}

output "mongo_db_version" {
  description = "Version of MongoDB the cluster is running"
  value       = local.cluster.mongo_db_version
}

# VPC Peering Outputs
output "network_container_id" {
  description = "MongoDB Atlas Network Container ID"
  value       = var.enable_vpc_peering ? mongodbatlas_network_container.this[0].container_id : null
}

output "atlas_vpc_cidr" {
  description = "MongoDB Atlas VPC CIDR block"
  value       = var.enable_vpc_peering ? mongodbatlas_network_container.this[0].atlas_cidr_block : null
}

output "peering_connection_id" {
  description = "VPC Peering Connection ID"
  value       = var.enable_vpc_peering ? mongodbatlas_network_peering.this[0].connection_id : null
}

output "peering_status" {
  description = "Status of the VPC peering connection"
  value       = var.enable_vpc_peering ? mongodbatlas_network_peering.this[0].status_name : null
}

# Database User Outputs
output "db_username" {
  description = "Database username (if created)"
  value       = var.create_user ? mongodbatlas_database_user.this[0].username : null
}

output "secrets_manager_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing MongoDB credentials"
  value       = var.create_user ? aws_secretsmanager_secret.mongodb_credentials[0].arn : null
}

output "secrets_manager_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing MongoDB credentials"
  value       = var.create_user ? aws_secretsmanager_secret.mongodb_credentials[0].name : null
}
