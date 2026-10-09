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
infra/   Terraform (VPC, ECR, ECS, ALB, pipeline, alarms)
```

## Roadmap

| Phase | What | Status |
|-------|------|--------|
| 0 | Setup: AWS account/IAM user, budget alert, repo | In progress |
| 1 | Containerize the app | Done (locally) |
| 2 | Networking with Terraform (VPC, subnets, SGs, remote state) | |
| 3 | ECR + ECS Fargate + ALB, deployed manually | |
| 4 | CI with CodeBuild (test, build, push to ECR) | |
| 5 | CodePipeline for dev | |
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

## Cost control

The ALB, NAT gateway, and Fargate tasks cost money while running. Run `terraform destroy`
after every working session.
