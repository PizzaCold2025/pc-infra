output "ecr_repo_uris" {
  value = {
    for name, repo in aws_ecr_repository.repos :
    name => repo.repository_url
  }
}

output "users_prod_url" {
  value = aws_api_gateway_stage.users_prod.invoke_url
}
