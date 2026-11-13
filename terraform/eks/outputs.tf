output "cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.securekube.name
}

output "cluster_endpoint" {
  description = "EKS API Server Endpoint"
  value       = aws_eks_cluster.securekube.endpoint
}

output "oidc_provider_arn" {
  description = "IAM OIDC Provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.oidc.arn
}

output "kms_key_arn" {
  description = "KMS Key ARN used for Kubernetes Secrets encryption"
  value       = var.enable_kms_secrets_encryption ? aws_kms_key.eks_secrets[0].arn : "disabled"
}
