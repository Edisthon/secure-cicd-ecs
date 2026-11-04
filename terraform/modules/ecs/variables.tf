variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "tasks_sg_id" { type = string }
variable "container_port" {
  type    = number
  default = 8080
}
variable "log_retention_days" {
  type    = number
  default = 14
}
variable "bootstrap_image" {
  description = "Placeholder image for the initial task definition (never started: desired_count = 0)."
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:stable"
}
