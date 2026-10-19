import os

def replace_once(s, old, new, label):
    if old not in s:
        print(f"WARNING: could not find: {label}")
        return s
    return s.replace(old, new, 1)

shots = [
    ("07-codedeploy-deployment-group-blue-green-alarm-rollback.png", "CodeDeploy deployment group: blue/green, alarm and automatic rollback enabled"),
    ("08-codedeploy-good-deploy-canary-10-percent.png", "Good deploy: 10% of traffic on the new version, 90% still on the old one"),
    ("09-check-versions-prod-flipping-during-canary.png", "Prod answers with both versions while the traffic shifts"),
    ("10-codedeploy-good-deploy-succeeded.png", "Good deploy finished: 100% on the new version"),
    ("11-pipeline-five-stages-succeeded-blue-green.png", "Pipeline: DeployProd now runs through CodeDeploy"),
    ("12-codedeploy-bad-deploy-stopped-by-alarm.png", "Broken deploy: CodeDeploy stopped it because the alarm fired, and rolled back"),
    ("13-cloudwatch-alarm-5xx-in-alarm.png", "The 5xx alarm that triggered the rollback"),
    ("14-pipeline-deployprod-failed-after-rollback.png", "Pipeline after the rollback: DeployProd failed, prod untouched"),
    ("15-check-versions-prod-still-on-good-version.png", "Prod still serves the last good version after the failed release"),
]

def root(s):
    s = replace_once(s, "| 7 | Blue/green with CodeDeploy and automatic rollback | |", "| 7 | Blue/green with CodeDeploy and automatic rollback | Done |", "phase 7 row")
    if "demo-phase7.sh" not in s.split("## Blue/green")[0]:
      s = replace_once(s, "check-versions.sh (what is live in dev and prod)",
                       "check-versions.sh (what is live in dev and prod), load.sh, deploy-status.sh, fault.sh and demo-phase7.sh (the rollback demo), billing-check.sh",
                       "scripts line")
    if "## Blue/green deploys with automatic rollback" in s:
        print("README already has the Phase 7 section, skipping")
        return s
    imgs = "".join(f"**{alt}**\n\n![{alt}](docs/images/{f})\n\n" for f, alt in shots if os.path.exists(f"docs/images/{f}"))
    section = '''## Blue/green deploys with automatic rollback (prod)

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

''' + imgs
    return replace_once(s, "## Problems solved along the way", section + "## Problems solved along the way", "Problems heading")

s = open("README.md").read()
t = root(s)
if t != s:
    open("README.md", "w").write(t); print("updated README.md")

def infra(s):
    s = replace_once(s, "; CodeDeploy and alarms come in Phase 7", "; prod is deployed through CodeDeploy", "pipeline row")
    s = replace_once(s, "IAM execution role, log group |", "IAM execution role, log group; in prod also a second target group, CodeDeploy and the rollback alarm |", "platform row")
    if "## Phase 7:" in s:
        print("infra README already has Phase 7, skipping")
        return s
    new = '''## Phase 7: blue/green with automatic rollback

Prod only (the `prod` workspace): `platform/bluegreen.tf` adds a second target group, a CodeDeploy
application and deployment group, and a CloudWatch alarm on 5xx responses. The prod ECS service
uses the CodeDeploy deployment controller. The pipeline's `DeployProd` action starts a CodeDeploy
deployment using `taskdef.json` and `appspec.yaml`, which the build fills in from `deploy/`.

```bash
cd infra/pipeline && terraform apply     # DeployProd now calls CodeDeploy
cd ../network && terraform apply
cd ../platform
terraform workspace select default && terraform apply
terraform workspace select prod && terraform apply
terraform workspace select default
```

Traffic shifting is set by `deployment_config_name` (default: 10% first, the rest after 5 minutes).
The alarm threshold is `alarm_5xx_threshold` (default 5 errors in a minute).

The rollback demo (`./scripts/demo-phase7.sh`) does a good deploy, then a broken one:
`./scripts/fault.sh on` makes the home page return 500 while `/health` stays green, so only the
alarm can catch it. `./scripts/load.sh` sends traffic so the canary has requests to fail.
Afterwards `./scripts/teardown.sh` and `./scripts/billing-check.sh`.

'''
    return replace_once(s, "## Cost", new + "## Cost", "Cost heading")

s = open("infra/README.md").read()
t = infra(s)
if t != s:
    open("infra/README.md", "w").write(t); print("updated infra/README.md")
