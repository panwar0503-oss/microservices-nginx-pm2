##############################################################################
# Root Variables
#
# Grouped by concern. Order per variable: type -> default -> description
# -> validation. Environment-specific values live in environments/<env>.tfvars.
##############################################################################

##############################################################################
# Project and Environment
##############################################################################

variable "project_name" {
  type        = string
  default     = "microservices"
  description = "Project name used for resource naming and tagging"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_profile" {
  type        = string
  default     = "aws-dharmendra"
  description = "AWS CLI named profile used by the provider (override with TF_VAR_aws_profile)"
}

variable "aws_region" {
  type        = string
  default     = "ap-south-1"
  description = "AWS region for resource deployment"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to all resources (merged with provider default_tags)"
}

##############################################################################
# Networking
##############################################################################

variable "vpc_cidr" {
  type        = string
  default     = "10.20.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
  description = "CIDRs for the public subnets, one per AZ (list length drives how many subnets get created — must be >= 2)"

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Provide at least 2 public subnet CIDRs (this project expects a multi-AZ public tier)."
  }
}

##############################################################################
# Private subnet variables - DISABLED
#
# The private subnet is not created in this project. Uncomment together
# with the resource blocks in modules/vpc when you need a private tier.
##############################################################################

/*
variable "private_subnet_cidr" {
  type        = string
  default     = "10.20.10.0/24"
  description = "CIDR block for the single private subnet"

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr must be a valid CIDR block."
  }
}
*/

##############################################################################
# Security Group
##############################################################################

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH into the instance (your public IP as x.x.x.x/32). No default - must be set."

  validation {
    condition     = can(cidrhost(var.ssh_cidr, 0)) && var.ssh_cidr != "0.0.0.0/0"
    error_message = "ssh_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "http_enabled" {
  type        = bool
  default     = true
  description = "If true, open ports 80 and 443 to 0.0.0.0/0 for Nginx"
}

##############################################################################
# EC2 Instance
##############################################################################

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type (t3.micro for dev, t3.small+ for prod cluster-mode headroom)"
}

variable "root_volume_size" {
  type        = number
  default     = 12
  description = "Root EBS volume size in GB (gp3)"

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "root_volume_size must be between 8 and 100 GB."
  }
}

variable "node_version" {
  type        = string
  default     = "20"
  description = "Node.js major version to install from NodeSource (e.g. 20 for Node 20.x LTS)"

  validation {
    condition     = contains(["18", "20", "22"], var.node_version)
    error_message = "node_version must be one of: 18, 20, 22."
  }
}

variable "attach_elastic_ip" {
  type        = bool
  default     = true
  description = "If true, allocate an Elastic IP and associate it with the instance so the public IP survives stop/start"
}
