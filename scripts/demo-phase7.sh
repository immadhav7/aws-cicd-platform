#!/usr/bin/env bash
# Phase 7 end to end: bring everything up, do a good blue/green deploy, do a deliberately broken
# deploy that rolls back by itself, switch the fault off and tear everything down.
# It stops and tells you when to take a screenshot. Run it from anywhere:  ./scripts/demo-phase7.sh
# Needs: phase 7 pushed to GitHub, infra/pipeline applied, SNS email subscription confirmed.
set -uo pipefail
cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-ap-south-1}"
PIPELINE="${PIPELINE_NAME:-aws-cicd-app-pipeline}"
APP="aws-cicd-prod"
JOBS_TO_KILL=()

cleanup() {
  for pid in "${JOBS_TO_KILL[@]:-}"; do [ -n "${pid}" ] && kill "${pid}" 2>/dev/null; done
}
trap cleanup EXIT
trap 'echo; echo "Interrupted. Run ./scripts/teardown.sh so nothing keeps billing."; exit 130' INT TERM

die() { echo "ERROR: $*" >&2; echo "If AWS resources exist, run ./scripts/teardown.sh when you are done." >&2; exit 1; }
pause() { echo; echo ">>> $1"; read -r -p "    Press Enter when you are done... " _; }

stage_status() {
  aws codepipeline get-pipeline-state --region "${REGION}" --name "${PIPELINE}" \
    --query "stageStates[?stageName=='$1'].latestExecution.status" --output text
}
latest_deployment() {
  aws deploy list-deployments --region "${REGION}" --application-name "${APP}" \
    --deployment-group-name "${APP}" --query 'deployments[0]' --output text 2>/dev/null
}
deployment_status() {
  aws deploy get-deployment --region "${REGION}" --deployment-id "$1" \
    --query 'deploymentInfo.status' --output text
}

wait_for_approval() {
  echo "Waiting for the pipeline to reach the approval gate..."
  local i
  for i in $(seq 1 90); do
    if [ "$(stage_status ApproveProd)" = "InProgress" ]; then
      ./scripts/approve.sh && return 0
    fi
    sleep 10
  done
  die "the pipeline never reached the approval gate"
}

# Sets DEP to the CodeDeploy deployment that appears after $1 (the id seen before).
wait_for_new_deployment() {
  local old="$1" i
  echo "Waiting for CodeDeploy to start the prod deployment..."
  for i in $(seq 1 60); do
    DEP="$(latest_deployment)"
    if [ -n "${DEP}" ] && [ "${DEP}" != "None" ] && [ "${DEP}" != "${old}" ]; then
      echo "CodeDeploy deployment: ${DEP}"
      return 0
    fi
    sleep 5
  done
  die "CodeDeploy never started a deployment"
}

# Follow a deployment until it ends; show which version prod answers with while traffic shifts.
follow_deployment() {
  local s
  while true; do
    s="$(deployment_status "$1")"
    echo "  $(date +%H:%M:%S)  CodeDeploy: ${s}   | $(./scripts/check-versions.sh | grep '^prod')"
    case "${s}" in Succeeded|Failed|Stopped) break ;; esac
    sleep 20
  done
  FINAL="${s}"
}

echo "=============================================================="
echo " Phase 7 demo. AWS billing runs from step 1 until the teardown"
echo " at the end (roughly 0.15 USD per hour, about 1.5 hours)."
echo "=============================================================="
read -r -p "Type yes to start: " ok
[ "${ok}" = "yes" ] || exit 0

# ---------------------------------------------------------------- 0. preflight
aws sts get-caller-identity > /dev/null || die "AWS credentials do not work"
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first (git status)"
grep -q '"SIMULATE_FAULT", "value": "0"' deploy/taskdef.json || die "the fault is on: run ./scripts/fault.sh off and commit"
git pull --ff-only -q || die "git pull failed"
[ "$(aws codepipeline get-pipeline --region "${REGION}" --name "${PIPELINE}" \
  --query "pipeline.stages[?name=='DeployProd'].actions[0].actionTypeId.provider" --output text)" = "CodeDeployToECS" ] \
  || die "the pipeline still deploys prod with ECS: run terraform apply in infra/pipeline first"

if [ "${START_AT:-1}" -le 2 ]; then
# ---------------------------------------------------------------- 1. infrastructure
echo; echo "==> 1/5  Creating network, dev and prod"
terraform -chdir=infra/network apply -auto-approve || die "network apply failed"
terraform -chdir=infra/platform workspace select default || die "workspace select failed"
terraform -chdir=infra/platform apply -auto-approve || die "dev apply failed"
terraform -chdir=infra/platform workspace select prod || die "workspace select failed"
terraform -chdir=infra/platform apply -auto-approve || die "prod apply failed"
terraform -chdir=infra/platform workspace select default

echo "Waiting for both environments to answer..."
for i in $(seq 1 36); do
  out="$(./scripts/check-versions.sh)"; echo "${out}"
  [ "$(echo "${out}" | grep -c build_id)" = "2" ] && break
  sleep 10
done

pause "SCREENSHOT 1: AWS console (Mumbai) > CodeDeploy > Applications > aws-cicd-prod > Deployment groups > aws-cicd-prod. Show blue/green, the rollback settings and the alarm."

# ---------------------------------------------------------------- 2. good deploy
echo; echo "==> 2/5  Good deploy: canary 10%, then 100%"
OLD="$(latest_deployment)"
./scripts/run-pipeline.sh > /tmp/pipeline-good.log 2>&1 &
PIPE_PID=$!; JOBS_TO_KILL+=("${PIPE_PID}")
wait_for_approval
wait_for_new_deployment "${OLD}"
echo
echo ">>> NOW (about 5 minutes): SCREENSHOT 2 and 3. In the CodeDeploy console open deployment ${DEP}."
echo ">>> 2: the traffic bar at 10% / 90%.  3: this terminal while prod flips between two versions."
follow_deployment "${DEP}"
wait "${PIPE_PID}"
echo "Good deploy finished: ${FINAL}"
[ "${FINAL}" = "Succeeded" ] || die "the good deploy did not succeed; check the CodeDeploy console"
pause "SCREENSHOT 4: CodeDeploy deployment ${DEP} with status Succeeded (traffic 100%). SCREENSHOT 5: the pipeline with all 5 stages green."

fi

# ---------------------------------------------------------------- 3. bad deploy
echo; echo "==> 3/5  Broken deploy: the home page returns 500 but health checks stay green"
./scripts/fault.sh on || die "fault.sh failed"
git add deploy/taskdef.json
git commit -q -m "demo: switch on the simulated fault in prod" || die "git commit failed"
git push -q || die "git push failed"
OLD="$(latest_deployment)"
wait_for_approval
wait_for_new_deployment "${OLD}"
./scripts/load.sh 600 > /tmp/load.log 2>&1 &
LOAD_PID=$!; JOBS_TO_KILL+=("${LOAD_PID}")
echo
echo ">>> Traffic is running. In the console watch deployment ${DEP}: 10% goes to the broken version,"
echo ">>> the alarm fires after 1-2 minutes and CodeDeploy rolls back by itself."
follow_deployment "${DEP}"
kill "${LOAD_PID}" 2>/dev/null
echo; echo "Deployment ended: ${FINAL}"
./scripts/deploy-status.sh
./scripts/check-versions.sh
aws cloudwatch describe-alarms --region "${REGION}" --alarm-names aws-cicd-prod-alb-5xx \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
[ "${FINAL}" = "Succeeded" ] && echo "WARNING: the broken deploy succeeded, so no rollback happened."
pause "SCREENSHOTS 6-9 (do them now, before teardown): 6 CodeDeploy deployment ${DEP} stopped/rolled back, with the alarm as the reason. 7 CloudWatch > Alarms > aws-cicd-prod-alb-5xx (history or In alarm). 8 the pipeline with DeployProd failed. 9 this terminal showing prod still on the good version."

# ---------------------------------------------------------------- 4. fault off
echo; echo "==> 4/5  Switching the fault off in the repo"
./scripts/fault.sh off || die "fault.sh failed"
git add deploy/taskdef.json
git commit -q -m "demo: switch the simulated fault off [skip ci]" || die "git commit failed"
git push -q || die "git push failed"

# ---------------------------------------------------------------- 5. teardown
echo; echo "==> 5/5  Teardown (type yes when Terraform asks)"
./scripts/teardown.sh
./scripts/billing-check.sh
echo "Phase 7 demo complete. Send me the screenshots."
