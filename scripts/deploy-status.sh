#!/usr/bin/env bash
# Show the latest prod CodeDeploy deployment: status, why it ended, and rollback details.
# Usage: scripts/deploy-status.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
APP="${CODEDEPLOY_APP:-aws-cicd-prod}"
GROUP="${CODEDEPLOY_GROUP:-aws-cicd-prod}"

ID="$(aws deploy list-deployments --region "${REGION}" --application-name "${APP}" \
  --deployment-group-name "${GROUP}" --max-items 1 --query 'deployments[0]' --output text)"
if [ -z "${ID}" ] || [ "${ID}" = "None" ]; then
  echo "No deployments yet."
  exit 0
fi

echo "Deployment ${ID}"
aws deploy get-deployment --region "${REGION}" --deployment-id "${ID}" \
  --query 'deploymentInfo.{status:status,created:createTime,finished:completeTime,error:errorInformation.message,rollback:rollbackInfo.rollbackMessage}' \
  --output table
