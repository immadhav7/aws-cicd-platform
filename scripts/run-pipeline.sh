#!/usr/bin/env bash
# Start the pipeline on the latest commit of the branch and wait for the result.
# Usage: scripts/run-pipeline.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
PIPELINE="${PIPELINE_NAME:-aws-cicd-app-pipeline}"

EXEC_ID="$(aws codepipeline start-pipeline-execution --region "${REGION}" --name "${PIPELINE}" \
  --query 'pipelineExecutionId' --output text)"
echo "Started execution ${EXEC_ID}"

while true; do
  STATUS="$(aws codepipeline get-pipeline-execution --region "${REGION}" --pipeline-name "${PIPELINE}" \
    --pipeline-execution-id "${EXEC_ID}" --query 'pipelineExecution.status' --output text)"
  STAGES="$(aws codepipeline get-pipeline-state --region "${REGION}" --name "${PIPELINE}" \
    --query 'stageStates[].[stageName,latestExecution.status]' --output text | tr '\t' '=' | paste -sd' ' -)"
  echo "  ${STATUS}   ${STAGES}"
  case "${STATUS}" in
    InProgress|Stopping) sleep 15 ;;
    *) break ;;
  esac
done

if [ "${STATUS}" = "Succeeded" ]; then
  echo "Pipeline succeeded. Check the live version:"
  echo "  curl http://\$(terraform -chdir=infra/platform output -raw alb_dns_name)/version"
else
  echo "Pipeline ${STATUS}. Failed actions:" >&2
  aws codepipeline list-action-executions --region "${REGION}" --pipeline-name "${PIPELINE}" \
    --filter "pipelineExecutionId=${EXEC_ID}" \
    --query 'actionExecutionDetails[?status==`Failed`].[stageName,actionName,output.executionResult.externalExecutionSummary]' \
    --output text >&2 || true
  exit 1
fi
