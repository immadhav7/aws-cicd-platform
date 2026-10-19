# aws-cicd-platform

A multi-environment, AWS-native CI/CD platform: every push to `main` is built, tested, and
deployed to **dev**, then promoted to **prod** after manual approval using **blue/green
deployment with automatic rollback**.

The app is intentionally tiny. The platform around it is the project.


## Architecture

![Architecture: pipeline, dev and prod environments, blue/green with alarm rollback](docs/images/architecture-overview.png)

One pipeline builds the Docker image once, tags it with the 7-character commit SHA, and promotes the
same image: dev on every push, prod after a manual approval, deployed blue/green with a 10% canary.
A CloudWatch alarm on 5xx responses stops a bad prod release and rolls traffic back automatically.
Everything is Terraform (editable diagram source: `docs/architecture-overview.svg`).

## Highlights

- **One pipeline, two environments.** Source, Build, DeployDev, ApproveProd, DeployProd. The image is
  built once, tagged with the commit SHA and promoted, never rebuilt.
- **Blue/green with automatic rollback.** Prod deploys through CodeDeploy: 10% canary, 5 minutes,
  then the rest. A CloudWatch alarm on 5xx responses rolls traffic back with nobody watching.
- **All Terraform.** Five small root modules, one `platform` code base for both environments
  (workspaces), least-privilege IAM per service.
- **Observable.** A CloudWatch dashboard per environment, created with the platform.
- **Cheap to run.** `teardown.sh` and `billing-check.sh` bring the bill back to zero after every session.

## Prerequisites

An AWS account on a **paid plan** (CodeDeploy is not available on the free plan), Terraform 1.10 or
newer, the AWS CLI, Docker, and a GitHub repository. Step order is in `infra/README.md`.

## Repo layout

```
app/     Flask app (/health, /version), tests, Dockerfile
infra/   Terraform (bootstrap, registry, network, platform, pipeline)
buildspec.yml  CodeBuild steps: test, build image, push to ECR tagged with the commit SHA
deploy/  taskdef.json and appspec.yaml templates for the CodeDeploy blue/green deploy
scripts/ push-image.sh (manual push), run-pipeline.sh (start the pipeline), approve.sh (approve or reject prod), check-versions.sh (what is live in dev and prod), load.sh, deploy-status.sh, fault.sh and demo-phase7.sh (the rollback demo), demo-phase8.sh (the dashboard demo), billing-check.sh, teardown.sh (destroys billable infra)
```

## Roadmap

| Phase | What | Status |
|-------|------|--------|
| 0 | Setup: AWS account/IAM user, budget alert, repo | Done |
| 1 | Containerize the app | Done |
| 2 | Networking with Terraform (VPC, subnets, SGs, remote state) | Done |
| 3 | ECR + ECS Fargate + ALB, deployed manually | Done |
| 4 | CI with CodeBuild (test, build, push to ECR) | Done |
| 5 | CodePipeline for dev | Done |
| 6 | Multi-environment + manual approval | Done |
| 7 | Blue/green with CodeDeploy and automatic rollback | Done |
| 8 | Observability, diagram, README polish, teardown script | Done |

## Run the app locally

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pytest
BUILD_ID=local python app.py        # http://localhost:8080/version
```

## Run with Docker

```bash
cd app
docker build -t aws-cicd-app:local --build-arg BUILD_ID=local .
docker run --rm -p 8080:8080 aws-cicd-app:local
curl localhost:8080/health
curl localhost:8080/version
```

`/version` returns the build ID (the commit SHA in the pipeline). It is how we prove which
version is live after a deploy or a rollback.

## Pipeline (dev)

A push to `main` starts **CodePipeline**:

1. **Source**: GitHub, through a CodeStar connection (authorized once in the console).
2. **Build**: CodeBuild runs `buildspec.yml`: unit tests, `docker build`, `docker push` to ECR
   tagged with the 7-character commit SHA, then writes `imagedefinitions.json`.
3. **DeployDev**: the ECS deploy action registers a new task definition revision with that
   image and updates the Fargate service behind the ALB.

Design notes:

- ECR tags are immutable and SHA-based, so every running version maps to exactly one commit.
  Rebuilding a commit that already has an image reuses it instead of failing.
- `BUILD_ID` is baked into the image, so `/version` always reports the commit that is live.
- Terraform ignores the service's task definition after creation (`ignore_changes`), so a
  `terraform apply` never reverts a deploy made by the pipeline.
- IAM is least privilege per service: CodeBuild can push to one repository, CodePipeline can
  update one ECS service and pass one role.

### Screenshots

**Before: /version reports the manually pushed image (v1)**

![Before: /version reports the manually pushed image (v1)](docs/images/01-version-before-deploy-v1.png)

**Terraform creates the pipeline; the GitHub connection is authorized**

![Terraform creates the pipeline; the GitHub connection is authorized](docs/images/02-terraform-apply-pipeline-github-connection.png)

**CodePipeline: Source, Build and DeployDev all succeeded**

![CodePipeline: Source, Build and DeployDev all succeeded](docs/images/03-pipeline-all-stages-succeeded.png)

**CodeBuild writes imagedefinitions.json for the ECS deploy action**

![CodeBuild writes imagedefinitions.json for the ECS deploy action](docs/images/04-codebuild-log-imagedefinitions.png)

**ECR repository with immutable tags**

![ECR repository with immutable tags](docs/images/05-ecr-repository-immutable-tags.png)

**Images tagged with the commit SHA**

![Images tagged with the commit SHA](docs/images/06-ecr-images-sha-tags.png)

**After: the pipeline deployed the new commit and /version reports it**

![After: the pipeline deployed the new commit and /version reports it](docs/images/07-run-pipeline-and-version-after-deploy.png)

**ALB target group with a healthy target**

![ALB target group with a healthy target](docs/images/08-alb-target-group-healthy.png)

**AWS approved the CodeBuild quota increase**

![AWS approved the CodeBuild quota increase](docs/images/09-aws-quota-increase-approved.png)

## Environments and manual approval (dev and prod)

```
Source -> Build -> DeployDev -> ApproveProd (email) -> DeployProd
```

- **One image, promoted.** The image is built once and tagged with the commit SHA. Prod gets
  exactly the image that ran in dev; nothing is rebuilt between environments.
- **Environments are Terraform workspaces** of the same `infra/platform` code: `default` is dev,
  `prod` is prod. Each has its own state, ALB, ECS cluster, service and IAM role. Dev runs one
  task, prod runs two. (One account keeps this cheap; for stronger isolation I would use a
  separate AWS account per environment.)
- **Manual approval.** CodePipeline publishes to an SNS topic, which emails the approver.
  Approve in the console or with `./scripts/approve.sh`; `./scripts/approve.sh reject` stops the
  release and `DeployProd` never runs.
- `./scripts/check-versions.sh` shows what is live in each environment, so the gate is visible:
  dev runs the new commit while prod stays on the old one until someone approves.

**Both environments created from the same Terraform code (prod is still warming up)**

![Both environments created from the same Terraform code (prod is still warming up)](docs/images/01-environments-created-dev-v1-prod-warming-up.png)

**Separate ECS clusters: dev runs 1 task, prod runs 2**

![Separate ECS clusters: dev runs 1 task, prod runs 2](docs/images/02-ecs-clusters-dev-1-task-prod-2-tasks.png)

**SNS asks the approver to confirm the email subscription**

![SNS asks the approver to confirm the email subscription](docs/images/03-sns-subscription-confirmation-email.png)

**Subscription confirmed**

![Subscription confirmed](docs/images/04-sns-subscription-confirmed.png)

**The approval gate at work: dev already runs the new commit, prod still runs v1**

![The approval gate at work: dev already runs the new commit, prod still runs v1](docs/images/05-approval-gate-dev-new-sha-prod-still-v1.png)

**Pipeline: Source, Build, DeployDev, ApproveProd, DeployProd**

![Pipeline: Source, Build, DeployDev, ApproveProd, DeployProd](docs/images/06-pipeline-five-stages-succeeded-with-approval.png)

## Blue/green deploys with automatic rollback (prod)

```
Source -> Build -> DeployDev -> ApproveProd -> DeployProd (CodeDeploy blue/green, canary)
```

- **Blue/green.** CodeDeploy starts the new version in a second target group next to the running
  one, sends 10% of the traffic to it, waits 5 minutes, then sends the rest. The old tasks stay
  around for a minute before they stop. Dev keeps the plain ECS rolling deploy.
- **Automatic rollback.** A CloudWatch alarm watches the 5xx responses the app returns. If it fires
  while a deployment runs, or the deployment fails, CodeDeploy moves all traffic back to the old
  version by itself and the pipeline's `DeployProd` action fails. Nobody has to react.
- **Why 5xx and not just health checks.** A bad release often passes `/health` and still breaks real
  requests. The demo flips `SIMULATE_FAULT` in `deploy/taskdef.json`: `/health` stays green, the home
  page returns 500. The health check would have let it through; the alarm catches it.
- **How to see it.** `./scripts/demo-phase7.sh` runs the whole thing (good deploy, broken deploy,
  rollback, teardown). `./scripts/deploy-status.sh` shows the last deployment and why it ended.
- **Known limits.** `deploy/taskdef.json` repeats the settings of the Terraform task definition, so
  the two must be kept in step. The alarm only sees traffic that reaches the ALB, which is why the demo
  sends requests while the canary runs. After a rollback the alarm needs a couple of minutes to clear
  before the next deploy can start.

**CodeDeploy deployment group: blue/green, alarm and automatic rollback enabled**

![CodeDeploy deployment group: blue/green, alarm and automatic rollback enabled](docs/images/07-codedeploy-deployment-group-blue-green-alarm-rollback.png)

**Prod answers with both versions while the traffic shifts**

![Prod answers with both versions while the traffic shifts](docs/images/09-check-versions-prod-flipping-during-canary.png)

**Good deploy finished: 100% on the new version**

![Good deploy finished: 100% on the new version](docs/images/10-codedeploy-good-deploy-succeeded.png)

**Pipeline: DeployProd now runs through CodeDeploy**

![Pipeline: DeployProd now runs through CodeDeploy](docs/images/11-pipeline-five-stages-succeeded-blue-green.png)

**Broken deploy: CodeDeploy stopped it because the alarm fired, and rolled back**

![Broken deploy: CodeDeploy stopped it because the alarm fired, and rolled back](docs/images/12-codedeploy-bad-deploy-stopped-by-alarm.png)

**The 5xx alarm that triggered the rollback**

![The 5xx alarm that triggered the rollback](docs/images/13-cloudwatch-alarm-5xx-in-alarm.png)

**Pipeline after the rollback: DeployProd failed, prod untouched**

![Pipeline after the rollback: DeployProd failed, prod untouched](docs/images/14-pipeline-deployprod-failed-after-rollback.png)

## Observability

Each environment gets its own CloudWatch dashboard, created by Terraform with the platform
(`infra/platform/dashboard.tf`). It answers "is it healthy right now?" at a glance:

- **Traffic and errors.** Requests, successful answers and 5xx answers per minute at the load balancer.
  The 5xx graph has the prod rollback threshold drawn on it.
- **Latency.** Average and p95 response time of the app.
- **Targets.** Healthy and unhealthy tasks behind the load balancer; in prod also the green target
  group, which is the new version during a deploy.
- **ECS service.** CPU and memory of the Fargate tasks.
- **Rollback alarm (prod).** The same alarm that stops a bad deploy, so the state of a release and
  the reason for a rollback are on one screen.

The dashboards are part of the platform stack, so they are created and destroyed with it (the
first 3 dashboards in an account are free).

**CloudWatch dashboard for prod: traffic, 5xx, latency, healthy targets, CPU and memory, and the rollback alarm**

![CloudWatch dashboard for prod: traffic, 5xx, latency, healthy targets, CPU and memory, and the rollback alarm](docs/images/16-cloudwatch-dashboard-prod.png)

## Design decisions and trade-offs

- **Build once, promote.** Prod runs the exact image that passed in dev. Rebuilding per environment
  would make "tested in dev" mean nothing.
- **Workspaces for environments.** Same code, separate state, so dev and prod cannot drift apart in
  structure. For real isolation I would use one AWS account per environment.
- **Alarm on 5xx, not only health checks.** A bad release can pass `/health` and still fail real requests.
- **Pipeline stays up, platform goes down.** The pipeline costs pennies and keeps the GitHub connection
  authorized; the NAT gateway, ALBs and tasks are what bill, so only those are destroyed.
- **Terraform ignores the task definition after creation.** The pipeline owns deploys, so
  `terraform apply` never reverts a release.

## Problems solved along the way

- **CodeBuild quota was 0** on a new account. I requested an increase (approved: 15 concurrent
  builds) and meanwhile built a GitHub Actions stopgap that pushes to ECR through **OIDC with no
  stored AWS keys**. It was removed once CodeBuild worked.
- **GitHub changed the OIDC subject claim** to include numeric owner and repository IDs
  (`repo:owner@id/name@id:...`). The role's trust policy rejected the token until it accepted
  that form too. I found it by decoding the token claims in a debug step.
- **Immutable tags vs re-runs**: re-running a build for the same commit used to fail at
  `docker push`; the build now checks ECR first and reuses the image.

- **CodeDeploy needed a paid plan.** The deployment failed with `SubscriptionRequiredException` on
  the free plan; upgrading fixed it.
- **The pipeline role was missing three permissions** for the CodeDeploy deploy action
  (`codedeploy:GetApplication`, `ecs:RegisterTaskDefinition`, `iam:PassRole` limited to the prod
  roles). Found in the pipeline's error message and added to the Terraform policy.
- **Rollback goes to the last successful deployment.** A broken release that CodeDeploy counted as
  successful became the rollback target, so the next rollback restored the broken build. Lesson: the
  alarm must fire during the canary, and the demo needs traffic (`load.sh`) for that.
- **The alarm only sees traffic that reaches the ALB**, and 5xx metrics exist only when errors occur,
  so an empty 5xx graph means zero errors, not a broken graph.

## Cost control

The NAT gateway, two ALBs (dev and prod) and the Fargate tasks bill by the hour: roughly 0.15 USD per
hour with both environments up. Create them for a working session and destroy them afterwards:

```bash
./scripts/teardown.sh        # destroys prod, then dev, then the network
./scripts/billing-check.sh   # prints "All clear" when nothing billable is left
```

The state bucket, the ECR repository and the pipeline stay (pennies per month). While the platform is
down the pipeline's Deploy stages fail harmlessly; use `[skip ci]` in docs-only commits.
