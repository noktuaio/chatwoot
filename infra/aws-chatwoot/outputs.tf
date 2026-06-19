output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "region" {
  value = var.aws_region
}

output "domain_name" {
  value = var.domain_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.chatwoot.repository_url
}

output "github_actions_deploy_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

output "rds_endpoint" {
  value = aws_db_instance.chatwoot.address
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.chatwoot.primary_endpoint_address
}

output "uploads_bucket" {
  value = aws_s3_bucket.uploads.bucket
}

output "dns_instruction" {
  value = "Create a CNAME outside AWS: ${var.domain_name} -> the ALB DNS name shown by the Kubernetes ingress after deployment."
}

output "ec2_instance_id" {
  value = aws_instance.chatwoot.id
}

output "ec2_alb_dns_name" {
  value = aws_lb.ec2.dns_name
}

output "ec2_dns_instruction" {
  value = "After validation, update the external CNAME for ${var.domain_name} to ${aws_lb.ec2.dns_name}."
}
