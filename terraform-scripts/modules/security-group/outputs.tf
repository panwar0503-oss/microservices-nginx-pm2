##############################################################################
# Security Group Module - Outputs
##############################################################################

output "app_security_group_id" {
  value       = aws_security_group.app.id
  description = "SG attached to the EC2 instance (public-facing)"
}

output "app_security_group_arn" {
  value       = aws_security_group.app.arn
  description = "ARN of the app SG"
}

##############################################################################
# Internal SG outputs - DISABLED (see main.tf)
##############################################################################

/*
output "internal_security_group_id" {
  value       = aws_security_group.internal.id
  description = "SG intended for future private-subnet workloads"
}

output "internal_security_group_arn" {
  value       = aws_security_group.internal.arn
  description = "ARN of the internal SG"
}
*/
