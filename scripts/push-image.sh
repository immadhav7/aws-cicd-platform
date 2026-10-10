#!/usr/bin/env bash
# Build the app image for Fargate (linux/amd64) and push it to ECR.
# Usage: scripts/push-image.sh <tag>      e.g. scripts/push-image.sh v1
set -euo pipefail

TAG="${1:?usage: scripts/push-image.sh <tag>}"
REGION="${AWS_REGION:-ap-south-1}"
REPO="${ECR_REPOSITORY:-aws-cicd-app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPO}:${TAG}"

echo "==> Logging in to ${REGISTRY}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

echo "==> Building ${IMAGE}"
docker build --platform linux/amd64 --build-arg BUILD_ID="${TAG}" -t "${IMAGE}" "${ROOT}/app"

echo "==> Pushing ${IMAGE}"
docker push "${IMAGE}"

echo "Done. Deploy it with: image_tag = \"${TAG}\" in infra/platform/terraform.tfvars"
