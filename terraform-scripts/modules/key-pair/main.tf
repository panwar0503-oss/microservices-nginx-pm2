##############################################################################
# Key Pair Module
#
# Generates an RSA 4096 key pair, registers the public half in AWS as an
# EC2 key pair, and writes the private half to the local filesystem at
# ../keys/<project>-<env>-key.pem with 0400 permissions.
#
# For a shared/team deploy prefer importing an existing key instead - see
# the `existing_public_key` variable.
##############################################################################

terraform {
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

locals {
  key_name          = "${var.project_name}-${var.environment}-key"
  generate_key      = var.existing_public_key == ""
  effective_pub_key = local.generate_key ? tls_private_key.this[0].public_key_openssh : var.existing_public_key
  keys_dir          = "${path.root}/keys"
  private_key_path  = "${local.keys_dir}/${local.key_name}.pem"
}

##############################################################################
# Local RSA key generation (only if no existing public key was provided)
##############################################################################

resource "tls_private_key" "this" {
  count = local.generate_key ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  count = local.generate_key ? 1 : 0

  content              = tls_private_key.this[0].private_key_pem
  filename             = local.private_key_path
  directory_permission = "0700"

  # 0600 (owner read+write) instead of 0400 so a future `terraform apply`
  # can overwrite this file. SSH still accepts 0600 for private keys - it
  # only rejects group/other-readable keys. If we used 0400 here, the file
  # would end up with no write bit and any re-apply (or key rotation) would
  # fail with "permission denied".
  file_permission = "0600"
}

##############################################################################
# AWS EC2 key pair
##############################################################################

resource "aws_key_pair" "this" {
  key_name   = local.key_name
  public_key = local.effective_pub_key

  tags = merge(var.tags, {
    Name = local.key_name
  })
}
