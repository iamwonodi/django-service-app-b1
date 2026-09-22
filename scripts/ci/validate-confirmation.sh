#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# THE TYPED CONFIRMATION FOR A MANUAL RUN
#
# A manual deploy or build must be confirmed by typing the environment's name (or the
# all-keyword for "all"), so a mis-click on a dropdown cannot deploy to production.
#
# Usage: validate-confirmation.sh <environment-selection> <typed-confirmation> <all-keyword>
# ==============================================================================

SELECTION="${1:?Usage: validate-confirmation.sh <environment-selection> <typed-confirmation> <all-keyword>}"
CONFIRMATION="${2:-}"
ALL_KEYWORD="${3:?all-keyword is required}"

EXPECTED="${SELECTION}"
[[ "${SELECTION}" == "all" ]] && EXPECTED="${ALL_KEYWORD}"

if [[ "${CONFIRMATION}" != "${EXPECTED}" ]]; then
  echo "ERROR: the confirmation does not match the selection." >&2
  echo "       Selected: '${SELECTION}'. Type exactly: '${EXPECTED}'. You typed: '${CONFIRMATION}'." >&2
  exit 1
fi

echo "Confirmation matches '${EXPECTED}'."
