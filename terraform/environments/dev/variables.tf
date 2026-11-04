variable "region" {
  type    = string
  default = "eu-west-1"
}
variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB. Use your own IP/32 for the lab."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
variable "alert_email" {
  description = "Email for alarm + deployment notifications ('' to skip). Confirm the SNS subscription email."
  type        = string
  default     = ""
}
variable "jenkins_role_name" {
  description = "Jenkins EC2 instance role to attach the deploy policy to ('' = create the policy only)."
  type        = string
  default     = ""
}
variable "ssh_public_key_path" {
  description = "Public key installed on the Jenkins host."
  type        = string
  default     = "~/.ssh/jenkins-keypair.pub"
}
variable "ssh_private_key_path" {
  description = "Private key Ansible uses to reach the Jenkins host (keep it in the WSL home, not under /mnt/c)."
  type        = string
  default     = "~/.ssh/jenkins-keypair"
}
