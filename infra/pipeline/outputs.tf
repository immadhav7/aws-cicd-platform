output "codebuild_project_name" {
  value = aws_codebuild_project.app.name
}

output "build_log_group" {
  value = aws_cloudwatch_log_group.build.name
}
