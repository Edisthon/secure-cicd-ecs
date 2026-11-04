output "policy_arn" { value = aws_iam_policy.jenkins.arn }
output "instance_profile_name" {
  description = "Associate this with the Jenkins EC2 instance (empty when an existing role was supplied)."
  value       = var.jenkins_role_name == "" ? aws_iam_instance_profile.jenkins[0].name : ""
}
