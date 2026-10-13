output "role_arn" {
  description = "Set this as the repository variable AWS_ROLE_ARN in GitHub"
  value       = aws_iam_role.github_actions.arn
}
