##############################################################################
# environments/dev.tfvars
#
# Development environment - cheap, one t3.micro.
# Layout: 2 public subnets (multi-AZ) + 1 private subnet. No NAT gateway.
# Select with: terraform plan -var-file=environments/dev.tfvars
##############################################################################

project_name = "microservices"
environment  = "dev"

aws_profile = "aws-dharmendra"
aws_region  = "ap-south-1"

# --- Networking ---
vpc_cidr            = "10.20.0.0/16"
public_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24"] # AZa, AZb
# private_subnet_cidr = "10.20.10.0/24"  # disabled — see modules/vpc/main.tf

# --- Security ---
# CHANGE THIS to your public IP as /32 before running plan/apply.
# Find it with: curl -s https://checkip.amazonaws.com
ssh_cidr     = "0.0.0.0/32"
http_enabled = true

# --- EC2 ---
instance_type     = "t3.micro"
root_volume_size  = 12
node_version      = "20"
attach_elastic_ip = true

# --- Tags ---
tags = {
  Project     = "Microservices"
  Environment = "Dev"
  Team        = "DevOps"
  ManagedBy   = "Terraform"
  CostCenter  = "Learning"
  Purpose     = "Development"
}
