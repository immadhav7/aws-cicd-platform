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

variable "github_repository" {
  description = "GitHub repository allowed to assume the role, as owner/name"
  type        = string
  default     = "immadhav7/aws-cicd-platform"
}

variable "github_branch" {
  description = "Only workflow runs on this branch can assume the role"
  type        = string
  default     = "main"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository created by the registry module"
  type        = string
  default     = "aws-cicd-app"
}
