output "irsa_role_arn" {
  value = local.irsa_role_arn
}

output "helm_release_name" {
  value = helm_release.this.name
}
