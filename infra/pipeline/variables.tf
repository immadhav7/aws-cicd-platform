variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name used in resource names and tags"
  type        = string
  default     = "aws-cicd"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository created by the registry module"
  type        = string
  default     = "aws-cicd-app"
}

variable "github_repository_id" {
  description = "GitHub repository the pipeline builds, as owner/name"
  type        = string
  default     = "immadhav7/aws-cicd-platform"
}

variable "github_branch" {
  description = "Branch whose pushes start the pipeline"
  type        = string
  default     = "main"
}

variable "ecs_cluster_name" {
  description = "ECS cluster the dev deploy stage updates (created by infra/platform)"
  type        = string
  default     = "aws-cicd-dev"
}

variable "ecs_service_name" {
  description = "ECS service the dev deploy stage updates (created by infra/platform)"
  type        = string
  default     = "aws-cicd-dev"
}

variable "task_execution_role_name" {
  description = "Name of the ECS task execution role (created by infra/platform); the deploy stage passes it to new task definitions"
  type        = string
  default     = "aws-cicd-dev-task-execution"
}

variable "approval_email" {
  description = "Email address that receives the manual approval request (set it in terraform.tfvars, which is git-ignored)"
  type        = string
}

variable "ecs_prod_cluster_name" {
  description = "ECS cluster the prod deploy stage updates (created by infra/platform, workspace prod)"
  type        = string
  default     = "aws-cicd-prod"
}

variable "ecs_prod_service_name" {
  description = "ECS service the prod deploy stage updates (created by infra/platform, workspace prod)"
  type        = string
  default     = "aws-cicd-prod"
}

variable "prod_task_execution_role_name" {
  description = "Name of the prod ECS task execution role (created by infra/platform, workspace prod)"
  type        = string
  default     = "aws-cicd-prod-task-execution"
}
