resource "aws_sagemaker_model_package_group" "credit_risk" {
  model_package_group_name        = var.model_package_group_name != "" ? var.model_package_group_name : "${local.name_prefix}-credit-risk"
  model_package_group_description = "Model registry group for credit risk classifier"
  tags                            = local.common_tags
}
