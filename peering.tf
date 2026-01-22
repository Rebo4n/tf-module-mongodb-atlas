# AWS VPC Peering Accepter - Accept the peering connection from MongoDB Atlas
resource "aws_vpc_peering_connection_accepter" "atlas" {
  count = var.enable_vpc_peering ? 1 : 0

  vpc_peering_connection_id = mongodbatlas_network_peering.this[0].connection_id
  auto_accept               = true

  tags = merge(
    var.tags,
    {
      Name = "mongodb-atlas-peering"
      Side = "Accepter"
    }
  )
}
