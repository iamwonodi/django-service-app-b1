#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# UPLOAD THE RELEASE'S STATIC FILES
#
# collectstatic ran when the image was built, so the exact files this release
# references are inside the image at /app/staticfiles. They are copied out and
# uploaded to the service's own prefix of the shared assets bucket:
#
#   s3://<assets bucket>/static/<service>/...
#
# CloudFront's one /static/* behaviour serves them, and the application's
# STATIC_URL is /static/<service>/.
#
# ORDER MATTERS: this runs BEFORE the redeploy, so a page from the new release never
# names a file that is not there yet.
#
# NEVER --delete: the file names carry a content hash, so a release only ADDS files.
# Hosts still running the previous release, and a later rollback, need the older
# ones.
#
# Hashed files can be cached for a year (their name changes when their content
# does). The unhashed copies collectstatic also keeps can change between releases,
# so they get a short cache.
#
# Usage: sync-static.sh <image> <bucket> <prefix> <aws-region>
# Needs: docker (able to pull the image), aws.
# ==============================================================================

IMAGE="${1:?Usage: sync-static.sh <image> <bucket> <prefix> <aws-region>}"
BUCKET="${2:?bucket is required}"
PREFIX="${3:?prefix is required}"
REGION="${4:?aws-region is required}"

[[ "${PREFIX}" =~ ^static/[a-z0-9-]+$ ]] || { echo "ERROR: prefix '${PREFIX}' is not static/<service>." >&2; exit 1; }
[[ "${BUCKET}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo "ERROR: '${BUCKET}' is not a bucket name." >&2; exit 1; }

WORK="$(mktemp -d)"
CONTAINER=""

cleanup() {
  [[ -n "${CONTAINER}" ]] && docker rm "${CONTAINER}" >/dev/null 2>&1 || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

CONTAINER="$(docker create "${IMAGE}")"

docker cp "${CONTAINER}:/app/staticfiles" "${WORK}/static" \
  || { echo "ERROR: ${IMAGE} has no /app/staticfiles. Was collectstatic run when the image was built?" >&2; exit 1; }

# The manifest maps names inside the running application; the bucket does not need it.
rm -f "${WORK}/static/staticfiles.json"

COUNT="$(find "${WORK}/static" -type f | wc -l | tr -d ' ')"
[[ "${COUNT}" -gt 0 ]] || { echo "ERROR: /app/staticfiles in ${IMAGE} is empty." >&2; exit 1; }

# Twelve hexadecimal characters between two dots: Django's content hash.
HASH='[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'

echo "Uploading ${COUNT} static files to s3://${BUCKET}/${PREFIX}/"

aws s3 sync "${WORK}/static" "s3://${BUCKET}/${PREFIX}/" \
  --exclude "*" --include "*.${HASH}.*" \
  --cache-control "public, max-age=31536000, immutable" \
  --region "${REGION}" --only-show-errors

aws s3 sync "${WORK}/static" "s3://${BUCKET}/${PREFIX}/" \
  --exclude "*.${HASH}.*" \
  --cache-control "public, max-age=300" \
  --region "${REGION}" --only-show-errors

echo "Static files are in place."
