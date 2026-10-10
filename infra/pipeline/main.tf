# Phase 4: CodeBuild. Phase 5 adds CodePipeline in this same module.

data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

locals {
  build_name = "${var.project}-app-build"
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "build" {
  name              = "/codebuild/${local.build_name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# IAM: the role CodeBuild assumes. Least privilege: write its own logs and
# push images to THIS repository only.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.build_name}-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.build.arn}:*"]
  }

  # ecr:GetAuthorizationToken cannot be limited to a repository, so it needs "*".
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [data.aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.build_name}-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# ---------------------------------------------------------------------------
# CodeBuild project. The steps live in buildspec.yml at the repo root.
# The repository is public, so no GitHub credentials are needed to clone it.
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "app" {
  name          = local.build_name
  description   = "Test, build and push the app image to ECR"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  source {
    type     = "GITHUB"
    location = var.github_repository_url
  }

  source_version = var.source_version

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"

    # Required to run Docker (build and push images) inside the build.
    privileged_mode = true

    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = data.aws_ecr_repository.app.repository_url
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.build.name
      stream_name = "build"
    }
  }
}
