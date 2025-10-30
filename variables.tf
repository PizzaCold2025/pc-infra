variable "aws_region" {
  type        = string
  description = "AWS region to use"
  default     = "us-east-1"
}

variable "labrole_arn" {
  type        = string
  description = "ARN of the LabRole to assume for lambda functions and similar"
}

variable "domain" {
  type        = string
  description = "Domain to use for SSL certificates"
}
