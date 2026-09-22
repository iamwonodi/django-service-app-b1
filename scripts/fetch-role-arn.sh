#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# CONNECT THIS REPOSITORY TO ITS ROLE
#
# After core has applied this repository's service-roles.json entry, core publishes
# every role ARN to role-arns/<environment>.json on its platform-outputs branch. This
# reads this repository's ARN from there and sets it as the AWS_ROLE_ARN secret on the
# environment's GitHub Environment.
#
# It needs no admin access to core: the file is a generated, non-secret list.
#
# Usage: scripts/fetch-role-arn.sh --core OWNER/CORE-REPO --environment ENV [--repo OWNER/REPO]
# Needs: gh (authenticated), jq, base64.
# ==============================================================================

REPO_ROOT="${INIT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CORE="" ENVIRONMENT="" REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core)        CORE="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --repo)        REPO="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument '$1'." >&2; exit 1 ;;
  esac
done

[[ "${CORE}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: --core must be OWNER/REPOSITORY." >&2; exit 1; }
case "${ENVIRONMENT}" in
  development|staging|production) ;;
  *) echo "ERROR: --environment must be development, staging or production." >&2; exit 1 ;;
esac

for command in gh jq base64; do
  command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: required command not found: ${command}" >&2; exit 1; }
done

if [[ -z "${REPO}" ]]; then
  REMOTE_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  [[ -n "${REMOTE_URL}" ]] || { echo "ERROR: no origin remote; pass --repo OWNER/REPO." >&2; exit 1; }
  REPO="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##; s#/$##' <<< "${REMOTE_URL}")"
fi

RESPONSE="$(gh api "repos/${CORE}/contents/role-arns/${ENVIRONMENT}.json?ref=platform-outputs" 2>/dev/null)" \
  || { echo "ERROR: could not read role-arns/${ENVIRONMENT}.json on ${CORE}'s platform-outputs branch." >&2
       echo "       Has core applied this repository's entry yet, and can you read ${CORE}?" >&2; exit 1; }

DOCUMENT="$(jq -r '.content' <<< "${RESPONSE}" | base64 -d)" \
  || { echo "ERROR: the role-arns file could not be decoded." >&2; exit 1; }

ARN="$(jq -r --arg r "${REPO}" '.service_role_arns[$r] // empty' <<< "${DOCUMENT}")"

if [[ -z "${ARN}" ]]; then
  echo "ERROR: ${REPO} has no role in ${CORE}'s ${ENVIRONMENT} role-arns." >&2
  echo "       Add its entry to core's service-roles.json (scripts/print-role-entry.sh) and let core apply it." >&2
  exit 1
fi

[[ "${ARN}" =~ ^arn:aws:iam::[0-9]{12}:role/.+ ]] || { echo "ERROR: '${ARN}' does not look like an IAM role ARN." >&2; exit 1; }

echo "Setting AWS_ROLE_ARN on ${REPO}'s ${ENVIRONMENT} environment."
gh secret set AWS_ROLE_ARN --repo "${REPO}" --env "${ENVIRONMENT}" --body "${ARN}" \
  || { echo "ERROR: could not set the secret. Create the environments first: scripts/init-app.sh" >&2; exit 1; }

echo "Done: ${REPO} will assume ${ARN} in ${ENVIRONMENT}."
