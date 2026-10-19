import os, sys

def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    open(path, "w").write(text)
    if mode:
        os.chmod(path, mode)
    print("wrote", path)

for must in ("infra/platform/bluegreen.tf", "infra/platform/main.tf", "scripts/load.sh", "scripts/teardown.sh", "scripts/billing-check.sh"):
    if not os.path.exists(must):
        sys.exit(f"ERROR: run this from the repo root with Phase 7 applied (cannot see {must})")
if os.path.exists("infra/platform/dashboard.tf"):
    sys.exit("Phase 8 is already applied in this repo (infra/platform/dashboard.tf exists). Nothing to do.")

# ---------------------------------------------------------------- one CloudWatch dashboard per environment
write("infra/platform/dashboard.tf", r'''# Phase 8: a CloudWatch dashboard per environment (dev and prod each get their own).
#
# It shows what the platform is doing right now: traffic and errors at the load balancer, how fast
# the app answers, how many targets are healthy, and the CPU and memory of the ECS service.
# In prod it also shows the green target group and the rollback alarm from bluegreen.tf, and the
# 5xx graph has the rollback threshold drawn on it. The first 3 dashboards in an account are free.

data "aws_region" "dashboard" {}

locals {
  dash_region   = data.aws_region.dashboard.name
  dash_alb      = aws_lb.app.arn_suffix
  dash_tg       = aws_lb_target_group.app.arn_suffix
  dash_tg_green = try(aws_lb_target_group.green[0].arn_suffix, "")
  dash_alarm    = try(aws_cloudwatch_metric_alarm.http_5xx[0].arn, "")

  # Widgets both environments have.
  dash_common = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title   = "Traffic: requests and successful answers per minute"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.dash_alb, { stat = "Sum", label = "requests" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", local.dash_alb, { stat = "Sum", label = "2xx answers" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 0
      width  = 12
      height = 6
      properties = {
        title   = "Errors: 5xx answers from the app per minute"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.dash_alb, { stat = "Sum", label = "5xx answers", color = "#d62728" }],
        ]
        annotations = {
          horizontal = [
            { label = "prod rolls back at this level", value = var.alarm_5xx_threshold, color = "#d62728" },
          ]
        }
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        title   = "Latency: how long the app takes to answer (seconds)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.dash_alb, { stat = "Average", label = "average" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.dash_alb, { stat = "p95", label = "p95" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        title   = "Targets: healthy and unhealthy tasks (main target group)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.dash_tg, "LoadBalancer", local.dash_alb, { stat = "Minimum", label = "healthy" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.dash_tg, "LoadBalancer", local.dash_alb, { stat = "Maximum", label = "unhealthy" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        title   = "ECS service: CPU and memory (%)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "CPU" }],
          ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "memory" }],
        ]
      }
    },
  ]

  # Extra widgets for prod only (blue/green). They are built in dev too but never used there.
  dash_prod_extra = [
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        title   = "Targets: healthy tasks in the green target group (new version during a deploy)"
        region  = local.dash_region
        view    = "timeSeries"
        stacked = false
        period  = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.dash_tg_green, "LoadBalancer", local.dash_alb, { stat = "Minimum", label = "healthy (green)" }],
        ]
      }
    },
    {
      type   = "alarm"
      x      = 0
      y      = 18
      width  = 12
      height = 3
      properties = {
        title  = "Rollback alarm"
        alarms = [local.dash_alarm]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = local.blue_green ? jsonencode({ widgets = concat(local.dash_common, local.dash_prod_extra) }) : jsonencode({ widgets = local.dash_common })
}

output "dashboard_url" {
  description = "Console link to this environment's CloudWatch dashboard"
  value       = "https://${local.dash_region}.console.aws.amazon.com/cloudwatch/home?region=${local.dash_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
''')

# ---------------------------------------------------------------- the demo that makes the screenshot
write("scripts/demo-phase8.sh", r'''#!/usr/bin/env bash
# Phase 8 demo: bring up network, dev and prod, send traffic to prod, wait until the CloudWatch
# dashboard has data, stop for a screenshot, then tear everything down.
# Takes about 30 minutes. Run it from anywhere:  ./scripts/demo-phase8.sh
# Needs: phase 8 applied (python3 phase8.py), the default and prod workspaces already created.
set -uo pipefail
cd "$(dirname "$0")/.."

LOAD_PID=""
cleanup() { [ -n "${LOAD_PID}" ] && kill "${LOAD_PID}" 2>/dev/null; }
trap cleanup EXIT
trap 'echo; echo "Interrupted. Run ./scripts/teardown.sh so nothing keeps billing."; exit 130' INT TERM

die() { echo "ERROR: $*" >&2; echo "If AWS resources exist, run ./scripts/teardown.sh when you are done." >&2; exit 1; }
pause() { echo; echo ">>> $1"; read -r -p "    Press Enter when you are done... " _; }

echo "=============================================================="
echo " Phase 8 demo. AWS billing runs from step 1 until the teardown"
echo " at the end (roughly 0.15 USD per hour, about 30 minutes)."
echo "=============================================================="
read -r -p "Type yes to start: " ok
[ "${ok}" = "yes" ] || exit 0

aws sts get-caller-identity > /dev/null || die "AWS credentials do not work"
[ -f infra/platform/dashboard.tf ] || die "run python3 phase8.py first"

echo; echo "==> 1/4  Creating network, dev and prod"
terraform -chdir=infra/network apply -auto-approve || die "network apply failed"
terraform -chdir=infra/platform workspace select default || die "workspace select failed"
terraform -chdir=infra/platform apply -auto-approve || die "dev apply failed"
terraform -chdir=infra/platform workspace select prod || die "workspace select failed"
terraform -chdir=infra/platform apply -auto-approve || die "prod apply failed"
DASH="$(terraform -chdir=infra/platform output -raw dashboard_url 2>/dev/null || true)"
terraform -chdir=infra/platform workspace select default

echo "Waiting for both environments to answer..."
for i in $(seq 1 36); do
  out="$(./scripts/check-versions.sh)"; echo "${out}"
  [ "$(echo "${out}" | grep -c build_id)" = "2" ] && break
  sleep 10
done

echo; echo "==> 2/4  Sending traffic to prod for 10 minutes"
./scripts/load.sh 600 > /tmp/load-phase8.log 2>&1 &
LOAD_PID=$!
echo "Prod dashboard: ${DASH:-CloudWatch > Dashboards > aws-cicd-prod}"
echo "Giving CloudWatch 5 minutes to collect data..."
for m in 1 2 3 4 5; do sleep 60; echo "  ${m}/5 minutes"; done

pause "SCREENSHOT: AWS console (Mumbai) > CloudWatch > Dashboards > aws-cicd-prod. Set the time range to 15 minutes, refresh, and show all the graphs and the alarm. Zoom the browser out so everything fits on one screen."

kill "${LOAD_PID}" 2>/dev/null; LOAD_PID=""

echo; echo "==> 3/4  Teardown (type yes when Terraform asks)"
./scripts/teardown.sh
echo; echo "==> 4/4  Billing check"
./scripts/billing-check.sh
echo "Phase 8 demo complete. Send me the screenshot."
''', 0o755)

print()
print("Next: cd infra/platform && terraform init -input=false && terraform validate")
print("then commit and push, then ./scripts/demo-phase8.sh")
