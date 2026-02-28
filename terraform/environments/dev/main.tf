module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  environment                     = var.environment
  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version
  vpc_id                          = module.vpc.vpc_id
  private_subnets                 = module.vpc.private_subnets
  node_instance_type              = var.node_instance_type
  inference_node_instance_type    = var.inference_node_instance_type
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  tags                            = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "mlops-dev-inference"
  environment     = var.environment
  project_name    = var.project_name
  tags            = local.common_tags
}

module "s3" {
  source      = "../../modules/s3"
  bucket_name = "mlops-dev-artifacts-bucket777"
  tags        = local.common_tags
}

module "sagemaker" {
  source = "../../modules/sagemaker"

  environment                 = var.environment
  model_package_group_name    = var.model_package_group_name
  model_artifacts_bucket_name = var.sagemaker_model_artifacts_bucket_name
  ecr_repository_arn          = module.ecr.repository_arn
  tags                        = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  environment                         = var.environment
  cluster_name                        = module.eks.cluster_name
  oidc_provider_arn                   = module.eks.oidc_provider_arn
  oidc_provider_url                   = module.eks.oidc_provider
  ecr_repository_arn                  = module.ecr.repository_arn
  artifact_bucket_name                = var.cicd_artifact_bucket_name
  model_artifacts_bucket_arn          = module.sagemaker.model_artifacts_bucket_arn
  model_artifacts_kms_key_arn         = module.sagemaker.model_artifacts_kms_key_arn
  training_data_bucket_arn            = local.training_data_bucket_arn
  codestar_connection_arn             = var.codestar_connection_arn
  inference_namespace                 = var.inference_namespace
  inference_service_account_name      = var.inference_service_account_name
  alb_controller_namespace            = var.alb_controller_namespace
  alb_controller_service_account_name = var.alb_controller_service_account_name
  tags                                = local.common_tags
}

module "cicd" {
  source = "../../modules/cicd"

  environment                 = var.environment
  artifact_bucket_name        = var.cicd_artifact_bucket_name
  codebuild_role_arn          = module.iam.codebuild_role_arn
  codepipeline_role_arn       = module.iam.codepipeline_role_arn
  codestar_connection_arn     = var.codestar_connection_arn
  github_full_repository_id   = var.github_full_repository_id
  github_branch               = var.github_branch
  ecr_repository_url          = module.ecr.repository_url
  sagemaker_training_role_arn = module.iam.sagemaker_training_role_arn
  training_input_s3_uri       = var.training_input_s3_uri
  training_output_s3_uri      = var.training_output_s3_uri
  tags                        = local.common_tags
}

module "alb_controller" {
  count  = var.environment == "dev" ? 0 : 1
  source = "../../modules/alb_controller"

  cluster_name              = module.eks.cluster_name
  region                    = var.region
  vpc_id                    = module.vpc.vpc_id
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_provider_url         = module.eks.oidc_provider
  namespace                 = var.alb_controller_namespace
  service_account_name      = var.alb_controller_service_account_name
  chart_version             = var.alb_controller_chart_version
  create_irsa_role          = false
  existing_irsa_role_arn    = module.iam.alb_controller_role_arn
  backend_security_group_id = module.eks.alb_backend_security_group_id
  tags                      = local.common_tags

  depends_on = [module.eks]
}

module "monitoring" {
  count  = var.environment == "dev" ? 0 : 1
  source = "../../modules/monitoring"

  cluster_name                 = module.eks.cluster_name
  namespace                    = var.monitoring_namespace
  enable_prometheus            = true
  enable_grafana               = true
  enable_metrics_server        = true
  enable_container_insights    = var.environment == "prod"
  log_retention_in_days        = var.environment == "prod" ? 30 : 7
  prometheus_chart_version     = var.prometheus_chart_version
  grafana_chart_version        = var.grafana_chart_version
  metrics_server_chart_version = var.metrics_server_chart_version
  tags                         = local.common_tags

  depends_on = [module.alb_controller]
}

locals {
  training_data_bucket_name = split("/", trimprefix(var.training_input_s3_uri, "s3://"))[0]
  training_data_bucket_arn  = "arn:aws:s3:::${local.training_data_bucket_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}
