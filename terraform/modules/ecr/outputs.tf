output "ecr_repository_url" {
  value = aws_ecr_repository.ecr-backend-repo.repository_url
}

output "ecs_repository_name" {
  value = aws_ecr_repository.ecr-backend-repo.name
}
