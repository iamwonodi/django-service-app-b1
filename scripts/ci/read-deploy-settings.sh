#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# READ THIS REPOSITORY'S DEPLOY SETTINGS
#
# deploy.json names the project and the service and the tier it runs on. They are
# the same values the service's infrastructure repository deploys with, and they
# locate the service's config in SSM: /<project>/services/<service>/config.
# Prints KEY=VALUE lines for GITHUB_ENV; every value is validated first, because a
# value written to GITHUB_ENV must never carry a newline.
#
# Usage: read-deploy-settings.sh [path-to-deploy.json]
# ==============================================================================

FILE="${1:-deploy.json}"

[[ -f "${FILE}" ]] || { echo "ERROR: ${FILE} not found." >&2; exit 1; }
jq -e 'type == "object"' "${FILE}" >/dev/null 2>&1 || { echo "ERROR: ${FILE} is not a JSON object." >&2; exit 1; }

read_field() { jq -r --arg k "$1" '.[$k] // empty' "${FILE}"; }

PROJECT_NAME="$(read_field project_name)"
SERVICE_NAME="$(read_field service_name)"
SERVICE_TIER="$(read_field tier)"

[[ "${PROJECT_NAME}" =~ ^[a-z][a-z0-9-]{1,14}[a-z0-9]$ ]] || { echo "ERROR: project_name '${PROJECT_NAME}' in ${FILE} is not valid. If it is the CHANGE_ME placeholder, run scripts/init-app.sh." >&2; exit 1; }
[[ "${SERVICE_NAME}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || { echo "ERROR: service_name '${SERVICE_NAME}' in ${FILE} is not valid. If it is the CHANGE_ME placeholder, run scripts/init-app.sh." >&2; exit 1; }
[[ "${SERVICE_TIER}" == "private" || "${SERVICE_TIER}" == "internal" ]] || { echo "ERROR: tier '${SERVICE_TIER}' in ${FILE} must be private or internal." >&2; exit 1; }

echo "PROJECT_NAME=${PROJECT_NAME}"
echo "SERVICE_NAME=${SERVICE_NAME}"
echo "SERVICE_TIER=${SERVICE_TIER}"
