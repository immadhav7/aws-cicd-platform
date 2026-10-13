output "codebuild_project_name" {
  value = aws_codebuild_project.app.name
}

output "build_log_group" {
  value = aws_cloudwatch_log_group.build.name
}

output "pipeline_name" {
  value = aws_codepipeline.app.name
}

output "connection_arn" {
  description = "Authorize this connection once in the console (it starts as PENDING)"
  value       = aws_codestarconnections_connection.github.arn
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
