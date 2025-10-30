provider "aws" {
  region = var.aws_region
}

variable "ecr_repos" {
  type = set(string)
  default = [
    "pc-users-hello"
  ]
}

resource "aws_ecr_repository" "repos" {
  for_each = var.ecr_repos
  name     = each.value
}

data "aws_ecr_image" "images" {
  for_each        = var.ecr_repos
  repository_name = each.value
  image_tag       = "latest"

  // Allows repos to be created first
  ignore_errors = true
}

resource "aws_dynamodb_table" "users_restaurants" {
  name           = "pc-users-restaurants"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "tenant_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "users_users" {
  name           = "pc-users-users"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "tenant_id"
  range_key      = "user_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }
}

resource "aws_lambda_function" "functions" {
  for_each = var.ecr_repos

  function_name = each.value
  package_type  = "Image"
  image_uri     = data.aws_ecr_image.images[each.value] != "" ? "${aws_ecr_repository.repos[each.value].repository_url}@${data.aws_ecr_image.images[each.value].image_digest}" : null

  role        = var.labrole_arn
  timeout     = 20
  memory_size = 512
}

resource "aws_api_gateway_rest_api" "users_api" {
  name = "pc-users-api"

  body = jsonencode({
    openapi = "3.0.1"

    info = {
      title   = "PizzaCold Users API"
      version = "0.1.0"
    }

    paths = {
      "/hello" = {
        get = {
          x-amazon-apigateway-integration = {
            httpMethod = "POST"
            type       = "aws_proxy"
            uri        = aws_lambda_function.functions["pc-users-hello"].invoke_arn
          }
        }
      }
    }
  })

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_lambda_permission" "api_permissions" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions["pc-users-hello"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.users_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "users_deployment" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.users_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "users_prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  deployment_id = aws_api_gateway_deployment.users_deployment.id
}
