##############################################################################
# Key Pair Module - Outputs
##############################################################################

output "key_pair_name" {
  value       = aws_key_pair.this.key_name
  description = "AWS key pair name"
}

output "key_pair_id" {
  value       = aws_key_pair.this.key_pair_id
  description = "AWS key pair ID"
}

output "private_key_path" {
  value       = local.generate_key ? local_sensitive_file.private_key[0].filename : ""
  description = "Local .pem path (empty string when existing_public_key was supplied)"
}
