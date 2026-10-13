# aws-cicd-platform

A multi-environment, AWS-native CI/CD platform: every push to `main` is built, tested, and
deployed to **dev**, then promoted to **prod** after manual approval using **blue/green
deployment with automatic rollback**.

The app is intentionally tiny. The platform around it is the project.

## Target architecture

```
GitHub --> CodePipeline --> CodeBuild --> ECR
                |
                +--> Deploy (dev)  ECS Fargate + ALB
                +--> Manual approval (SNS email)
                +--> Deploy (prod) ECS Fargate + ALB, CodeDeploy blue/green
                                   rollback on CloudWatch alarm
```

Everything is created with Terraform. Config lives in SSM Parameter Store, secrets in
Secrets Manager.

## Repo layout

```
app/     Flask app (/health, /version), tests, Dockerfile
infra/   Terraform (bootstrap, registry, network, platform, pipeline; later alarms)
buildspec.yml  CodeBuild steps: test, build image, push to ECR tagged with the commit SHA
scripts/ push-image.sh (manual push), run-pipeline.sh (start the pipeline), teardown.sh (destroys billable infra)
```

## Roadmap

| Phase | What | Status |
|-------|------|--------|
| 0 | Setup: AWS account/IAM user, budget alert, repo | In progress |
| 1 | Containerize the app | Done |
| 2 | Networking with Terraform (VPC, subnets, SGs, remote state) | Done |
| 3 | ECR + ECS Fargate + ALB, deployed manually | Done |
| 4 | CI with CodeBuild (test, build, push to ECR) | Done |
| 5 | CodePipeline for dev | Done |
| 6 | Multi-environment + manual approval | |
| 7 | Blue/green with CodeDeploy and automatic rollback | |
| 8 | Observability, diagram, README polish, teardown script | |

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

## Problems solved along the way

- **CodeBuild quota was 0** on a new account. I requested an increase (approved: 15 concurrent
  builds) and meanwhile built a GitHub Actions stopgap that pushes to ECR through **OIDC with no
  stored AWS keys**. It was removed once CodeBuild worked.
- **GitHub changed the OIDC subject claim** to include numeric owner and repository IDs
  (`repo:owner@id/name@id:...`). The role's trust policy rejected the token until it accepted
  that form too. I found it by decoding the token claims in a debug step.
- **Immutable tags vs re-runs**: re-running a build for the same commit used to fail at
  `docker push`; the build now checks ECR first and reuses the image.

## Cost control

The ALB, NAT gateway, and Fargate tasks cost money while running. Run `terraform destroy`
after every working session.

CodeBuild quota approved (15 concurrent Linux/Small builds, ap-south-1).
