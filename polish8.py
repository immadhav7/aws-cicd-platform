#!/usr/bin/env python3
"""Phase 8 README polish. Run from the repo root. Refuses to run twice."""
import pathlib, sys

R = pathlib.Path("README.md")
I = pathlib.Path("infra/README.md")
assert R.exists() and I.exists(), "run this from the repo root"
r = R.read_text()
i = I.read_text()
if "## Highlights" in r:
    sys.exit("already polished, nothing to do")

def swap(text, old, new):
    assert text.count(old) == 1, f"expected exactly one match for: {old[:60]!r}"
    return text.replace(old, new)

# ---- README.md ----------------------------------------------------------
a = r.index("## Target architecture")
b = r.index("## Repo layout")
intro = """## Highlights

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

"""
r = r[:a] + intro + r[b:]

r = swap(r, "pipeline; later alarms)", "pipeline)")
r = swap(r, "scripts/ push-image.sh",
         "deploy/  taskdef.json and appspec.yaml templates for the CodeDeploy blue/green deploy\nscripts/ push-image.sh")
r = swap(r, "fault.sh and demo-phase7.sh (the rollback demo),",
         "fault.sh and demo-phase7.sh (the rollback demo), demo-phase8.sh (the dashboard demo),")
r = swap(r, "| 0 | Setup: AWS account/IAM user, budget alert, repo | In progress |",
         "| 0 | Setup: AWS account/IAM user, budget alert, repo | Done |")
r = swap(r, "| 8 | Observability, diagram, README polish, teardown script | |",
         "| 8 | Observability, diagram, README polish, teardown script | Done |")

d = r.index("## Problems solved along the way")
decisions = """## Design decisions and trade-offs

- **Build once, promote.** Prod runs the exact image that passed in dev. Rebuilding per environment
  would make "tested in dev" mean nothing.
- **Workspaces for environments.** Same code, separate state, so dev and prod cannot drift apart in
  structure. For real isolation I would use one AWS account per environment.
- **Alarm on 5xx, not only health checks.** A bad release can pass `/health` and still fail real requests.
- **Pipeline stays up, platform goes down.** The pipeline costs pennies and keeps the GitHub connection
  authorized; the NAT gateway, ALBs and tasks are what bill, so only those are destroyed.
- **Terraform ignores the task definition after creation.** The pipeline owns deploys, so
  `terraform apply` never reverts a release.

"""
r = r[:d] + decisions + r[d:]

c = r.index("## Cost control")
problems_tail = """- **CodeDeploy needed a paid plan.** The deployment failed with `SubscriptionRequiredException` on
  the free plan; upgrading fixed it.
- **The pipeline role was missing three permissions** for the CodeDeploy deploy action
  (`codedeploy:GetApplication`, `ecs:RegisterTaskDefinition`, `iam:PassRole` limited to the prod
  roles). Found in the pipeline's error message and added to the Terraform policy.
- **Rollback goes to the last successful deployment.** A broken release that CodeDeploy counted as
  successful became the rollback target, so the next rollback restored the broken build. Lesson: the
  alarm must fire during the canary, and the demo needs traffic (`load.sh`) for that.
- **The alarm only sees traffic that reaches the ALB**, and 5xx metrics exist only when errors occur,
  so an empty 5xx graph means zero errors, not a broken graph.

"""
r = r[:c] + problems_tail + """## Cost control

The NAT gateway, two ALBs (dev and prod) and the Fargate tasks bill by the hour: roughly 0.15 USD per
hour with both environments up. Create them for a working session and destroy them afterwards:

```bash
./scripts/teardown.sh        # destroys prod, then dev, then the network
./scripts/billing-check.sh   # prints "All clear" when nothing billable is left
```

The state bucket, the ECR repository and the pipeline stay (pennies per month). While the platform is
down the pipeline's Deploy stages fail harmlessly; use `[skip ci]` in docs-only commits.
"""

# ---- infra/README.md ----------------------------------------------------
i = swap(i, "second target group, CodeDeploy and the rollback alarm |",
         "second target group, CodeDeploy and the rollback alarm; a CloudWatch dashboard per environment |")
i = swap(i, "`bootstrap` -> `registry` -> (push image) -> `network` -> `platform`.",
         "`bootstrap` -> `registry` -> (push image) -> `network` -> `platform` -> `pipeline`.")
i = swap(i, "AWS credentials (`aws sts get-caller-identity` should work).\n",
         "AWS credentials (`aws sts get-caller-identity` should work). CodeDeploy (phase 7) needs a paid AWS plan.\n")
i = swap(i, "(very roughly $0.10 per hour together)", "(roughly $0.15 per hour with dev and prod both up)")
i = swap(i, "```bash\n./scripts/teardown.sh\n```\n\n`bootstrap`",
         "```bash\n./scripts/teardown.sh\n./scripts/billing-check.sh    # must print \"All clear\"\n```\n\n`bootstrap`")

R.write_text(r)
I.write_text(i)
print("README.md and infra/README.md polished")
