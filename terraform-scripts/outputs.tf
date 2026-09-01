##############################################################################
# Root Outputs
#
# Everything a caller needs to (a) SSH in, (b) hit the app publicly, and
# (c) understand what was created. Most values are re-exported from modules.
##############################################################################

##############################################################################
# Networking
##############################################################################

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = module.vpc.vpc_cidr
  description = "VPC CIDR block"
}

output "internet_gateway_id" {
  value       = module.vpc.internet_gateway_id
  description = "Internet gateway ID"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "IDs of every public subnet (multi-AZ)"
}

output "app_subnet_id" {
  value       = module.vpc.app_subnet_id
  description = "Public subnet the EC2 runs in (first public subnet)"
}

# Private subnet not created — see modules/vpc/main.tf for the commented-out block.
# output "private_subnet_id" {
#   value       = module.vpc.private_subnet_id
#   description = "Private subnet ID"
# }

##############################################################################
# Security
##############################################################################

output "app_security_group_id" {
  value       = module.security_group.app_security_group_id
  description = "SG attached to the EC2 (public-facing: 22/80/443)"
}

# internal-sg not created — see modules/security-group/main.tf.
# output "internal_security_group_id" {
#   value       = module.security_group.internal_security_group_id
#   description = "SG intended for future private-subnet workloads"
# }

output "key_pair_name" {
  value       = module.key_pair.key_pair_name
  description = "AWS key pair name"
}

output "private_key_path" {
  value       = module.key_pair.private_key_path
  description = "Local path to the generated .pem private key (chmod 0400)"
}

##############################################################################
# Compute
##############################################################################

output "instance_id" {
  value       = module.ec2.instance_id
  description = "EC2 instance ID"
}

output "instance_public_ip" {
  value       = module.ec2.public_ip
  description = "Public IP of the instance (Elastic IP if attach_elastic_ip is true)"
}

output "instance_private_ip" {
  value       = module.ec2.private_ip
  description = "Private IP of the instance inside the VPC"
}

##############################################################################
# Convenience - copy-paste ready
##############################################################################

output "ssh_command" {
  value       = "ssh -i ${module.key_pair.private_key_path} ubuntu@${module.ec2.public_ip}"
  description = "Ready-to-run SSH command"
}

output "app_urls" {
  value = {
    users    = "http://${module.ec2.public_ip}/api/users/health"
    products = "http://${module.ec2.public_ip}/api/products/health"
    orders   = "http://${module.ec2.public_ip}/api/orders/health"
    root     = "http://${module.ec2.public_ip}/"
  }
  description = "Curl-ready URLs to verify each service through Nginx"
}

output "infrastructure_summary" {
  value = {
    project           = var.project_name
    environment       = var.environment
    region            = var.aws_region
    vpc_id            = module.vpc.vpc_id
    public_subnet_ids = module.vpc.public_subnet_ids
    instance_id       = module.ec2.instance_id
    public_ip         = module.ec2.public_ip
    key_pair          = module.key_pair.key_pair_name
  }
  description = "One-glance summary of what was deployed"
}
