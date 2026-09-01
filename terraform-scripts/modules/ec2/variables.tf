##############################################################################
# EC2 Module - Input Variables
##############################################################################

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "aws_region" {
  type        = string
  description = "AWS region (passed to user_data for logging/awareness)"
}

variable "ami_id" {
  type        = string
  description = "AMI ID (Ubuntu 24.04) - resolve via data.aws_ami in the caller"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

variable "subnet_id" {
  type        = string
  description = "Subnet in which to launch the instance (public subnet)"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs to attach to the instance"
}

variable "key_name" {
  type        = string
  description = "AWS key pair name to associate with the instance"
}

variable "root_volume_size" {
  type        = number
  default     = 12
  description = "Root EBS volume size in GB"
}

variable "node_version" {
  type        = string
  default     = "20"
  description = "Node.js major version installed via NodeSource"
}

variable "attach_elastic_ip" {
  type        = bool
  default     = true
  description = "If true, allocate an Elastic IP and associate it with the instance"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags applied to every resource in this module"
}
