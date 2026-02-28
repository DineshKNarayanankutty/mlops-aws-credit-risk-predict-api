variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)

  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "private_subnets must contain at least one private subnet for worker node placement."
  }
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
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

variable "cluster_enabled_log_types" {
  type = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

variable "cluster_additional_security_group_ids" {
  type    = list(string)
  default = []
}

variable "kms_deletion_window_in_days" {
  type    = number
  default = 30
}

variable "system_node_group_min_size" {
  type    = number
  default = 2
}

variable "system_node_group_max_size" {
  type    = number
  default = 6
}

variable "system_node_group_desired_size" {
  type    = number
  default = 2
}

variable "inference_node_group_min_size" {
  type    = number
  default = 1
}

variable "inference_node_group_max_size" {
  type    = number
  default = 10
}

variable "inference_node_group_desired_size" {
  type    = number
  default = 2
}

variable "system_node_root_volume_size" {
  type    = number
  default = 50
}

variable "inference_node_root_volume_size" {
  type    = number
  default = 80
}

variable "autoscaler_service_account_namespace" {
  type    = string
  default = "kube-system"
}

variable "autoscaler_service_account_name" {
  type    = string
  default = "cluster-autoscaler"
}

variable "tags" {
  type    = map(string)
  default = {}
}
