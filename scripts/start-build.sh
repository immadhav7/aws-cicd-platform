#!/usr/bin/env bash
# Start a CodeBuild build of the default branch and wait for the result.
# Usage: scripts/start-build.sh [commit-sha-or-branch]
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
PROJECT="${CODEBUILD_PROJECT:-aws-cicd-app-build}"

ARGS=(--region "${REGION}" --project-name "${PROJECT}" --query 'build.id' --output text)
if [ -n "${1:-}" ]; then
  ARGS+=(--source-version "$1")
fi

BUILD_ID="$(aws codebuild start-build "${ARGS[@]}")"
echo "Started ${BUILD_ID}"

while true; do
  read -r STATUS PHASE < <(aws codebuild batch-get-builds --region "${REGION}" --ids "${BUILD_ID}" \
    --query 'builds[0].[buildStatus,currentPhase]' --output text)
  echo "  ${STATUS} (${PHASE})"
  [ "${STATUS}" != "IN_PROGRESS" ] && break
  sleep 10
done

if [ "${STATUS}" = "SUCCEEDED" ]; then
  echo "Build succeeded. Newest images:"
  aws ecr describe-images --region "${REGION}" --repository-name "${ECR_REPOSITORY:-aws-cicd-app}" \
    --query 'sort_by(imageDetails,&imagePushedAt)[-3:].[imageTags[0],imagePushedAt]' --output text
else
  echo "Build ${STATUS}. Logs: CloudWatch > Log groups > /codebuild/${PROJECT}" >&2
  exit 1
fi
