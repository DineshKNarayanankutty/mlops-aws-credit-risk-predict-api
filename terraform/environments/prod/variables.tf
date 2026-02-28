variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "project_name" {
  type    = string
  default = "mlops-platform"
}

variable "cluster_name" {
  type    = string
  default = "mlops-prod-cluster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = [
    "10.2.1.0/24",
    "10.2.2.0/24",
    "10.2.3.0/24"
  ]
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = [
    "10.2.101.0/24",
    "10.2.102.0/24",
    "10.2.103.0/24"
  ]
}

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_type" {
  type    = string
  default = "t3.large"
}

variable "inference_node_instance_type" {
  type    = string
  default = "t3.large"
}

variable "cluster_endpoint_public_access" {
  type    = bool
  default = true
}

variable "cluster_endpoint_private_access" {
  type    = bool
  default = true
}

variable "model_package_group_name" {
  type = string
}

variable "sagemaker_model_artifacts_bucket_name" {
  type = string
}

variable "cicd_artifact_bucket_name" {
  type = string
}

variable "codestar_connection_arn" {
  type = string
}

variable "github_full_repository_id" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "training_input_s3_uri" {
  type = string
}

variable "training_output_s3_uri" {
  type = string
}

variable "inference_namespace" {
  type    = string
  default = "inference"
}

variable "inference_service_account_name" {
  type    = string
  default = "inference-service"
}

variable "alb_controller_namespace" {
  type    = string
  default = "kube-system"
}

variable "alb_controller_service_account_name" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "alb_controller_chart_version" {
  type    = string
  default = "1.11.0"
}

variable "monitoring_namespace" {
  type    = string
  default = "monitoring"
}

variable "prometheus_chart_version" {
  type    = string
  default = "25.30.0"
}

variable "grafana_chart_version" {
  type    = string
  default = "8.10.0"
}

variable "metrics_server_chart_version" {
  type    = string
  default = "3.13.0"
}
