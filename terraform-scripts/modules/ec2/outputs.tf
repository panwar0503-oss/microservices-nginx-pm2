##############################################################################
# EC2 Module - Outputs
##############################################################################

output "instance_id" {
  value       = aws_instance.app.id
  description = "EC2 instance ID"
}

output "instance_arn" {
  value       = aws_instance.app.arn
  description = "EC2 instance ARN"
}

output "private_ip" {
  value       = aws_instance.app.private_ip
  description = "Private IP inside the VPC"
}

output "public_ip" {
  value       = var.attach_elastic_ip ? aws_eip.app[0].public_ip : aws_instance.app.public_ip
  description = "Public IP - Elastic IP if attach_elastic_ip is true, else ephemeral"
}

output "eip_allocation_id" {
  value       = var.attach_elastic_ip ? aws_eip.app[0].id : ""
  description = "Elastic IP allocation ID (empty when EIP not attached)"
}
