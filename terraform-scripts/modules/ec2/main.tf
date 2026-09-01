##############################################################################
# EC2 Module - Application Instance
#
# One Ubuntu 24.04 instance in the PUBLIC subnet, optionally fronted by an
# Elastic IP. At boot, user_data.sh installs Nginx, Node.js LTS and PM2, and
# lays down a placeholder Nginx site (which upload-app.sh replaces with the
# real reverse-proxy config after the app is uploaded).
#
# IMDSv2 is required (http_tokens = required) and the root EBS volume is
# encrypted - both are cheap security wins that belong on by default.
##############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

##############################################################################
# EC2 Instance
##############################################################################

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    node_version = var.node_version
    aws_region   = var.aws_region
    project_name = var.project_name
    environment  = var.environment
  }))

  # Re-run user_data if it changes (Terraform will replace the instance).
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.project_name}-app-root-${var.environment}"
    })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  monitoring = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-${var.environment}"
    Tier = "public"
  })

  lifecycle {
    # Prevent AMI drift from rotating the instance on every plan when AWS
    # publishes a new Ubuntu image mid-week. Bump ami_id deliberately.
    ignore_changes = [ami]
  }
}

##############################################################################
# Elastic IP (optional but on by default)
##############################################################################

resource "aws_eip" "app" {
  count = var.attach_elastic_ip ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.app.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-eip-${var.environment}"
  })
}
