variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for EKS IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL for EKS IRSA"
  type        = string
}

variable "inference_namespace" {
  description = "Namespace for inference service account"
  type        = string
  default     = "inference"
}

variable "inference_service_account_name" {
  description = "Service account name for inference workload"
  type        = string
  default     = "inference-service"
}

variable "alb_controller_namespace" {
  description = "Namespace for AWS Load Balancer Controller service account"
  type        = string
  default     = "kube-system"
}

variable "alb_controller_service_account_name" {
  description = "Service account name for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN used for inference/training images"
  type        = string
}

variable "artifact_bucket_name" {
  description = "Artifact bucket name used by CI/CD"
  type        = string
}

variable "model_artifacts_bucket_arn" {
  description = "S3 bucket ARN used for model artifacts"
  type        = string
}

variable "training_data_bucket_arn" {
  description = "S3 bucket ARN used for SageMaker training input data"
  type        = string
}

variable "codestar_connection_arn" {
  description = "CodeStar connection ARN for GitHub source integration"
  type        = string
}

variable "model_artifacts_kms_key_arn" {
  description = "KMS key ARN used for SageMaker model artifacts"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
