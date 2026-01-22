variable "org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "project_name" {
  description = "MongoDB Atlas Project Name"
  type        = string
}

variable "cluster_name" {
  description = "MongoDB Atlas Cluster Name"
  type        = string
  default     = "Cluster0"
}

variable "cluster_type" {
  description = "Cluster type (REPLICASET, SHARDED, GEOSHARDED)"
  type        = string
  default     = "REPLICASET"
}

variable "instance_size" {
  description = "Instance size (M0 for free tier, M10+ for dedicated)"
  type        = string
  default     = "M0"
}

variable "mongodb_version" {
  description = "MongoDB major version"
  type        = string
  default     = "8.0"
}

variable "cloud_provider" {
  description = "Cloud provider (AWS, GCP, AZURE)"
  type        = string
  default     = "AWS"
}

variable "region" {
  description = "MongoDB Atlas region"
  type        = string
}

variable "disk_size_gb" {
  description = "Disk size in GB (not applicable for M0/M2/M5)"
  type        = number
  default     = null
}

variable "auto_scaling_disk_enabled" {
  description = "Enable auto-scaling for disk (not available for M0/M2/M5)"
  type        = bool
  default     = false
}

variable "backup_enabled" {
  description = "Enable cloud backup (not available for M0/M2/M5)"
  type        = bool
  default     = false
}

variable "advanced_config" {
  description = "Advanced configuration settings for dedicated clusters (M10+)"
  type = object({
    javascript_enabled                   = optional(bool, false)
    minimum_enabled_tls_protocol         = optional(string, "TLS1_2")
    no_table_scan                        = optional(bool, false)
    oplog_size_mb                        = optional(number, 2048)
    sample_size_bi_connector             = optional(number, 5000)
    sample_refresh_interval_bi_connector = optional(number, 300)
  })
  default = {
    javascript_enabled                   = false
    minimum_enabled_tls_protocol         = "TLS1_2"
    no_table_scan                        = false
    oplog_size_mb                        = 2048
    sample_size_bi_connector             = 5000
    sample_refresh_interval_bi_connector = 300
  }
}

variable "ip_access_list" {
  description = "List of IP addresses or CIDR blocks allowed to access MongoDB Atlas cluster"
  type = list(object({
    cidr_block = optional(string)
    ip_address = optional(string)
    comment    = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to MongoDB Atlas resources"
  type        = map(string)
  default     = {}
}

# VPC Peering Configuration
variable "enable_vpc_peering" {
  description = "Enable VPC peering between MongoDB Atlas and AWS VPC"
  type        = bool
  default     = false
}

variable "aws_vpc_id" {
  description = "AWS VPC ID to peer with MongoDB Atlas (required if enable_vpc_peering = true)"
  type        = string
  default     = null
}

variable "atlas_cidr_block" {
  description = "CIDR block for MongoDB Atlas VPC (must not overlap with AWS VPC). Default: 10.8.0.0/21"
  type        = string
}

# Database User Configuration
variable "create_user" {
  description = "Create a database user and store credentials in AWS Secrets Manager"
  type        = bool
  default     = false
}

variable "db_username" {
  description = "Database username (required if create_user = true)"
  type        = string
  default     = "app-user"
}

variable "db_user_database" {
  description = "Database name for user permissions (required if create_user = true)"
  type        = string
  default     = "admin"
}

variable "db_user_role" {
  description = "Database user role (readWrite, read, dbAdmin, etc.)"
  type        = string
  default     = "readWrite"
}

variable "secrets_manager_secret_name" {
  description = "AWS Secrets Manager secret name to store MongoDB credentials (required if create_user = true)"
  type        = string
  default     = "mongodb-atlas-credentials"
}
