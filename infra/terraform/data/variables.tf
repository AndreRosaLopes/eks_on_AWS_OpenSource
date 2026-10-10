variable "name" {
  description = "Name prefix of the platform resources."
  type        = string
  default     = "data-platform-dev"
}

variable "region" {
  description = "AWS Region."
  type        = string
  default     = "us-east-2"
}
