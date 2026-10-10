# ---------------------------------------------------------------------------
# Application Load Balancer (public, in the public subnets)
# ---------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = local.public_subnet_ids
  security_groups    = [local.alb_sg_id]
}

# Target type "ip" is required for Fargate (awsvpc networking).
# Phase 7 (blue/green) will add a second target group for the "green" tasks.
resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  # Drain quickly: this is a demo app with no long-running requests.
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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
