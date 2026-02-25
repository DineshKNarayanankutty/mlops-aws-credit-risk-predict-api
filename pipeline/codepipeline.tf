terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "mlops-aws-credit-risk"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "artifact_bucket_force_destroy" {
  type    = bool
  default = true
}

variable "codebuild_role_arn" {
  type = string
}

variable "ecr_repository_name" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "model_artifact_s3_uri" {
  type = string
}

variable "k8s_deployment_name" {
  type    = string
  default = "credit-risk-api"
}

variable "k8s_container_name" {
  type    = string
  default = "credit-risk-api"
}

resource "random_id" "artifact_bucket_suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = lower(replace("${local.name_prefix}-pipeline-artifacts-${random_id.artifact_bucket_suffix.hex}", "_", "-"))
  force_destroy = var.artifact_bucket_force_destroy
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name_prefix}-github-connection"
  provider_type = "GitHub"
}

data "aws_iam_policy_document" "codepipeline_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "${local.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json
}

data "aws_iam_policy_document" "codepipeline_policy" {
  statement {
    sid = "S3Artifacts"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    sid = "CodeStarConnection"
    actions = [
      "codestar-connections:UseConnection"
    ]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  statement {
    sid = "CodeBuild"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds"
    ]
    resources = [aws_codebuild_project.deploy.arn]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "${local.name_prefix}-codepipeline-policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}-deploy"
  retention_in_days = 14
}

resource "aws_codebuild_project" "deploy" {
  name          = "${local.name_prefix}-deploy"
  service_role  = var.codebuild_role_arn
  build_timeout = 30

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "ECR_REPO_NAME"
      value = var.ecr_repository_name
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = var.eks_cluster_name
    }

    environment_variable {
      name  = "MODEL_ARTIFACT_S3_URI"
      value = var.model_artifact_s3_uri
    }

    environment_variable {
      name  = "K8S_DEPLOYMENT_NAME"
      value = var.k8s_deployment_name
    }

    environment_variable {
      name  = "K8S_CONTAINER_NAME"
      value = var.k8s_container_name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
      status     = "ENABLED"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "pipeline/buildspec.yml"
  }
}

resource "aws_codepipeline" "this" {
  name     = "${local.name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "BuildDeploy"

    action {
      name            = "CodeBuildDeploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }
}

output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "codestar_connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}
