output "alb_dns_name" {
  description = "Open http://<this> in a browser or curl it"
  value       = aws_lb.app.dns_name
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "deployed_image" {
  value = local.image
}

output "environment" {
  description = "Environment this workspace deployed (dev or prod)"
  value       = local.environment
}

output "codedeploy_app_name" {
  description = "CodeDeploy application (prod only)"
  value       = try(aws_codedeploy_app.app[0].name, null)
}

output "codedeploy_deployment_group" {
  description = "CodeDeploy deployment group (prod only)"
  value       = try(aws_codedeploy_deployment_group.app[0].deployment_group_name, null)
}

output "rollback_alarm" {
  description = "CloudWatch alarm that triggers the automatic rollback (prod only)"
  value       = try(aws_cloudwatch_metric_alarm.http_5xx[0].alarm_name, null)
}
