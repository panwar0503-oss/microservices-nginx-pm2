##############################################################################
# environments/prod.tfvars
#
# Production - a step up from dev (more RAM headroom for PM2 cluster mode)
# and a wider CIDR range. Layout: 2 public subnets (multi-AZ) + 1 private
# subnet. No NAT gateway.
# Select with: terraform plan -var-file=environments/prod.tfvars
##############################################################################

project_name = "microservices"
environment  = "prod"

aws_profile = "aws-dharmendra"
aws_region  = "ap-south-1"

# --- Networking ---
vpc_cidr            = "10.30.0.0/16"
public_subnet_cidrs = ["10.30.1.0/24", "10.30.2.0/24"] # AZa, AZb
# private_subnet_cidr = "10.30.10.0/24"  # disabled — see modules/vpc/main.tf

# --- Security ---
# CHANGE THIS to your public IP as /32 before running plan/apply.
ssh_cidr     = "0.0.0.0/32"
http_enabled = true

# --- EC2 ---
instance_type     = "t3.small" # 2 GB RAM - room for PM2 cluster + Nginx + kernel
root_volume_size  = 20
node_version      = "20"
attach_elastic_ip = true

# --- Tags ---
tags = {
  Project     = "Microservices"
  Environment = "Prod"
  Team        = "DevOps"
  ManagedBy   = "Terraform"
  CostCenter  = "Product"
  Purpose     = "Production"
}
