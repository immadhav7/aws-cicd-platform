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
