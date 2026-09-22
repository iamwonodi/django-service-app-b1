#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# PUBLISH THE RENDERED DEPLOY FILES TO THE FLEET'S DEPLOY BUCKET
#
# Publishes into the service's own directory, and only there:
#
#   s3://<bucket>/<tier>/<service>/docker-compose.yml
#   s3://<bucket>/<tier>/<service>/.env
#
# (services/<service>/ in the service's own bucket where it has dedicated hosts.)
#
# The fleet's deploy script runs each service's compose file as its own project
# with that directory as the project directory, so one service cannot reach a
# co-tenant's files. The compose file goes LAST: it is what names the new image.
#
# Usage: publish-deploy-files.sh <rendered-dir> <bucket> <prefix> <aws-region>
# ==============================================================================

DIR="${1:?Usage: publish-deploy-files.sh <rendered-dir> <bucket> <prefix> <aws-region>}"
BUCKET="${2:?bucket is required}"
PREFIX="${3:?prefix is required}"
REGION="${4:?aws-region is required}"

[[ "${PREFIX}" =~ ^((private|internal)|services)/[a-z0-9-]+$ ]] || { echo "ERROR: prefix '${PREFIX}' is not <tier>/<service> or services/<service>." >&2; exit 1; }
[[ "${BUCKET}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo "ERROR: '${BUCKET}' is not a bucket name." >&2; exit 1; }

for name in .env docker-compose.yml; do
  [[ -s "${DIR}/${name}" ]] || { echo "ERROR: ${DIR}/${name} is missing or empty." >&2; exit 1; }
done

for name in .env docker-compose.yml; do
  echo "Publishing ${name} to s3://${BUCKET}/${PREFIX}/${name}"
  aws s3 cp "${DIR}/${name}" "s3://${BUCKET}/${PREFIX}/${name}" --region "${REGION}" --only-show-errors
done

echo "Published to s3://${BUCKET}/${PREFIX}/."
