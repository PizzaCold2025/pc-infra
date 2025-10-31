output "users_prod_url" {
  value = {
    for key, stage in aws_api_gateway_stage.prods :
    key => stage.invoke_url
  }
}
