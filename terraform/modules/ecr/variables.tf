variable "name" { type = string }
variable "keep_images" {
  description = "Tagged images to retain. Keep this >= the task-definition revisions kept by scripts/ecs-cleanup.sh."
  type        = number
  default     = 10
}
variable "force_delete" {
  type    = bool
  default = true # lab convenience so `terraform destroy` works with images present
}
