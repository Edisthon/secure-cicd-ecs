variable "name" { type = string }
variable "region" { type = string }
variable "alert_email" {
  type    = string
  default = ""
}
variable "cluster_name" { type = string }
variable "service_name" { type = string }
variable "service_arn" { type = string }
variable "log_group_name" { type = string }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "desired_count" {
  type    = number
  default = 2
}
