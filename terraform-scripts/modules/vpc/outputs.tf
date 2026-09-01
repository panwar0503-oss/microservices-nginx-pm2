##############################################################################
# VPC Module - Outputs
##############################################################################

output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = aws_vpc.this.cidr_block
  description = "CIDR block of the VPC"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.this.id
  description = "Internet gateway ID"
}

##############################################################################
# Public subnets (list)
##############################################################################

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs of every public subnet, in the same order as public_subnet_cidrs"
}

output "public_subnet_cidrs" {
  value       = aws_subnet.public[*].cidr_block
  description = "CIDRs of every public subnet"
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "Shared public route table ID"
}

##############################################################################
# Convenience: the specific public subnet the app EC2 lives in
##############################################################################

output "app_subnet_id" {
  value       = aws_subnet.public[0].id
  description = "Public subnet ID the EC2 instance runs in (first public subnet)"
}

##############################################################################
# Private subnet outputs - DISABLED (see modules/vpc/main.tf)
##############################################################################

/*
output "private_subnet_id" {
  value       = aws_subnet.private.id
  description = "Private subnet ID"
}

output "private_subnet_cidr" {
  value       = aws_subnet.private.cidr_block
  description = "CIDR of the private subnet"
}

output "private_route_table_id" {
  value       = aws_route_table.private.id
  description = "Private route table ID"
}
*/
