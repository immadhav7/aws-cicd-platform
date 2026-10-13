#!/usr/bin/env bash
# Approve (or reject) the pending prod release from the terminal.
# Usage: scripts/approve.sh [approve|reject]     (default: approve)
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
PIPELINE="${PIPELINE_NAME:-aws-cicd-app-pipeline}"
DECISION="${1:-approve}"

case "${DECISION}" in
  approve) RESULT="Approved" ;;
  reject)  RESULT="Rejected" ;;
  *) echo "Usage: $0 [approve|reject]" >&2; exit 2 ;;
esac

TOKEN="$(aws codepipeline get-pipeline-state --region "${REGION}" --name "${PIPELINE}" \
  --query "stageStates[?stageName=='ApproveProd'].actionStates[0].latestExecution.token" --output text)"

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "None" ]; then
  echo "Nothing is waiting for approval right now." >&2
  exit 1
fi

aws codepipeline put-approval-result --region "${REGION}" --pipeline-name "${PIPELINE}" \
  --stage-name ApproveProd --action-name Approve \
  --result "summary=${RESULT} from the terminal,status=${RESULT}" --token "${TOKEN}"
echo "${RESULT}."
