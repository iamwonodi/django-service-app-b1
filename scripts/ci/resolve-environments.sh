#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# WHICH ENVIRONMENTS MAY A WORKFLOW USE?
#
# .github/environments.json lists the enabled environments from LOWEST to HIGHEST,
# for example ["development","staging","production"]. Staging and production stay
# off the list until the platform hosts services there.
#
#   auto <>       the FIRST (lowest) environment: the only one that deploys
#                 automatically on a release
#   one <env>     exactly that environment, if it is enabled
#   all           every enabled environment (used to backfill images)
#   lower <env>   the environment just below <env>, or nothing for the lowest.
#                 A tag may be promoted to <env> only after it ran there
#
# Prints a compact JSON array for auto/one/all, or the environment name (empty for
# none) for lower.
#
# Usage: resolve-environments.sh auto | one <env> | all | lower <env>
# ==============================================================================

ROOT="${RESOLVE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
FILE="${ROOT}/.github/environments.json"

[[ -f "${FILE}" ]] || { echo "ERROR: ${FILE} not found." >&2; exit 1; }

ENABLED="$(jq -c 'if type == "array" and length > 0 and all(.[]; type == "string") then . else error("bad") end' "${FILE}" 2>/dev/null)" \
  || { echo "ERROR: ${FILE} must be a non-empty JSON array of environment names." >&2; exit 1; }

MODE="${1:-}"
ENV="${2:-}"

case "${MODE}" in
  auto)
    jq -c '[.[0]]' <<< "${ENABLED}"
    ;;
  all)
    echo "${ENABLED}"
    ;;
  one)
    [[ -n "${ENV}" ]] || { echo "ERROR: 'one' needs an environment." >&2; exit 1; }
    if jq -e --arg e "${ENV}" 'index($e) != null' <<< "${ENABLED}" >/dev/null; then
      jq -cn --arg e "${ENV}" '[$e]'
    else
      echo "ERROR: '${ENV}' is not enabled. Enabled: $(jq -r 'join(", ")' <<< "${ENABLED}")." >&2
      exit 1
    fi
    ;;
  lower)
    [[ -n "${ENV}" ]] || { echo "ERROR: 'lower' needs an environment." >&2; exit 1; }
    jq -e --arg e "${ENV}" 'index($e) != null' <<< "${ENABLED}" >/dev/null \
      || { echo "ERROR: '${ENV}' is not enabled." >&2; exit 1; }
    jq -r --arg e "${ENV}" 'index($e) as $i | if $i == 0 then "" else .[$i - 1] end' <<< "${ENABLED}"
    ;;
  *)
    echo "ERROR: Usage: ${0} auto | one <env> | all | lower <env>" >&2
    exit 1
    ;;
esac
