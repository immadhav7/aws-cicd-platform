#!/usr/bin/env bash
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
