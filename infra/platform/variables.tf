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

variable "environment" {
  description = "Environment name (dev now; prod is added in Phase 6)"
  type        = string
  default     = "dev"
}

variable "state_bucket" {
  description = "S3 bucket holding Terraform state (needed to read the network module's outputs)"
  type        = string
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository created by the registry module"
  type        = string
  default     = "aws-cicd-app"
}

variable "image_tag" {
  description = "Image tag to deploy. Push it first with scripts/push-image.sh <tag>"
  type        = string
  default     = "v1"
}

variable "app_port" {
  description = "Container port (must match the Dockerfile and the network module's security groups)"
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "Number of running tasks"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}
