provider "aws" {
  region = var.aws_region
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

locals {
  functions = {
    users = {
      runtime   = "python3.13"
      functions = ["hello", "goodbye"]
    }
  }

  apis = {
    users = {
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
              uri        = aws_lambda_function.functions["users-hello"].invoke_arn
            }
          }
        }
        "/goodbye" = {
          get = {
            x-amazon-apigateway-integration = {
              httpMethod = "POST"
              type       = "aws_proxy"
              uri        = aws_lambda_function.functions["users-goodbye"].invoke_arn
            }
          }
        }
      }
    }
  }

  all_functions = flatten([
    for api_name, api in local.functions : [
      for fn_name in api.functions : {
        api_name    = api_name
        api_runtime = api.runtime
        fn_name     = fn_name
      }
    ]
  ])

  all_functions_keyed = {
    for f in local.all_functions :
    "${f.api_name}-${f.fn_name}" => f
  }
}

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "pc-lambda-artifacts"
}

resource "aws_s3_object" "zips" {
  for_each = local.all_functions_keyed

  bucket = aws_s3_bucket.lambda_artifacts.bucket
  key    = "lambdas/${each.value.api_name}/${each.value.fn_name}.zip"
}

resource "aws_lambda_function" "functions" {
  for_each = local.all_functions_keyed

  function_name = "pc-${each.key}"

  runtime     = each.value.api_runtime
  handler     = "handler.handler"
  role        = var.labrole_arn
  timeout     = 20
  memory_size = 512

  s3_bucket        = aws_s3_bucket.lambda_artifacts.bucket
  s3_key           = aws_s3_object.zips[each.key].key
  source_code_hash = base64encode(aws_s3_object.zips[each.key].etag)
}

resource "aws_api_gateway_rest_api" "apis" {
  for_each = local.apis

  name = "pc-${each.key}-api"

  body = jsonencode(each.value)

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_lambda_permission" "api_permissions" {
  for_each = local.all_functions_keyed

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.apis[each.value.api_name].execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployments" {
  for_each = local.apis

  rest_api_id = aws_api_gateway_rest_api.apis[each.key].id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.apis[each.key].body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prods" {
  for_each = local.apis

  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.apis[each.key].id
  deployment_id = aws_api_gateway_deployment.deployments[each.key].id
}
