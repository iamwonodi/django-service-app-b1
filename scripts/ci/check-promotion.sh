#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# MAY THIS TAG GO TO THIS ENVIRONMENT?
#
# A tag reaches an environment above the lowest one only after it has been deployed
# successfully to the environment just below it. Development deploys every release;
# staging accepts only a tag that ran in development; production only one that ran
# in staging.
#
# "Ran" is read from GitHub Deployments: record-deployment.sh records a successful
# deployment per environment, with the tag as its ref, after every successful
# deploy. The lower environment is whichever comes before this one in
# .github/environments.json.
#
# Usage: check-promotion.sh <owner/repo> <environment> <tag>
# Needs: gh (authenticated; the workflow's token needs deployments: read), jq.
# ==============================================================================

REPO="${1:?Usage: check-promotion.sh <owner/repo> <environment> <tag>}"
ENVIRONMENT="${2:?environment is required}"
TAG="${3:?tag is required}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: '${REPO}' is not OWNER/REPOSITORY." >&2; exit 1; }
[[ "${ENVIRONMENT}" =~ ^[a-z][a-z-]*$ ]] || { echo "ERROR: '${ENVIRONMENT}' is not an environment name." >&2; exit 1; }
[[ "${TAG}" =~ ^v[0-9][A-Za-z0-9._+-]*$ ]] || { echo "ERROR: '${TAG}' is not a release tag." >&2; exit 1; }

LOWER="$(bash "${HERE}/resolve-environments.sh" lower "${ENVIRONMENT}")"

if [[ -z "${LOWER}" ]]; then
  echo "${ENVIRONMENT} is the lowest environment: no promotion gate."
  exit 0
fi

echo "Checking that ${TAG} was deployed successfully to ${LOWER} before ${ENVIRONMENT}."

DEPLOYMENTS="$(gh api "repos/${REPO}/deployments?environment=${LOWER}&ref=${TAG}&per_page=100")" \
  || { echo "ERROR: could not list deployments (does the token have deployments: read?)." >&2; exit 1; }

for ID in $(jq -r '.[].id' <<< "${DEPLOYMENTS}"); do
  STATE="$(gh api "repos/${REPO}/deployments/${ID}/statuses?per_page=1" | jq -r '.[0].state // empty')"

  if [[ "${STATE}" == "success" ]]; then
    echo "Promotion allowed: ${TAG} was deployed to ${LOWER} (deployment ${ID})."
    exit 0
  fi
done

echo "ERROR: ${TAG} has not been deployed successfully to ${LOWER}, so it cannot be promoted to ${ENVIRONMENT}." >&2
echo "       Deploy it to ${LOWER} first." >&2
exit 1
