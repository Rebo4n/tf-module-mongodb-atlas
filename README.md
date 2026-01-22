# MongoDB Atlas Terraform Module Documentation

## Overview

This Terraform module provisions and manages MongoDB Atlas infrastructure including projects, clusters, IP access lists, and VPC peering connections with AWS.

---

## Features

* MongoDB Atlas Project and Cluster provisioning
* IP Access List (network security rules)
* VPC Peering with AWS (M10+ dedicated clusters only)
* Automatic private/public endpoint selection
* Support for M0 (free tier) through M10+ (dedicated clusters)

---

## Architecture Decision: Dual Resource Design

**Why Two Separate Cluster Resources?**

This module uses two separate `mongodbatlas_advanced_cluster` resources:
- `mongodbatlas_advanced_cluster.this[0]` - For M0/M2/M5 (free/shared tiers)
- `mongodbatlas_advanced_cluster.this_paid[0]` - For M10+ (dedicated clusters)

**Reason: MongoDB Atlas API Limitation**

MongoDB Atlas **does not allow M0/M2/M5 clusters to be updated via API**:

```
Error: (Error code: "TENANT_CLUSTER_UPDATE_UNSUPPORTED") 
Detail: Cannot update a M0/M2/M5 cluster through the public API.
```

**Solution:**
- **M0/M2/M5**: Uses `lifecycle { ignore_changes = [replication_specs, advanced_configuration] }` to prevent API update attempts
- **M10+**: Fully managed by Terraform with no restrictions

**Upgrading from M0 to M10+:**
1. Change `instance_size = "M10"` in your configuration
2. Run `terraform apply` - Terraform will:
   - Destroy the M0 cluster (`mongodbatlas_advanced_cluster.this[0]`)
   - Create a new M10 cluster (`mongodbatlas_advanced_cluster.this_paid[0]`)
3. **Note**: This is a destructive change - backup your data first!

---

## Prerequisites

### MongoDB Atlas API Credentials

The module requires MongoDB Atlas API credentials stored in AWS Secrets Manager.

**Steps to set up:**

1. **Generate API Keys in MongoDB Atlas:**
   * Go to: Organization Settings → Access Manager → API Keys
   * Click "Create API Key"
   * Select role: `Organization Project Creator`
   * Save the Public Key and Private Key

2. **Store in AWS Secrets Manager:**
   Create a secret with this JSON structure:
   ```json
   {
     "public_key": "your-atlas-public-key",
     "private_key": "your-atlas-private-key"
   }
   ```
   
   **Required Fields:**
   - `public_key`: MongoDB Atlas API Public Key
   - `private_key`: MongoDB Atlas API Private Key

3. **Configure Provider in Root Module:**
   ```hcl
   provider "mongodbatlas" {
     public_key  = jsondecode(data.aws_secretsmanager_secret_version.mongodbatlas.secret_string)["public_key"]
     private_key = jsondecode(data.aws_secretsmanager_secret_version.mongodbatlas.secret_string)["private_key"]
   }

   data "aws_secretsmanager_secret" "mongodbatlas" {
    name = "example/mongodbatlas/creds"
   }

   data "aws_secretsmanager_secret_version" "mongodbatlas" {
     secret_id = data.aws_secretsmanager_secret.mongodbatlas.id
   }
   ```

---

## Usage Examples

### Basic Configuration (Free Tier M0)

```hcl
module "mongodb_atlas" {
  source = "./modules/mongodb-atlas"

  org_id       = "0123456789abcdef01234567"
  project_name = "my-project"
  cluster_name = "Cluster0"
  
  instance_size   = "M0"
  mongodb_version = "8.0"
  region          = "EU_CENTRAL_1"
  
  ip_access_list = [
    {
      cidr_block = "10.0.0.0/16"
      comment    = "VPC CIDR"
    },
    {
      ip_address = "203.0.113.25"
      comment    = "Office IP"
    }
  ]

  tags = {
    Environment = "dev"
    Project     = "myapp"
  }
}
```

### Production with VPC Peering (M10+)

```hcl
module "mongodb_atlas" {
  source = "./modules/mongodb-atlas"

  org_id       = "0123456789abcdef01234567"
  project_name = "production-project"
  cluster_name = "ProductionCluster"
  
  instance_size             = "M10"  # Minimum for VPC peering
  mongodb_version           = "8.0"
  cloud_provider            = "AWS"
  region                    = "EU_CENTRAL_1"
  disk_size_gb              = 100
  auto_scaling_disk_enabled = true
  backup_enabled            = true
  
  # VPC Peering Configuration (VPC CIDR is automatically added to IP access list!)
  enable_vpc_peering = true
  aws_vpc_id         = module.vpc.vpc_id
  atlas_cidr_block   = "192.168.240.0/21"  # Must not overlap with AWS VPC
  
  # IP access list for external IPs only (VPC CIDR is auto-added, don't add it here!)
  ip_access_list = [
    {
      cidr_block = "198.51.100.10/32"
      comment    = "Example Client VPN"
    }
    # No need to add VPC CIDR - it's automatically added when peering is enabled!
  ]

  tags = {
    Environment = "production"
    Project     = "myapp"
    CostCenter  = "engineering"
  }
}
```

### With Database User Creation (Stores Credentials in Secrets Manager)

```hcl
module "mongodb_atlas" {
  source = "./modules/mongodb-atlas"

  org_id       = "0123456789abcdef01234567"
  project_name = "my-project"
  cluster_name = "Cluster0"
  
  instance_size   = "M10"
  mongodb_version = "8.0"
  region          = "EU_CENTRAL_1"
  
  # Automatically create database user
  create_user                   = true
  db_username                   = "atlas-demo-app"
  db_user_database              = "appdb"             # Database the user has permissions on
  db_user_role                  = "readWrite"          # Role: readWrite, read, dbAdmin, etc.
  secrets_manager_secret_name   = "example/mongodb/creds"
  
  tags = {
    Environment = "prod"
  }
}
```

**MongoDB Structure Hierarchy:**
```
Cluster (MongoDB Atlas infrastructure)
└── Database 1 (e.g., "appdb")
    ├── Collection A (e.g., "users")
    ├── Collection B (e.g., "orders")
    └── Collection C (e.g., "products")
└── Database 2 (e.g., "analytics")
    ├── Collection D (e.g., "metrics")
    └── Collection E (e.g., "logs")
```

**Understanding "Database" vs "Collection":**
- **Database**: Top-level container within a cluster (e.g., "appdb", "analytics")
- **Collection**: Container for documents within a database (like a table in SQL)
- **Role scope**: Some roles grant access to a specific database, others to all databases

**Database User Configuration:**
- `db_username`: The username (what you see in Atlas UI)
- `db_user_database`: Which database the user has permissions on (e.g., "appdb")
  - Use your app's database name for specific permissions
  - Use "admin" with role "readWriteAnyDatabase" or "atlasAdmin" for admin-like access
- `db_user_role`: Permission level on that database (see table below)

**Common MongoDB Atlas Roles:**

| Role | Database | Permissions | Can Create DBs? | Use Case |
|------|----------|-------------|-----------------|----------|
| `readWrite` | Specific (e.g., `appdb`) | Read/write in that database only | Only that DB (auto-created) | **Application users (recommended)** |
| `read` | Specific (e.g., `appdb`) | Read-only in that database | No | Read-only access, reporting |
| `readWriteAnyDatabase` | `admin` | Read/write **all databases** | Yes | Multi-database apps, migration tools |
| `dbAdmin` | Specific | Admin operations on that database | Only that DB | Database maintenance |
| `dbAdminAnyDatabase` | `admin` | Admin operations on **all databases** | Yes | DBA operations |
| `atlasAdmin` | `admin` | **Full cluster access (superuser)** | Yes | **Admin only - full control** |

**Recommended configurations:**

1. **Application user (most common):**
   ```hcl
  db_user_database = "appdb"        # Your app's database
   db_user_role     = "readWrite"     # Can read and write
   ```

2. **Read-only analytics/reporting:**
   ```hcl
  db_user_database = "appdb"
   db_user_role     = "read"          # Read-only
   ```

3. **Admin user (use sparingly):**
   ```hcl
   db_user_database = "admin"
   db_user_role     = "atlasAdmin"    # Full cluster access
   ```

**Security Note:** The password is stored in Terraform state. Ensure your state backend is encrypted (S3 with KMS).

**AWS Secrets Manager Secret Structure (Database User Credentials):**

When `create_user = true`, the module automatically creates a secret in AWS Secrets Manager with the following JSON structure:

```json
{
  "username": "atlas-demo-app",
  "password": "auto-generated-secure-password",
  "connection_string": "mongodb://atlas-demo-app:password@cluster0-shard-00-00.xxxxx.mongodb.net:27017,cluster0-shard-00-01.xxxxx.mongodb.net:27017,cluster0-shard-00-02.xxxxx.mongodb.net:27017/?ssl=true&replicaSet=atlas-xxxxx-shard-0&authSource=admin&retryWrites=true&w=majority",
  "connection_string_private": "mongodb://atlas-demo-app:password@cluster0-shard-00-00-pl-0.xxxxx.mongodb.net:27017,cluster0-shard-00-01-pl-0.xxxxx.mongodb.net:27017,cluster0-shard-00-02-pl-0.xxxxx.mongodb.net:27017/?ssl=true&replicaSet=atlas-xxxxx-shard-0&authSource=admin&retryWrites=true&w=majority",
  "database": "appdb",
  "cluster_name": "Cluster0",
  "project_id": "0123456789abcdef01234567"
}
```

### Add AWS Routes for Peering (in network.tf)

```hcl
resource "aws_route" "to_atlas_mongodb" {
  for_each = var.mongodbatlas_enable_vpc_peering ? local.all_route_table_ids : toset([])

  route_table_id            = each.value
  destination_cidr_block    = module.mongodb_atlas.atlas_vpc_cidr
  vpc_peering_connection_id = module.mongodb_atlas.peering_connection_id
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `org_id` | MongoDB Atlas Organization ID | string | - | yes |
| `project_name` | MongoDB Atlas Project Name | string | - | yes |
| `cluster_name` | MongoDB Atlas Cluster Name | string | "Cluster0" | no |
| `instance_size` | Instance size (M0, M10, M20, etc.) | string | "M0" | no |
| `mongodb_version` | MongoDB version | string | "8.0" | no |
| `region` | MongoDB Atlas region | string | - | yes |
| `enable_vpc_peering` | Enable VPC peering (M10+ only) | bool | false | no |
| `aws_vpc_id` | AWS VPC ID to peer with | string | null | no |
| `atlas_cidr_block` | CIDR for Atlas VPC | string | "10.8.0.0/21" | no |
| `ip_access_list` | IP/CIDR access rules | list(object) | [] | no |

---

## Outputs

| Name | Description |
|------|-------------|
| `project_id` | MongoDB Atlas Project ID |
| `cluster_id` | MongoDB Atlas Cluster ID |
| `connection_string_standard` | Public connection string |
| `connection_string_private` | Private connection string (VPC peering) |
| `mongodb_server_list` | Server hostnames (auto-selects private/public) |
| `peering_connection_id` | VPC peering connection ID |
| `atlas_vpc_cidr` | MongoDB Atlas VPC CIDR |

---

## Important Considerations

### VPC Peering

* **Only available for M10+ dedicated clusters**
* Not supported on M0/M2/M5 free/shared tiers
* Requires non-overlapping CIDR blocks
* Automatically accepted on AWS side
* Routes must be added to AWS route tables later using the peering output ID (see example above)

### CIDR Block Planning

Ensure the `atlas_cidr_block` does NOT overlap with:
* Your AWS VPC CIDR
* Other peered VPCs
* On-premises networks

Common Atlas CIDR choices:
* `10.8.0.0/21` (default)
* `192.168.240.0/21`
* `172.16.0.0/21`

### Connection Strings

The module automatically selects the appropriate connection string:
* **M0 or peering disabled**: Uses public connection string
* **M10+ with VPC peering**: Uses private connection string (via peering)

The `mongodb_server_list` output handles this automatically for your applications.

### Free Tier (M0) Limitations

* 512MB storage (fixed)
* No backups
* No auto-scaling
* No VPC peering
* Shared infrastructure

---

## Troubleshooting

### "Peering connections will only apply to dedicated-tier clusters"

You're trying to enable VPC peering on M0/M2/M5. Solution:
* Set `enable_vpc_peering = false`, OR
* Upgrade to M10 or higher (`instance_size = "M10"`)

### Provider Authentication Failed

Check your AWS Secrets Manager secret contains valid Atlas API keys with correct permissions (`Organization Project Creator`).

