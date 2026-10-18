# Phase 8: a CloudWatch dashboard per environment (dev and prod each get their own).
#
# It shows what the platform is doing right now: traffic and errors at the load balancer, how fast
# the app answers, how many targets are healthy, and the CPU and memory of the ECS service.
# In prod it also shows the green target group and the rollback alarm from bluegreen.tf, and the
# 5xx graph has the rollback threshold drawn on it. The first 3 dashboards in an account are free.

data "aws_region" "dashboard" {}

locals {
  dash_region   = data.aws_region.dashboard.name
  dash_alb      = aws_lb.app.arn_suffix
  dash_tg       = aws_lb_target_group.app.arn_suffix
  dash_tg_green = try(aws_lb_target_group.green[0].arn_suffix, "")
  dash_alarm    = try(aws_cloudwatch_metric_alarm.http_5xx[0].arn, "")

  # Widgets both environments have.
  dash_common = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title   = "Traffic: requests and successful answers per minute"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.dash_alb, { stat = "Sum", label = "requests" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", local.dash_alb, { stat = "Sum", label = "2xx answers" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 0
      width  = 12
      height = 6
      properties = {
        title   = "Errors: 5xx answers from the app per minute"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.dash_alb, { stat = "Sum", label = "5xx answers", color = "#d62728" }],
        ]
        annotations = {
          horizontal = [
            { label = "prod rolls back at this level", value = var.alarm_5xx_threshold, color = "#d62728" },
          ]
        }
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        title   = "Latency: how long the app takes to answer (seconds)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.dash_alb, { stat = "Average", label = "average" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.dash_alb, { stat = "p95", label = "p95" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        title   = "Targets: healthy and unhealthy tasks (main target group)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.dash_tg, "LoadBalancer", local.dash_alb, { stat = "Minimum", label = "healthy" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.dash_tg, "LoadBalancer", local.dash_alb, { stat = "Maximum", label = "unhealthy" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        title   = "ECS service: CPU and memory (%)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "CPU" }],
          ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "memory" }],
        ]
      }
    },
  ]

  # Extra widgets for prod only (blue/green). They are built in dev too but never used there.
  dash_prod_extra = [
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        title   = "Targets: healthy tasks in the green target group (new version during a deploy)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.dash_tg_green, "LoadBalancer", local.dash_alb, { stat = "Minimum", label = "healthy (green)" }],
        ]
      }
    },
    {
      type   = "alarm"
      x      = 0
      y      = 18
      width  = 12
      height = 3
      properties = {
        title  = "Rollback alarm"
        alarms = [local.dash_alarm]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = local.blue_green ? jsonencode({ widgets = concat(local.dash_common, local.dash_prod_extra) }) : jsonencode({ widgets = local.dash_common })
}

output "dashboard_url" {
  description = "Console link to this environment's CloudWatch dashboard"
  value       = "https://${local.dash_region}.console.aws.amazon.com/cloudwatch/home?region=${local.dash_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
