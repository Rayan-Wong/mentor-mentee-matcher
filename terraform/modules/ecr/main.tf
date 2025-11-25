resource "aws_ecr_repository" "ecr-backend-repo" {
  name         = var.app_name
  force_delete = true

  tags = var.tags
}
