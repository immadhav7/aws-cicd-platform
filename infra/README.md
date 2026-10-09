# infra

Terraform for the platform. Built phase by phase:

- Phase 2: `network/` (VPC, subnets, security groups) and remote state in S3
- Phase 3: ECR, ECS cluster/service, ALB
- Phase 5-7: CodeBuild, CodePipeline, CodeDeploy, CloudWatch alarms

Never commit `*.tfstate` or real `*.tfvars` files (already in `.gitignore`).
