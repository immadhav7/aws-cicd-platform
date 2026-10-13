# Lets GitHub Actions push images to ECR WITHOUT stored AWS keys.
# Workflow run -> GitHub issues a short-lived OIDC token -> AWS STS exchanges it for temporary
# credentials of the role below, but only for runs of this repository on the main branch.

data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

# One OIDC provider per AWS account. If this fails with "EntityAlreadyExists", the account
# already has one: remove this resource and reference the existing provider's ARN instead.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer validates this for GitHub, but older provider versions require the argument.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The important line: only this repository, only this branch.
    # GitHub now puts the numeric owner/repo IDs into the subject
    # (repo:owner@<id>/name@<id>:...), so the ID form is allowed as well as the plain one.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}",
        "repo:${var.github_repository_with_ids}:ref:
