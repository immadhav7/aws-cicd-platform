#!/usr/bin/env bash
# Prints the billable things that may still be running. Everything should be empty.
# Usage: scripts/billing-check.sh
set -uo pipefail

REGION="${AWS_REGION:-ap-south-1}"
bad=0

check() {
  local label="$1"; shift
  local out
  out="$("$@" 2>&1)"
  if [ -z "${out}" ] || [ "${out}" = "None" ]; then
    echo "OK    ${label}: none"
  else
    echo "LEFT  ${label}:"; echo "${out}" | sed 's/^/        /'; bad=1
  fi
}

check "load balancers" aws elbv2 describe-load-balancers --region "${REGION}" \
  --query 'LoadBalancers[].LoadBalancerName' --output text
check "NAT gateways" aws ec2 describe-nat-gateways --region "${REGION}" \
  --filter Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId' --output text
check "Elastic IPs" aws ec2 describe-addresses --region "${REGION}" \
  --query 'Addresses[].PublicIp' --output text
check "running ECS tasks (prod)" aws ecs list-tasks --region "${REGION}" --cluster aws-cicd-prod \
  --query 'taskArns[]' --output text
check "running ECS tasks (dev)" aws ecs list-tasks --region "${REGION}" --cluster aws-cicd-dev \
  --query 'taskArns[]' --output text

[ "${bad}" = "0" ] && echo "All clear: nothing billable is running." || echo "Something is still running: run ./scripts/teardown.sh"
