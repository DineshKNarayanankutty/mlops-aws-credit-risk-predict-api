variable "environment" {
  description = "Environment name"
  type        = string
}

variable "model_package_group_name" {
  description = "SageMaker model package group name"
  type        = string
}

variable "model_artifacts_bucket_name" {
  description = "S3 bucket name for model artifacts"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN for model/inference image access"
  type        = string
}

variable "kms_deletion_window_in_days" {
  description = "Deletion window for module-created KMS keys"
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow bucket destruction when non-empty"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
