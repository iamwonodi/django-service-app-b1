#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# IS THIS IMAGE TAG ALREADY IN THE REPOSITORY?
#
# ECR tags are immutable, so pushing a tag that exists fails. Building is skipped
# when the tag is already there, which makes a rerun, a backfill and a promotion all
# safe. Appends exists=true|false to GITHUB_OUTPUT.
#
# Usage: check-image-exists.sh <repository-name> <image-tag> <aws-region>
# ==============================================================================

REPOSITORY_NAME="${1:?Usage: check-image-exists.sh <repository-name> <image-tag> <aws-region>}"
IMAGE_TAG="${2:?image-tag is required}"
AWS_REGION="${3:?aws-region is required}"

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

if aws ecr describe-images --repository-name "${REPOSITORY_NAME}" --image-ids "imageTag=${IMAGE_TAG}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "exists=true" >> "${OUTPUT_FILE}"
  echo "Image tag '${IMAGE_TAG}' already exists in '${REPOSITORY_NAME}'."
else
  echo "exists=false" >> "${OUTPUT_FILE}"
  echo "Image tag '${IMAGE_TAG}' is not in '${REPOSITORY_NAME}': it needs building."
fi
