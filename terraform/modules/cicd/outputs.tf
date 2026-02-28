output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "pipeline_arn" {
  value = aws_codepipeline.this.arn
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "artifact_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}

output "artifact_kms_key_arn" {
  value = aws_kms_key.artifacts.arn
}

output "build_project_name" {
  value = aws_codebuild_project.build_and_push.name
}

output "build_project_arn" {
  value = aws_codebuild_project.build_and_push.arn
}

output "training_project_name" {
  value = aws_codebuild_project.trigger_training.name
}

output "training_project_arn" {
  value = aws_codebuild_project.trigger_training.arn
}
