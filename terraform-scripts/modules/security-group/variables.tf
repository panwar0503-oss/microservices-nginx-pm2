##############################################################################
# Security Group Module - Input Variables
##############################################################################

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC in which to create the security groups"
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to reach port 22 (your public IP as /32)"

  validation {
    condition     = can(cidrhost(var.ssh_cidr, 0)) && var.ssh_cidr != "0.0.0.0/0"
    error_message = "ssh_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "http_enabled" {
  type        = bool
  default     = true
  description = "Whether to open 80 and 443 to 0.0.0.0/0"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to every resource in this module"
}
