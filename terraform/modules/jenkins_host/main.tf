# Jenkins + SonarQube host (replaces the Mod7 Jenkins instance in a fresh account).
# Built to match what the pipeline needs: 8 GB RAM, 40 GB disk, IAM role (no keys), IMDS hop limit 2,
# a fixed Elastic IP, and Docker + docker-compose installed at first boot.

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "jenkins" {
  key_name   = "${var.name}-jenkins"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "jenkins" {
  name        = "${var.name}-jenkins-sg"
  description = "Jenkins host: SSH and Jenkins UI from allowed CIDRs only"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  egress {
    description = "Updates, Docker Hub, GitHub, AWS APIs, scanner databases"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "jenkins" {
  domain = "vpc"
  tags   = { Name = "${var.name}-jenkins" }
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  key_name                    = aws_key_pair.jenkins.key_name
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.volume_size_gb
    volume_type = "gp3"
    encrypted             = var.encrypt_root_volume
  }

  # Jenkins runs in a container: hop limit 2 lets the AWS CLI inside it reach the instance role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    curl -fsSL https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    mkdir -p /var/jenkins_home
  EOT

  tags = { Name = "${var.name}-jenkins" }

  lifecycle { ignore_changes = [ami, user_data] }
}

resource "aws_eip_association" "jenkins" {
  instance_id   = aws_instance.jenkins.id
  allocation_id = aws_eip.jenkins.id
}
