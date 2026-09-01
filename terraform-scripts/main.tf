##############################################################################
# Root Terraform Configuration
#
# Composes the infrastructure for microservices-nginx-pm2:
#
#   VPC (10.20.0.0/16)
#   ├── Internet Gateway
#   ├── Public  subnet #1  10.20.1.0/24   (AZ a)  -> EC2 + EIP + Nginx
#   └── Public  subnet #2  10.20.2.0/24   (AZ b)  -> reserved for future ALB
#
#   (private subnet + internal-sg intentionally not created — see the
#    commented-out blocks in modules/vpc and modules/security-group.)
#
#   Security group:
#     app-sg  - attached to the EC2, allows 22/80/443 from restricted CIDRs
#
# The EC2 instance boots with a user_data.sh that installs Nginx, Node.js LTS
# and PM2, drops in a placeholder Nginx site and wires pm2-systemd startup.
# Application code is uploaded post-boot via deploy/scripts/upload-app.sh.
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Team        = "DevOps"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

##############################################################################
# Ubuntu 24.04 AMI (Canonical) - resolved fresh per plan
##############################################################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

##############################################################################
# VPC Module - 2 public subnets (multi-AZ) + IGW
##############################################################################

module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs

  # One AZ per public subnet. slice() truncates the AZ list to match the
  # number of public CIDRs, so adding a 3rd CIDR "just works" without
  # editing this file.
  public_availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    length(var.public_subnet_cidrs),
  )

  tags = var.tags
}

##############################################################################
# Security Group Module - app-sg (public) + internal-sg (private)
##############################################################################

module "security_group" {
  source = "./modules/security-group"

  project_name = var.project_name
  environment  = var.environment

  vpc_id       = module.vpc.vpc_id
  ssh_cidr     = var.ssh_cidr
  http_enabled = var.http_enabled

  tags = var.tags

  depends_on = [module.vpc]
}

##############################################################################
# Key Pair Module - generates RSA locally and registers with AWS
##############################################################################

module "key_pair" {
  source = "./modules/key-pair"

  project_name = var.project_name
  environment  = var.environment

  tags = var.tags
}

##############################################################################
# EC2 Module - runs in the FIRST public subnet, gets an Elastic IP
##############################################################################

module "ec2" {
  source = "./modules/ec2"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  ami_id             = data.aws_ami.ubuntu.id
  instance_type      = var.instance_type
  subnet_id          = module.vpc.app_subnet_id
  security_group_ids = [module.security_group.app_security_group_id]
  key_name           = module.key_pair.key_pair_name

  root_volume_size  = var.root_volume_size
  node_version      = var.node_version
  attach_elastic_ip = var.attach_elastic_ip

  tags = var.tags

  depends_on = [module.vpc, module.security_group, module.key_pair]
}
