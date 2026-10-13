# Phase 4: CodeBuild. Phase 5: CodePipeline (Source -> Build -> Deploy to dev).

data "aws_caller_identity" "current" {}

data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  build_name    = "${var.project}-app-build"
  pipeline_name = "${var.project}-app-pipeline"

  # The ECS cluster/service/role are created by infra/platform. Only their names are needed
  # here, so the pipeline module does not depend on the platform's state (which is destroyed
  # between sessions).
  ecs_service_arn         = "arn:aws:ecs:${var.region}:${local.account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  task_execution_role_arn = "arn:aws:iam::${local.account_id}:role/${var.task_execution_role_name}"

  ecs_prod_service_arn         = "arn:aws:ecs:${var.region}:${local.account_id}:service/${var.ecs_prod_cluster_name}/${var.ecs_prod_service_name}"
  prod_task_execution_role_arn = "arn:aws:iam::${local.account_id}:role/${var.prod_task_execution_role_name}"
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "build" {
  name              = "/codebuild/${local.build_name}"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# Artifact bucket: where CodePipeline hands files from one stage to the next
# (the source zip, then imagedefinitions.json). Private, encrypted, auto-expiring.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project}-pipeline-artifacts-${local.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ---------------------------------------------------------------------------
# GitHub connection. Terraform creates it in PENDING state; you authorize it ONCE in the
# console (Developer Tools > Settings > Connections > Update pending connection).
# ---------------------------------------------------------------------------
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project}-github"
  provider_type = "GitHub"
}

# ---------------------------------------------------------------------------
# IAM: the role CodeBuild assumes. Least privilege: write its own logs, push images to
# THIS repository only, and read/write the pipeline's artifact bucket.
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
      "ecr:DescribeImages", # lets the build skip a commit whose image already exists
    ]
    resources = [data.aws_ecr_repository.app.arn]
  }

  statement {
    sid = "PipelineArtifacts"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "PipelineBucket"
    actions   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.build_name}-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# ---------------------------------------------------------------------------
# CodeBuild project. The steps live in buildspec.yml at the repo root.
# Source and artifacts now come from / go to CodePipeline (not GitHub directly).
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "app" {
  name          = local.build_name
  description   = "Test, build and push the app image to ECR (run by CodePipeline)"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  source {
    type = "CODEPIPELINE"
  }

  artifacts {
    type = "CODEPIPELINE"
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

# ---------------------------------------------------------------------------
# IAM: the role CodePipeline assumes.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Manual approval: CodePipeline publishes to this topic and SNS emails you.
# The subscription stays "pending" until you click the confirmation link in the first email.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "approvals" {
  name = "${var.project}-pipeline-approvals"
}

resource "aws_sns_topic_subscription" "approver" {
  topic_arn = aws_sns_topic.approvals.arn
  protocol  = "email"
  endpoint  = var.approval_email
}

data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${local.pipeline_name}-role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid = "ArtifactBucket"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "ArtifactBucketInfo"
    actions   = ["s3:GetBucketVersioning", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    sid       = "UseGitHubConnection"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  statement {
    sid       = "RunBuild"
    actions   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
    resources = [aws_codebuild_project.app.arn]
  }

  # The ECS deploy action reads the current task definition, registers a new revision with
  # the new image, then points the service at it. These calls cannot be limited to one ARN.
  statement {
    sid = "EcsDeployDescribeRegister"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EcsUpdateService"
    actions   = ["ecs:UpdateService"]
    resources = [local.ecs_service_arn, local.ecs_prod_service_arn]
  }

  statement {
    sid       = "NotifyApprover"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.approvals.arn]
  }

  statement {
    sid       = "PassTaskExecutionRole"
    actions   = ["iam:PassRole"]
    resources = [local.task_execution_role_arn, local.prod_task_execution_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "${local.pipeline_name}-policy"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

# ---------------------------------------------------------------------------
# The pipeline: GitHub -> CodeBuild -> ECS (dev).
# Runs on every push to the branch. V2 is billed per action-minute (cheap when idle).
# ---------------------------------------------------------------------------
resource "aws_codepipeline" "app" {
  name          = local.pipeline_name
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repository_id
        BranchName           = var.github_branch
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  stage {
    name = "DeployDev"

    action {
      name            = "DeployDev"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName       = var.ecs_cluster_name
        ServiceName       = var.ecs_service_name
        FileName          = "imagedefinitions.json"
        DeploymentTimeout = "10"
      }
    }
  }

  stage {
    name = "ApproveProd"

    action {
      name     = "Approve"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.approvals.arn
        CustomData      = "Dev deploy succeeded. Check the dev site, then approve to release the same image to prod."
      }
    }
  }

  stage {
    name = "DeployProd"

    action {
      name            = "DeployProd"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName       = var.ecs_prod_cluster_name
        ServiceName       = var.ecs_prod_service_name
        FileName          = "imagedefinitions.json"
        DeploymentTimeout = "10"
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]
}
