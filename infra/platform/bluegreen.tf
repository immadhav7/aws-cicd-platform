# Phase 7: blue/green deployments with automatic rollback (prod only).
#
# CodeDeploy starts the new version ("green") in a second target group next to the running one
# ("blue"), shifts 10% of the traffic to it, watches a CloudWatch alarm for a few minutes, then
# shifts the rest. If the alarm fires or the deployment fails, traffic goes back to blue by itself.
# Dev keeps the plain ECS rolling deploy, so everything here is created in the prod workspace only.

locals {
  blue_green = local.environment == "prod"
}

# The second target group. "blue" and "green" swap roles on every deployment, so the names
# are just names: the first one (aws_lb_target_group.app) happens to start as blue.
resource "aws_lb_target_group" "green" {
  count = local.blue_green ? 1 : 0

  name        = "${local.name}-tg-green"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# The rollback trigger: the load balancer counts responses where the app itself answered 5xx.
# No traffic means no data, which is treated as healthy.
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  count = local.blue_green ? 1 : 0

  alarm_name          = "${local.name}-alb-5xx"
  alarm_description   = "Prod app returns 5xx errors. CodeDeploy rolls the deployment back while this is in ALARM."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  count = local.blue_green ? 1 : 0

  name               = "${local.name}-codedeploy"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json
}

# AWS-managed policy for CodeDeploy on ECS: update the service, move ALB traffic, read alarms.
resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = local.blue_green ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_app" "app" {
  count = local.blue_green ? 1 : 0

  name             = local.name
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "app" {
  count = local.blue_green ? 1 : 0

  app_name               = aws_codedeploy_app.app[0].name
  deployment_group_name  = local.name
  service_role_arn       = aws_iam_role.codedeploy[0].arn
  deployment_config_name = var.deployment_config_name

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.blue_termination_wait_minutes
    }
  }

  # Roll back by itself when the deployment fails or the alarm fires.
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.http_5xx[0].alarm_name]
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group {
        name = aws_lb_target_group.app.name
      }

      target_group {
        name = aws_lb_target_group.green[0].name
      }
    }
  }
}
