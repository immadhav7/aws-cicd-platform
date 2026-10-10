# ---------------------------------------------------------------------------
# Inputs from other modules
# ---------------------------------------------------------------------------

# VPC, subnets and security groups come from the network module's state.
# The network must be applied first (and is destroyed AFTER this module).
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "network/terraform.tfstate"
    region = var.region
  }
}

# The ECR repository comes from the registry module.
data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

locals {
  name = "${var.project}-${var.environment}"

  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  alb_sg_id          = data.terraform_remote_state.network.outputs.alb_security_group_id
  app_sg_id          = data.terraform_remote_state.network.outputs.app_security_group_id

  image = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# IAM: the task EXECUTION role lets ECS pull the image from ECR and write logs.
# (A separate task role, for the app's own AWS API calls, is not needed yet.)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# ECS cluster, task definition, service
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = local.name
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  # Images are built for linux/amd64 (see scripts/push-image.sh).
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = local.image
      essential = true

      portMappings = [{
        containerPort = var.app_port
        protocol      = "tcp"
      }]

      environment = [
        { name = "BUILD_ID", value = var.image_tag },
        { name = "APP_ENV", value = var.environment },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Give a new task time to start before the ALB health check can fail it.
  health_check_grace_period_seconds = 30

  # If a new deployment keeps failing, stop it and roll back to the last good one.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [local.app_sg_id]
    assign_public_ip = false # tasks reach ECR/logs through the NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  # The target group must be attached to a listener before the service can use it.
  depends_on = [aws_lb_listener.http]
}
