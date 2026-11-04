variable "name" { type = string }
variable "ecr_repository_arn" { type = string }
variable "cluster_name" { type = string }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "jenkins_role_name" {
  description = "Name of the Jenkins EC2 instance role to attach the policy to ('' = just create the policy)."
  type        = string
  default     = ""
}
