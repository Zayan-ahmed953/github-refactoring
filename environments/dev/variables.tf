variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
}

variable "aws_profile" {
  description = "Optional AWS CLI profile to use"
  type        = string
  default     = null
}

variable "environment" {
  description = "Logical environment name used in modules (e.g. dev, uat, prod)"
  type        = string
  default     = "dev"
}
