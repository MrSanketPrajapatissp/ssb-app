output "ssb_app_role_arn" {
  description = "IRSA role ARN for ssb-app pods."
  value       = aws_iam_role.ssb_app.arn
}
output "cicd_role_arn" {
  description = "IAM role ARN for GitHub Actions CI/CD pipeline."
  value       = aws_iam_role.cicd.arn
}
output "ecr_repository_url" {
  description = "ECR repository URL for ssb-app images."
  value       = aws_ecr_repository.ssb_app.repository_url
}
