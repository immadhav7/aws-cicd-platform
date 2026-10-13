#!/usr/bin/env bash
# Show which version is live in each environment (looks the load balancers up by name).
# Usage: scripts/check-versions.sh
set -uo pipefail

REGION="${AWS_REGION:-ap-south-1}"

for env in dev prod; do
  DNS="$(aws elbv2 describe-load-balancers --region "${REGION}" --names "aws-cicd-${env}-alb" \
    --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || true)"
  if [ -z "${DNS}" ] || [ "${DNS}" = "None" ]; then
    echo "${env}: not running"
    continue
  fi
  printf '%s: ' "${env}"
  curl -s --max-time 5 "http://${DNS}/version" || printf 'no answer yet'
  echo
done
