# infra

Terraform for the platform, split into small root modules so each phase can be applied
(and destroyed) independently.

| Module | Purpose | Phase | Destroyed by teardown? |
|--------|---------|-------|------------------------|
| `bootstrap/` | S3 bucket for Terraform state (local state, applied once) | 2 | No |
| `registry/` | ECR repository for the app images | 3 | No (images survive) |
| `network/` | VPC, 2 public + 2 private subnets, IGW, NAT, route tables, ALB/app security groups | 2 | Yes |
| `platform/` | ECS cluster, Fargate service, ALB, target group, IAM execution role, log group | 3 | Yes (first) |
| `pipeline/` | CodeBuild, CodePipeline (GitHub, build, deploy to dev), GitHub connection, artifact bucket; CodeDeploy and alarms come in Phase 7 | 4-5 | No (idle cost is pennies, and it keeps the GitHub connection authorized) |

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

## Phase 4 and 5: CodeBuild and CodePipeline

The pipeline module creates the CodeBuild project, the artifact bucket, the GitHub connection
and the pipeline. It deploys to the ECS service created by `platform/`, so apply that first.
Push `buildspec.yml` to GitHub before the first run: the pipeline builds what is on GitHub.

```bash
# 1. Registry: tags become immutable (skip if already applied)
cd infra/registry && terraform apply

# 2. Network and platform (billing starts)
cd ../network  && terraform apply
cd ../platform && terraform apply

# 3. Pipeline
cd ../pipeline
sed 's/REPLACE_WITH_STATE_BUCKET_NAME/<BUCKET>/' backend.hcl.example > backend.hcl
terraform init -backend-config=backend.hcl
terraform apply
```

The GitHub connection is created in PENDING state. Authorize it once: console (Mumbai), Developer
Tools, Settings, Connections, `aws-cicd-github`, Update pending connection, install the GitHub
app for this repository. Check it:

```bash
aws codestar-connections list-connections --region ap-south-1 \
  --query 'Connections[].[ConnectionName,ConnectionStatus]' --output text   # AVAILABLE
```

Run the pipeline and check the deployed version (from the repo root):

```bash
./scripts/run-pipeline.sh
curl "http://$(terraform -chdir=infra/platform output -raw alb_dns_name)/version"
```

`build_id` is the 7-character commit SHA that CodeBuild tagged and ECS is now running. Every
later push to `main` starts the pipeline by itself. If the platform is destroyed, the Deploy
stage fails harmlessly; add `[skip ci]` to a commit message to avoid starting a run.

## Phase 6: prod environment and manual approval

`platform/` builds one environment per Terraform workspace: `default` is dev, `prod` is prod
(any other workspace name is rejected). The environments share the network, so apply that first.

```bash
cd infra/platform
terraform apply                  # dev (default workspace)
terraform workspace new prod     # creates and switches to the prod workspace
terraform apply                  # prod
terraform workspace select default
```

The pipeline module needs an approval email address (git-ignored):

```bash
cd infra/pipeline
printf 'approval_email = "you@example.com"\n' > terraform.tfvars
terraform apply
```

SNS sends a confirmation email: click "Confirm subscription" once. Then run
`./scripts/run-pipeline.sh`; when it waits at ApproveProd, approve by email link, in the
console, or with `./scripts/approve.sh`. `./scripts/check-versions.sh` shows dev and prod.
`./scripts/teardown.sh` destroys prod, then dev, then the network.

## Cost

While running, the **NAT gateway**, the **ALB** and the **Fargate task** all bill by the hour
(very roughly $0.10 per hour together). Destroy them when you stop for the day:

```bash
./scripts/teardown.sh
```

`bootstrap` (state) and `registry` (images) stay, since they cost almost nothing.

Never commit `*.tfstate`, `backend.hcl` or real `*.tfvars` files (already in `.gitignore`).
