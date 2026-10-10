# Registry: the ECR repository that holds the app images.
# Kept separate from `platform/` so images SURVIVE teardown (an ECR repo costs almost nothing,
# but re-pushing images after every destroy would be annoying).

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Partial backend config, same pattern as network/: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "registry"
    }
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name used in tags"
  type        = string
  default     = "aws-cicd"
}

variable "repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "aws-cicd-app"
}

resource "aws_ecr_repository" "app" {
  name = var.repository_name

  # IMMUTABLE: a tag can never be overwritten, so a tag (a commit SHA from CodeBuild) always
  # points to the exact same image. Re-pushing an existing tag fails, which is the point.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep only the 10 most recent images so storage cost stays near zero.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_url" {
  description = "Full ECR URL, e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com/aws-cicd-app"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_name" {
  value = aws_ecr_repository.app.name
}
