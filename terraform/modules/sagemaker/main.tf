data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  model_artifacts_log_bucket_name = "${var.model_artifacts_bucket_name}-access-logs"
  create_model_package_group      = var.environment != "dev"
  enable_bucket_versioning        = var.environment != "dev"
  base_tags = merge(
    {
      Project     = lookup(var.tags, "Project", "mlops-platform")
      ManagedBy   = "Terraform"
      Environment = var.environment
    },
    var.tags
  )
}

resource "aws_kms_key" "model_artifacts" {
  description             = "KMS key for SageMaker model artifacts (${var.environment})"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  tags                    = local.base_tags
}

resource "aws_kms_alias" "model_artifacts" {
  name          = "alias/sagemaker/${var.environment}/model-artifacts"
  target_key_id = aws_kms_key.model_artifacts.key_id
}

resource "aws_s3_bucket" "model_artifacts" {
  bucket        = var.model_artifacts_bucket_name
  force_destroy = var.force_destroy
  tags          = merge(local.base_tags, { Purpose = "sagemaker-model-artifacts" })
}

resource "aws_s3_bucket" "model_artifacts_log" {
  bucket        = local.model_artifacts_log_bucket_name
  force_destroy = var.force_destroy
  tags          = merge(local.base_tags, { Purpose = "sagemaker-model-artifacts-access-logs" })
}

resource "aws_s3_bucket_ownership_controls" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "model_artifacts_log" {
  bucket = aws_s3_bucket.model_artifacts_log.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "model_artifacts_log" {
  bucket = aws_s3_bucket.model_artifacts_log.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  versioning_configuration {
    status = local.enable_bucket_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "model_artifacts_log" {
  bucket = aws_s3_bucket.model_artifacts_log.id

  versioning_configuration {
    status = local.enable_bucket_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.model_artifacts.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts_log" {
  bucket = aws_s3_bucket.model_artifacts_log.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.model_artifacts.arn
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "model_artifacts_bucket_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.model_artifacts.arn,
      "${aws_s3_bucket.model_artifacts.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "model_artifacts_tls" {
  bucket = aws_s3_bucket.model_artifacts.id
  policy = data.aws_iam_policy_document.model_artifacts_bucket_tls.json
}

data "aws_iam_policy_document" "model_artifacts_log_delivery" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.model_artifacts_log.arn}/access-logs/*"
    ]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.model_artifacts.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "model_artifacts_log_delivery" {
  bucket = aws_s3_bucket.model_artifacts_log.id
  policy = data.aws_iam_policy_document.model_artifacts_log_delivery.json
}

resource "aws_s3_bucket_logging" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  target_bucket = aws_s3_bucket.model_artifacts_log.id
  target_prefix = "access-logs/"

  depends_on = [aws_s3_bucket_policy.model_artifacts_log_delivery]
}

data "aws_iam_policy_document" "sagemaker_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  name               = "${var.environment}-mlops-sagemaker-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_execution_assume_role.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "sagemaker_execution" {
  statement {
    sid    = "ReadWriteModelArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.model_artifacts.arn,
      "${aws_s3_bucket.model_artifacts.arn}/*"
    ]
  }

  statement {
    sid    = "PullECRImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid    = "GetECRAuthToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    # AWS only supports "*" for ecr:GetAuthorizationToken.
    resources = ["*"]
  }

  statement {
    sid    = "SageMakerCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"
    ]
  }

  statement {
    sid    = "UseKMSForArtifacts"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = [aws_kms_key.model_artifacts.arn]
  }
}

resource "aws_iam_policy" "sagemaker_execution" {
  name   = "${var.environment}-mlops-sagemaker-execution-policy"
  policy = data.aws_iam_policy_document.sagemaker_execution.json
  tags   = local.base_tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_execution" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.sagemaker_execution.arn
}

resource "aws_sagemaker_model_package_group" "this" {
  count = local.create_model_package_group ? 1 : 0

  model_package_group_name        = var.model_package_group_name
  model_package_group_description = "Model package group for ${var.environment} MLOps platform"
  tags                            = local.base_tags
}
