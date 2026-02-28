output "inference_irsa_role_arn" {
  value = aws_iam_role.inference_irsa.arn
}

output "inference_irsa_role_name" {
  value = aws_iam_role.inference_irsa.name
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}

output "codebuild_role_name" {
  value = aws_iam_role.codebuild.name
}

output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codepipeline_role_name" {
  value = aws_iam_role.codepipeline.name
}

output "sagemaker_training_role_arn" {
  value = aws_iam_role.sagemaker_training.arn
}

output "sagemaker_training_role_name" {
  value = aws_iam_role.sagemaker_training.name
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "alb_controller_role_name" {
  value = aws_iam_role.alb_controller.name
}
