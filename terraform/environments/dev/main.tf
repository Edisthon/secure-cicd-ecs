terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }

  # Local state by default. For team use, switch to the S3 + DynamoDB backend from Mod7:
  # backend "s3" {
  #   bucket         = "<state-bucket>"
  #   key            = "mod9/secure-cicd/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "<lock-table>"
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "secure-cicd-ecs", Lab = "Mod9", ManagedBy = "terraform" }
  }
}

locals { name = "secure-cicd" }

module "network" {
  source                = "../../modules/network"
  name                  = local.name
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
}

module "ecr" {
  source      = "../../modules/ecr"
  name        = "secure-cicd-app"
  keep_images = 10
}

module "ecs" {
  source      = "../../modules/ecs"
  name        = "secure-cicd" # -> cluster secure-cicd-cluster, service secure-cicd-service, roles secure-cicd-task[-execution]
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.public_subnet_ids
  alb_sg_id   = module.network.alb_sg_id
  tasks_sg_id = module.network.tasks_sg_id
}

module "monitoring" {
  source                  = "../../modules/monitoring"
  name                    = local.name
  region                  = var.region
  alert_email             = var.alert_email
  cluster_name            = module.ecs.cluster_name
  service_name            = module.ecs.service_name
  service_arn             = module.ecs.service_arn
  log_group_name          = module.ecs.log_group_name
  alb_arn_suffix          = module.ecs.alb_arn_suffix
  target_group_arn_suffix = module.ecs.target_group_arn_suffix
  desired_count           = 2
}

module "jenkins_access" {
  source             = "../../modules/jenkins_access"
  name               = local.name
  ecr_repository_arn = module.ecr.repository_arn
  cluster_name       = module.ecs.cluster_name
  execution_role_arn = module.ecs.execution_role_arn
  task_role_arn      = module.ecs.task_role_arn
  jenkins_role_name  = var.jenkins_role_name
}

# ---- Jenkins + SonarQube host (fixed IP, sized for the pipeline) ----
module "jenkins_host" {
  source                = "../../modules/jenkins_host"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.public_subnet_ids[0]
  instance_profile_name = module.jenkins_access.instance_profile_name
  allowed_cidrs         = var.allowed_ingress_cidrs
  ssh_public_key_path   = var.ssh_public_key_path
}

# The pipeline's verify step curls the ALB FROM the Jenkins host, so allow its (fixed) IP on the ALB.
resource "aws_vpc_security_group_ingress_rule" "alb_from_jenkins" {
  security_group_id = module.network.alb_sg_id
  description       = "HTTP from the Jenkins host (deployment verification)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "${module.jenkins_host.public_ip}/32"
}

# Inventory for ansible/site.yml, so there is nothing to type by hand.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory.generated.ini"
  file_permission = "0644"
  content         = <<-EOT
    [jenkins_servers]
    jenkins ansible_host=${module.jenkins_host.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${var.ssh_private_key_path}
  EOT
}
