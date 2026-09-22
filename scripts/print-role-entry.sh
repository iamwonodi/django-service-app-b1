#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# PRINT THIS REPOSITORY'S ENTRY FOR CORE'S service-roles.json
#
# Core creates one IAM role per repository. It needs this repository's name, the
# service's name and tier, and the repository's numeric GitHub IDs (which core's trust
# policy embeds, so a renamed or transferred repository cannot be impersonated). This
# repository's role is kind "app": it can push an image, publish files and redeploy,
# and it can create or change nothing.
#
# The service name and tier are read from deploy.json.
#
# Usage: scripts/print-role-entry.sh [--repo OWNER/REPO]
# Needs: gh (authenticated), jq.
# ==============================================================================

REPO_ROOT="${INIT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument '$1'. Usage: ${0} [--repo OWNER/REPO]" >&2; exit 1 ;;
  esac
done

for command in gh jq; do
  command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: required command not found: ${command}" >&2; exit 1; }
done

SETTINGS="${REPO_ROOT}/deploy.json"
[[ -f "${SETTINGS}" ]] || { echo "ERROR: ${SETTINGS} not found." >&2; exit 1; }

SERVICE="$(jq -r '.service_name // empty' "${SETTINGS}")"
TIER="$(jq -r '.tier // empty' "${SETTINGS}")"

if [[ -z "${SERVICE}" || "${SERVICE}" == "CHANGE_ME" ]]; then
  echo "ERROR: service_name is not set. Run scripts/init-app.sh first." >&2
  exit 1
fi

if [[ -z "${REPO}" ]]; then
  REMOTE_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  [[ -n "${REMOTE_URL}" ]] || { echo "ERROR: no origin remote; pass --repo OWNER/REPO." >&2; exit 1; }
  REPO="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##; s#/$##' <<< "${REMOTE_URL}")"
fi

[[ "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: '${REPO}' is not in OWNER/REPOSITORY form." >&2; exit 1; }

DETAILS="$(gh api "repos/${REPO}" 2>/dev/null)" || { echo "ERROR: could not read ${REPO} from GitHub. Run 'gh auth login' and check the name." >&2; exit 1; }

OWNER_ID="$(jq -r '.owner.id // empty' <<< "${DETAILS}")"
REPOSITORY_ID="$(jq -r '.id // empty' <<< "${DETAILS}")"
FULL_NAME="$(jq -r '.full_name // empty' <<< "${DETAILS}")"

[[ -n "${OWNER_ID}" && -n "${REPOSITORY_ID}" ]] || { echo "ERROR: GitHub returned no IDs for ${REPO}." >&2; exit 1; }

jq -n \
  --arg repo "${FULL_NAME:-${REPO}}" \
  --arg service "${SERVICE}" \
  --arg tier "${TIER}" \
  --arg owner "${OWNER_ID}" \
  --arg id "${REPOSITORY_ID}" \
  '{($repo): {service_name: $service, kind: "app", tier: $tier, owner_id: $owner, repository_id: $id}}'
