# infra

Terraform for the platform, split into small root modules so each phase can be applied
(and destroyed) independently.

| Module | Purpose | Phase | Destroyed by teardown? |
|--------|---------|-------|------------------------|
| `bootstrap/` | S3 bucket for Terraform state (local state, applied once) | 2 | No |
| `registry/` | ECR repository for the app images | 3 | No (images survive) |
| `network/` | VPC, 2 public + 2 private subnets, IGW, NAT, route tables, ALB/app security groups | 2 | Yes |
| `platform/` | ECS cluster, Fargate service, ALB, target group, IAM execution role, log group | 3 | Yes (first) |
| `pipeline/` | CodeBuild project now; CodePipeline, CodeDeploy and alarms in Phases 5-7 | 4+ | No (CodeBuild costs nothing while idle) |

Requires Terraform **>= 1.10** (S3 native state locking, no DynamoDB table needed) and
AWS credentials (`aws sts get-caller-identity` should work).

Dependency order: `bootstrap` -> `registry` -> (push image) -> `network` -> `platform`.
Teardown runs the other way round (`platform`, then `network`).

## Phase 2: state bucket and network

```bash
cd infra/bootstrap
terraform init && terraform apply
terraform output -raw state_bucket      # copy this name

cd ../network
cp backend.hcl.example backend.hcl      # paste the bucket name into backend.hcl
terraform init -backend-config=backend.hcl
terraform apply
```

## Phase 3: registry, image, platform

```bash
# 1. ECR repository (once; it is not destroyed by teardown)
cd infra/registry
cp backend.hcl.example backend.hcl      # paste the bucket name
terraform init -backend-config=backend.hcl
terraform apply

# 2. Build and push the first image (from the repo root)
cd ../..
./scripts/push-image.sh v1

# 3. Make sure the network is applied (it is destroyed at teardown), then the platform
cd infra/network && terraform apply
cd ../platform
cp backend.hcl.example backend.hcl            # paste the bucket name
cp terraform.tfvars.example terraform.tfvars  # paste the bucket name here too
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 4. Test through the load balancer
curl "http://$(terraform output -raw alb_dns_name)/health"
curl "http://$(terraform output -raw alb_dns_name)/version"
```

`/version` should return `{"build_id":"v1","environment":"dev"}`. The service needs about
a minute after `apply` to pass its first health checks, so a 503 right away is normal.

## Phase 4: CodeBuild

CodeBuild clones the repo from GitHub, so `buildspec.yml` must be **pushed to GitHub first**.

```bash
# 1. Registry: tags become immutable (in-place change)
cd infra/registry && terraform apply

# 2. CodeBuild project
cd ../pipeline
sed 's/REPLACE_WITH_STATE_BUCKET_NAME/<BUCKET>/' backend.hcl.example > backend.hcl
terraform init -backend-config=backend.hcl
terraform apply

# 3. Run a build (from the repo root) and watch it
cd ../..
./scripts/start-build.sh
```

A successful build runs the tests, builds the image and pushes it to ECR tagged with the
7-character commit SHA. Re-running a build for a commit that already has an image fails at the
push step: immutable tags never overwrite an image, so make a new commit instead.

## Cost

While running, the **NAT gateway**, the **ALB** and the **Fargate task** all bill by the hour
(very roughly $0.10 per hour together). Destroy them when you stop for the day:

```bash
./scripts/teardown.sh
```

`bootstrap` (state) and `registry` (images) stay, since they cost almost nothing.

Never commit `*.tfstate`, `backend.hcl` or real `*.tfvars` files (already in `.gitignore`).
