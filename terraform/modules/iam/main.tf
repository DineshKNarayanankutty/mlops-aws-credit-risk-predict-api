data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  oidc_provider_hostpath   = replace(var.oidc_provider_url, "https://", "")
  artifact_bucket_arn      = "arn:aws:s3:::${var.artifact_bucket_name}"
  training_data_bucket_arn = var.training_data_bucket_arn
  base_tags = merge(
    {
      Project     = lookup(var.tags, "Project", "mlops-platform")
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

data "aws_iam_policy_document" "inference_irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_hostpath}:sub"
      values   = ["system:serviceaccount:${var.inference_namespace}:${var.inference_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "inference_irsa" {
  name               = "${var.environment}-mlops-inference-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.inference_irsa_assume_role.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "inference_irsa" {
  statement {
    sid    = "ReadModelArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      var.model_artifacts_bucket_arn,
      "${var.model_artifacts_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "PullInferenceImage"
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
    sid    = "DecryptModelArtifacts"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [var.model_artifacts_kms_key_arn]
  }
}

resource "aws_iam_policy" "inference_irsa" {
  name   = "${var.environment}-mlops-inference-irsa-policy"
  policy = data.aws_iam_policy_document.inference_irsa.json
  tags   = local.base_tags
}

resource "aws_iam_role_policy_attachment" "inference_irsa" {
  role       = aws_iam_role.inference_irsa.name
  policy_arn = aws_iam_policy.inference_irsa.arn
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.environment}-mlops-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid    = "CodeBuildLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
    ]
  }

  statement {
    sid    = "ArtifactBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      local.artifact_bucket_arn,
      "${local.artifact_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "PushAndPullECRImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage"
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid     = "GetECRAuthToken"
    effect  = "Allow"
    actions = ["ecr:GetAuthorizationToken"]
    # AWS only supports "*" for ecr:GetAuthorizationToken.
    resources = ["*"]
  }

  statement {
    sid    = "StartSageMakerTraining"
    effect = "Allow"
    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:AddTags"
    ]
    resources = [
      "arn:aws:sagemaker:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:training-job/${var.environment}-*"
    ]
  }

  statement {
    sid    = "PassTrainingExecutionRole"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [aws_iam_role.sagemaker_training.arn]
  }

}

resource "aws_iam_policy" "codebuild" {
  name   = "${var.environment}-mlops-codebuild-policy"
  policy = data.aws_iam_policy_document.codebuild.json
  tags   = local.base_tags
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
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

resource "aws_iam_role" "codepipeline" {
  name               = "${var.environment}-mlops-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    sid    = "ArtifactBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      local.artifact_bucket_arn,
      "${local.artifact_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "UseGitHubConnection"
    effect = "Allow"
    actions = [
      "codestar-connections:UseConnection"
    ]
    resources = [var.codestar_connection_arn]
  }

  statement {
    sid    = "InvokeBuildProjects"
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds"
    ]
    resources = [
      "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/${var.environment}-mlops-*"
    ]
  }

}

resource "aws_iam_policy" "codepipeline" {
  name   = "${var.environment}-mlops-codepipeline-policy"
  policy = data.aws_iam_policy_document.codepipeline.json
  tags   = local.base_tags
}

resource "aws_iam_role_policy_attachment" "codepipeline" {
  role       = aws_iam_role.codepipeline.name
  policy_arn = aws_iam_policy.codepipeline.arn
}

data "aws_iam_policy_document" "sagemaker_training_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_training" {
  name               = "${var.environment}-mlops-sagemaker-training-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_training_assume_role.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "sagemaker_training" {
  statement {
    sid    = "ModelArtifactsBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      var.model_artifacts_bucket_arn,
      "${var.model_artifacts_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "TrainingDataBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      local.training_data_bucket_arn,
      "${local.training_data_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "PullContainerImage"
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
    sid    = "SageMakerLogs"
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
    sid    = "UseKMSKeys"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = [var.model_artifacts_kms_key_arn]
  }
}

resource "aws_iam_policy" "sagemaker_training" {
  name   = "${var.environment}-mlops-sagemaker-training-policy"
  policy = data.aws_iam_policy_document.sagemaker_training.json
  tags   = local.base_tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_training" {
  role       = aws_iam_role.sagemaker_training.name
  policy_arn = aws_iam_policy.sagemaker_training.arn
}

data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_hostpath}:sub"
      values   = ["system:serviceaccount:${var.alb_controller_namespace}:${var.alb_controller_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.environment}-mlops-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "alb_controller" {
  statement {
    sid    = "AllowELBReadAndManage"
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "cognito-idp:DescribeUserPoolClient",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetWebAcl",
      "iam:CreateServiceLinkedRole",
      "iam:GetServerCertificate",
      "iam:ListServerCertificates",
      "waf-regional:GetWebACLForResource",
      "waf-regional:GetWebACL",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:GetWebACL",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection"
    ]
    # ALB controller requires broad resource scope for several ELB/EC2/WAF APIs.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.environment}-mlops-alb-controller-policy"
  policy = data.aws_iam_policy_document.alb_controller.json
  tags   = local.base_tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
