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

variable "github_repository_url" {
  description = "HTTPS clone URL of the (public) GitHub repository CodeBuild builds from"
  type        = string
  default     = "https://github.com/immadhav7/aws-cicd-platform.git"
}

variable "source_version" {
  description = "Branch (or commit) built by default when a build is started without one"
  type        = string
  default     = "main"
}
