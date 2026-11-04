variable "name" { type = string }
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "container_port" {
  type    = number
  default = 8080
}
variable "allowed_ingress_cidrs" {
  description = "Who may reach the ALB on :80. Restrict this to your IP/CIDR for the lab."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
