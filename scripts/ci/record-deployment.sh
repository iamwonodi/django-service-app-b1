#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# RECORD A SUCCESSFUL DEPLOYMENT
#
# After a tag has been deployed and every host reported Success, record it as a GitHub
# Deployment with the TAG as its ref. check-promotion.sh reads these to decide
# whether the tag may go to the next environment.
#
# (A job that declares "environment:" already makes GitHub record a deployment, but
# with the ref of the workflow run -- usually main -- not the tag that was deployed,
# so it cannot answer "did v1.2.0 run in development?".)
#
# Usage: record-deployment.sh <owner/repo> <environment> <tag> <log-url>
# Needs: gh (the workflow's token needs deployments: write), jq.
# ==============================================================================

REPO="${1:?Usage: record-deployment.sh <owner/repo> <environment> <tag> <log-url>}"
ENVIRONMENT="${2:?environment is required}"
TAG="${3:?tag is required}"
LOG_URL="${4:?log-url is required}"

[[ "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: '${REPO}' is not OWNER/REPOSITORY." >&2; exit 1; }
[[ "${ENVIRONMENT}" =~ ^[a-z][a-z-]*$ ]] || { echo "ERROR: '${ENVIRONMENT}' is not an environment name." >&2; exit 1; }
[[ "${TAG}" =~ ^v[0-9][A-Za-z0-9._+-]*$ ]] || { echo "ERROR: '${TAG}' is not a release tag." >&2; exit 1; }
[[ "${LOG_URL}" =~ ^https://[A-Za-z0-9./_?=\&-]+$ ]] || { echo "ERROR: '${LOG_URL}' is not an https URL." >&2; exit 1; }

BODY="$(jq -cn --arg ref "${TAG}" --arg env "${ENVIRONMENT}" \
  '{ref: $ref, environment: $env, auto_merge: false, required_contexts: [], transient_environment: false, description: ("Deployed " + $ref)}')"

ID="$(printf '%s' "${BODY}" | gh api -X POST "repos/${REPO}/deployments" --input - | jq -r '.id // empty')"

[[ "${ID}" =~ ^[0-9]+$ ]] || { echo "ERROR: GitHub did not create a deployment record." >&2; exit 1; }

jq -cn --arg url "${LOG_URL}" --arg env "${ENVIRONMENT}" \
  '{state: "success", environment: $env, log_url: $url, description: "Every host reported Success"}' \
  | gh api -X POST "repos/${REPO}/deployments/${ID}/statuses" --input - >/dev/null

echo "Recorded: ${TAG} deployed to ${ENVIRONMENT} (deployment ${ID})."
