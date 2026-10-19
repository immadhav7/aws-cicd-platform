import os

def replace_once(s, old, new, label):
    if old not in s:
        print(f"WARNING: could not find: {label}")
        return s
    return s.replace(old, new, 1)

shots = [
    ("16-cloudwatch-dashboard-prod.png", "CloudWatch dashboard for prod: traffic, 5xx, latency, healthy targets, CPU and memory, and the rollback alarm"),
]

def root(s):
    if "## Observability" in s:
        print("README already has the Observability section, skipping")
        return s
    imgs = "".join(f"**{alt}**\n\n![{alt}](docs/images/{f})\n\n" for f, alt in shots if os.path.exists(f"docs/images/{f}"))
    section = '''## Observability

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

''' + imgs
    return replace_once(s, "## Problems solved along the way", section + "## Problems solved along the way", "Problems heading")

s = open("README.md").read()
t = root(s)
if t != s:
    open("README.md", "w").write(t); print("updated README.md")

def infra(s):
    if "## Phase 8:" in s:
        print("infra README already has Phase 8, skipping")
        return s
    new = '''## Phase 8: CloudWatch dashboards

`platform/dashboard.tf` adds one dashboard per environment (named like the environment, for example
`aws-cicd-prod`): traffic, 5xx with the rollback threshold, latency, healthy targets, ECS CPU and
memory, and in prod the green target group and the rollback alarm. The `dashboard_url` output has
the console link. `./scripts/demo-phase8.sh` brings the environments up, sends traffic to prod,
stops for a screenshot, then runs `./scripts/teardown.sh` and `./scripts/billing-check.sh`.

'''
    return replace_once(s, "## Cost", new + "## Cost", "Cost heading")

s = open("infra/README.md").read()
t = infra(s)
if t != s:
    open("infra/README.md", "w").write(t); print("updated infra/README.md")
