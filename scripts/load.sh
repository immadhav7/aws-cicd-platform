#!/usr/bin/env bash
# Send steady traffic to prod's home page and print how many answers were OK or errors.
# CodeDeploy's alarm needs real requests to see 5xx errors during a canary deployment.
# Usage: scripts/load.sh [seconds]     (default 300)
set -uo pipefail

REGION="${AWS_REGION:-ap-south-1}"
SECONDS_TO_RUN="${1:-300}"

DNS="$(aws elbv2 describe-load-balancers --region "${REGION}" --names aws-cicd-prod-alb \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || true)"
if [ -z "${DNS}" ] || [ "${DNS}" = "None" ]; then
  echo "prod is not running" >&2
  exit 1
fi

echo "Sending traffic to http://${DNS}/ for ${SECONDS_TO_RUN}s (Ctrl+C to stop)"
ok=0; err=0; start=$SECONDS; last=$SECONDS
while [ $((SECONDS - start)) -lt "${SECONDS_TO_RUN}" ]; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://${DNS}/" || echo 000)"
  if [ "${code}" = "200" ]; then ok=$((ok + 1)); else err=$((err + 1)); fi
  if [ $((SECONDS - last)) -ge 10 ]; then
    echo "  $((SECONDS - start))s  ok=${ok}  errors=${err}"
    last=$SECONDS
  fi
  sleep 0.2
done
echo "Done: ok=${ok} errors=${err}"
