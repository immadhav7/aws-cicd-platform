# infra

Terraform for the platform, split into small root modules so each phase can be applied
(and destroyed) independently.

| Module | Purpose | Phase |
|--------|---------|-------|
| `bootstrap/` | S3 bucket for Terraform state (local state, applied once, never destroyed) | 2 |
| `network/` | VPC, 2 public + 2 private subnets, IGW, NAT, route tables, ALB/app security groups | 2 |
| `platform/` | ECR, ECS cluster/service, ALB | 3 (next) |
| `pipeline/` | CodeBuild, CodePipeline, CodeDeploy, CloudWatch alarms | 5-7 |

Requires Terraform **>= 1.10** (S3 native state locking, no DynamoDB table needed) and
AWS credentials (`aws sts get-caller-identity` should work).

## Phase 2: first run

```bash
# 1. Create the state bucket (once)
cd infra/bootstrap
terraform init
terraform apply
terraform output -raw state_bucket      # copy this name

# 2. Create the network
cd ../network
cp backend.hcl.example backend.hcl      # then paste the bucket name into backend.hcl
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Check in the console (VPC, then Your VPCs / Subnets / Security groups) that you see
`aws-cicd-vpc`, 2 public and 2 private subnets in different AZs, and the two security groups.

## Cost

The **NAT gateway** (plus its Elastic IP) is billed per hour while it exists. Destroy the
network when you stop for the day:

```bash
./scripts/teardown.sh
```

The `bootstrap` bucket stays (it costs almost nothing and holds your state).

Never commit `*.tfstate`, `backend.hcl` or real `*.tfvars` files (already in `.gitignore`).
