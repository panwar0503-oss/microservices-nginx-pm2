##############################################################################
# VPC Module - Input Variables
##############################################################################

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for the public subnets. Length must match public_availability_zones."

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Provide at least 2 public subnet CIDRs (multi-AZ layout expected)."
  }
}

variable "public_availability_zones" {
  type        = list(string)
  description = "AZs for the public subnets (one per CIDR). Length must match public_subnet_cidrs."

  validation {
    condition     = length(var.public_availability_zones) >= 2
    error_message = "Provide at least 2 AZs for the public subnets."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to every resource in this module"
}

##############################################################################
# Private subnet variables - DISABLED (see modules/vpc/main.tf)
#
# Uncomment together with the resource blocks in main.tf and outputs.tf when
# you need a private tier.
##############################################################################

/*
variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the single private subnet"
}

variable "private_availability_zone" {
  type        = string
  description = "AZ in which to place the private subnet"
}
*/
