##############################################################################
# VPC Module - Network Foundation
#
# Two public subnets (multi-AZ) + one Internet Gateway.
#
#   VPC
#   ├── Internet Gateway
#   └── Public subnets   [AZa, AZb, ...]  -> route 0/0 via IGW
#         public[0]  hosts the EC2 + EIP
#         public[1..] reserved for a future ALB (needs >= 2 AZs)
#
# The private subnet + private route table + private route table association
# are currently COMMENTED OUT — this project does not need them. The code
# stays in the file so you can re-enable in one edit when a private-only
# workload (RDS, ElastiCache, worker nodes) actually needs a home.
##############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

##############################################################################
# VPC + Internet Gateway
##############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-${var.environment}"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw-${var.environment}"
  })
}

##############################################################################
# Public subnets - one per (cidr, az) pair. Count driven by the list length.
##############################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.public_availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}-${var.environment}"
    Tier = "public"
    AZ   = var.public_availability_zones[count.index]
  })
}

# Shared public route table + default route to the IGW. All public subnets
# associate with this one table (they share the same routing policy).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt-${var.environment}"
    Tier = "public"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

##############################################################################
# Private subnet - DISABLED
#
# Uncomment the block below (and the matching bits in variables.tf,
# outputs.tf, and the root main.tf/variables.tf/outputs.tf) when you need
# a private tier for RDS/ElastiCache/workers. Add a NAT gateway or S3/ECR
# VPC endpoints if that workload needs outbound internet.
##############################################################################

/*
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.private_availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-subnet-${var.environment}"
    Tier = "private"
    AZ   = var.private_availability_zone
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-rt-${var.environment}"
    Tier = "private"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
*/
