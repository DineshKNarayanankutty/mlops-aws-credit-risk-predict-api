output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  value = module.eks.oidc_provider
}

output "cluster_autoscaler_role_arn" {
  value = try(aws_iam_role.cluster_autoscaler[0].arn, null)
}

output "node_ebs_kms_key_arn" {
  value = aws_kms_key.node_ebs.arn
}

output "alb_backend_security_group_id" {
  value = aws_security_group.alb_backend.id
}
