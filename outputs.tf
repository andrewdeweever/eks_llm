# output "rds_password" {
#   description = "The generated password for the RDS instance"
#   value       = random_password.rds_password.result
#   sensitive   = true
# }

output "eks_private_key_pem" {
  value     = tls_private_key.eks.private_key_pem
  sensitive = true
}

# output "bastion_public_ip" {
#   description = "Public IP of the Bastion host"
#   value       = aws_instance.bastion.public_ip
# }

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "external_dns_role_arn" {
  value       = aws_iam_role.external_dns.arn
  description = "ARN of the IAM role for external-dns"
}

output "cert_manager_role_arn" {
  value       = aws_iam_role.cert_manager.arn
  description = "ARN of the IAM role for external-dns"
}
