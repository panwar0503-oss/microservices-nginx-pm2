##############################################################################
# Key Pair Module - Input Variables
##############################################################################

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "existing_public_key" {
  type        = string
  default     = ""
  description = "If set (OpenSSH format), import this public key instead of generating one. Empty string generates a fresh RSA 4096 key locally."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to every resource in this module"
}
