# github-oidc (retired stopgap)

This module was only needed while the CodeBuild quota was 0. CodePipeline and CodeBuild now do
the build, so it is no longer used. To remove it: `terraform destroy` in this folder.

Original description:

AWS blocked CodeBuild on this account (concurrent builds quota = 0, increase requested), so
GitHub Actions builds and pushes the image instead. It uses the same steps and the same
7-character commit SHA tags as `buildspec.yml`, so switching back to CodeBuild later changes
nothing downstream.

This module creates (all free):

- the GitHub OIDC identity provider for the AWS account
- an IAM role GitHub Actions can assume, **only** for runs of this repository on `main`
- a policy that allows pushing to the one ECR repository and nothing else

No AWS access keys are stored in GitHub.

## Set up

```bash
cd infra/github-oidc
sed 's/REPLACE_WITH_STATE_BUCKET_NAME/<BUCKET>/' backend.hcl.example > backend.hcl
terraform init -backend-config=backend.hcl
terraform apply            # 3 resources
terraform output -raw role_arn
```

Then in GitHub: repository **Settings, Secrets and variables, Actions, Variables tab, New
repository variable**: name `AWS_ROLE_ARN`, value = the role ARN above. (It is not a secret.)

Push the workflow (`.github/workflows/build-push.yml`) and watch the **Actions** tab.

## Removing it later

When CodeBuild works, delete the workflow file and run `terraform destroy` here.
