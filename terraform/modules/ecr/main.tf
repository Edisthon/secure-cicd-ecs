resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE" # a version tag can never be overwritten
  force_delete         = var.force_delete

  image_scanning_configuration { scan_on_push = true } # second line of defence after Trivy
  encryption_configuration { encryption_type = "AES256" }
}

# Clean up old images: keep the newest N tagged images, expire untagged ones after 1 day.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the newest ${var.keep_images} tagged images"
        selection    = { tagStatus = "tagged", tagPatternList = ["*"], countType = "imageCountMoreThan", countNumber = var.keep_images }
        action       = { type = "expire" }
      }
    ]
  })
}
