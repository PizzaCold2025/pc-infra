provider "aws" {
  region = var.aws_region
}

data "aws_lambda_function" "start_order_execution" {
  function_name = "pc-orders-dev-start_order_execution"
}

data "aws_lambda_function" "put_order_task_token" {
  function_name = "pc-orders-dev-put_order_task_token"
}

data "aws_lambda_function" "resume_order_workflow" {
  function_name = "pc-orders-dev-resume_order_workflow"
}

data "aws_lambda_function" "broadcast_order_create" {
  function_name = "pc-orders-dev-broadcast_order_create"
}

data "aws_lambda_function" "broadcast_order_status" {
  function_name = "pc-orders-dev-broadcast_order_status"
}

resource "aws_dynamodb_table" "restaurants" {
  name         = "pc-users-restaurants"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "tenant_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "users" {
  name         = "pc-users-users"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "tenant_id"
  range_key = "user_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "tenant_id"
    range_key       = "status"
    projection_type = "ALL"
  }
}

resource "aws_dynamodb_table" "orders" {
  name         = "pc-orders"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "tenant_id"
  range_key = "order_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "order_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "order_subscriptions" {
  name         = "pc-order-subscriptions"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "tenant_id"
  range_key = "connection_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "connection_id"
    type = "S"
  }

  global_secondary_index {
    name            = "connection-id-index"
    hash_key        = "connection_id"
    projection_type = "ALL"
  }
}

locals {
  order_state_names = [
    "WaitForCook",
    "Cooking",
    "WaitForDispatcher",
    "Dispatching",
    "WaitForDeliverer",
    "Delivering",
    "Complete"
  ]

  order_states = {
    for i, name in local.order_state_names :
    name => {
      Type     = "Task"
      Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
      Parameters = {
        FunctionName = data.aws_lambda_function.put_order_task_token.function_name
        Payload = {
          "tenant_id.$" : "$.detail.tenant_id"
          "order_id.$" : "$.detail.order_id"
          "task_token.$" : "$$.Task.Token"
        }
      }
      Next = i < length(local.order_state_names) - 1 ? local.order_state_names[i + 1] : "FinalStep"
    }
  }
}

resource "aws_sfn_state_machine" "order_workflow" {
  name     = "pc-order-workflow"
  role_arn = var.labrole_arn

  definition = jsonencode({
    StartAt = "WaitForCook"
    States = merge(local.order_states, {
      FinalStep = {
        Type = "Pass"
        End  = true
      }
    })
  })
}

resource "aws_cloudwatch_event_rule" "order_created" {
  name = "pc-order-created"

  event_pattern = jsonencode({
    source      = ["pc.orders"],
    detail-type = ["order.created"]
  })
}

resource "aws_cloudwatch_event_target" "start_order_execution" {
  target_id = "pc-order-created"
  rule      = aws_cloudwatch_event_rule.order_created.name
  arn       = data.aws_lambda_function.start_order_execution.arn

  role_arn = var.labrole_arn
}

resource "aws_cloudwatch_event_target" "broadcast_order_create" {
  target_id = "pc-order-created"
  rule      = aws_cloudwatch_event_rule.order_created.name
  arn       = data.aws_lambda_function.broadcast_order_create.arn

  role_arn = var.labrole_arn
}

resource "aws_cloudwatch_event_rule" "order_status_updated" {
  name = "pc-order-status-updated"

  event_pattern = jsonencode({
    source      = ["pc.orders"],
    detail-type = ["order.status_update"],
  })
}

resource "aws_cloudwatch_event_target" "resume_order_workflow" {
  target_id  = "pc-resume-order-workflow"
  rule       = aws_cloudwatch_event_rule.order_status_updated.name
  arn        = data.aws_lambda_function.resume_order_workflow.arn
  input_path = "$"

  role_arn = var.labrole_arn
}

resource "aws_cloudwatch_event_target" "broadcast_order_status" {
  target_id  = "pc-broadcast-order-status"
  rule       = aws_cloudwatch_event_rule.order_status_updated.name
  arn        = data.aws_lambda_function.broadcast_order_status.arn
  input_path = "$"

  role_arn = var.labrole_arn
}
