output "sfn_orders_state_machine" {
  value = aws_sfn_state_machine.order_workflow.arn
}
