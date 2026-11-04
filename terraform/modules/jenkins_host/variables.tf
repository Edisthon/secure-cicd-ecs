variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "instance_profile_name" { type = string }
variable "allowed_cidrs" { type = list(string) }
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/jenkins-keypair.pub"
}
variable "instance_type" {
  description = "SonarQube alone needs ~4 GB RAM, so t3.large (8 GB) is the minimum that is comfortable."
  type        = string
  default     = "t3.large"
}
variable "volume_size_gb" {
  type    = number
  default = 40
}

variable "encrypt_root_volume" {
  description = "Encrypt the root EBS volume. Set false if the account's SCPs block KMS use for EBS (the instance then terminates right after launch)."
  type        = bool
  default     = false
}
