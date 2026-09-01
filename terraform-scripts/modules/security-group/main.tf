##############################################################################
# Security Group Module
#
# One security group is created:
#
#   app_sg - attached to the EC2 instance in the public subnet.
#       INGRESS 22    tcp  ssh_cidr        (SSH restricted to caller's IP)
#       INGRESS 80    tcp  0.0.0.0/0       (HTTP  to Nginx)  - if http_enabled
#       INGRESS 443   tcp  0.0.0.0/0       (HTTPS to Nginx)  - if http_enabled
#       EGRESS  all   any  0.0.0.0/0
#
# The internal_sg (for future private-subnet workloads) is COMMENTED OUT
# below - re-enable it together with the private subnet in modules/vpc when
# you actually add something to a private tier.
#
# Application ports 3001/3002/3003 are NEVER exposed - the microservices bind
# to 127.0.0.1 and only Nginx (same host) reaches them.
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
# Application SG (public-facing)
##############################################################################

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg-${var.environment}"
  description = "Public-facing SG for the microservices EC2 (SSH from operator, HTTP/HTTPS to Nginx)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-sg-${var.environment}"
    Tier = "public"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH from operator"
  cidr_ipv4         = var.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-sg-ssh-${var.environment}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  count = var.http_enabled ? 1 : 0

  security_group_id = aws_security_group.app.id
  description       = "HTTP to Nginx"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-sg-http-${var.environment}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  count = var.http_enabled ? 1 : 0

  security_group_id = aws_security_group.app.id
  description       = "HTTPS to Nginx"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-sg-https-${var.environment}"
  })
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(var.tags, {
    Name = "${var.project_name}-app-sg-egress-${var.environment}"
  })
}

##############################################################################
# Internal SG - DISABLED
#
# Only exists to protect private-subnet workloads (DB, cache, workers).
# The private subnet is not created in this project, so this SG has no
# purpose right now. Re-enable together with the private subnet in
# modules/vpc when you actually add a private-tier workload.
##############################################################################

/*
resource "aws_security_group" "internal" {
  name        = "${var.project_name}-internal-sg-${var.environment}"
  description = "Private-subnet SG - accepts traffic only from app SG"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-internal-sg-${var.environment}"
    Tier = "private"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "internal_from_app" {
  security_group_id            = aws_security_group.internal.id
  description                  = "All TCP from app SG"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535

  tags = merge(var.tags, {
    Name = "${var.project_name}-internal-sg-from-app-${var.environment}"
  })
}

resource "aws_vpc_security_group_egress_rule" "internal_all" {
  security_group_id = aws_security_group.internal.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(var.tags, {
    Name = "${var.project_name}-internal-sg-egress-${var.environment}"
  })
}
*/
