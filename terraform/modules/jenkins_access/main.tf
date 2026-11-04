# Least-privilege policy for the Jenkins controller's INSTANCE ROLE (no long-lived keys in Jenkins).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages", "ecr:DescribeImageScanFindings", "ecr:ListImages",
    ]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid = "EcsTaskDefinitions" # these APIs do not support resource-level permissions
    actions = [
      "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DeleteTaskDefinitions",
      "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "TagTaskDefinitionRevisions" # RegisterTaskDefinition with "tags" in the template needs this
    actions   = ["ecs:TagResource"]
    resources = ["arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.name}-app:*"]
  }
  statement {
    sid       = "EcsService"
    actions   = ["ecs:UpdateService"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
    }
  }
  statement {
    sid       = "EcsDescribeNoCondition"
    actions   = ["ecs:DescribeServices", "ecs:ListTasks", "ecs:DescribeTasks"]
    resources = ["*"]
  }
  statement {
    sid       = "PassOnlyTheTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.execution_role_arn, var.task_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadForVerification"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers", "cloudwatch:DescribeAlarms", "logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "jenkins" {
  name   = "${var.name}-jenkins-deploy"
  policy = data.aws_iam_policy_document.jenkins.json
}

# The Mod7 Jenkins instance has no IAM role. When jenkins_role_name is empty we create one (plus its
# instance profile) that you then associate with the Jenkins EC2 instance (see README step 3).
# When jenkins_role_name is set, the policy is attached to that existing role instead.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  count              = var.jenkins_role_name == "" ? 1 : 0
  name               = "${var.name}-jenkins"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "jenkins" {
  count = var.jenkins_role_name == "" ? 1 : 0
  name  = "${var.name}-jenkins"
  role  = aws_iam_role.jenkins[0].name
}

locals {
  jenkins_role = var.jenkins_role_name == "" ? aws_iam_role.jenkins[0].name : var.jenkins_role_name
}

resource "aws_iam_role_policy_attachment" "jenkins" {
  role       = local.jenkins_role
  policy_arn = aws_iam_policy.jenkins.arn
}
