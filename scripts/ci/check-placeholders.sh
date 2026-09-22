#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# FAIL WHEN A FILE STILL CONTAINS THE BLUEPRINT'S PLACEHOLDER
#
# This repository is a blueprint: values that differ per service ship as the marker
# CHANGE_ME, and a deploy must not run with one of them unset. Comment lines are
# ignored so documentation may mention the marker.
#
# Usage: check-placeholders.sh <file>...
# ==============================================================================

MARKER="CHANGE_ME"

[[ $# -ge 1 ]] || { echo "ERROR: Usage: ${0} <file>..." >&2; exit 1; }

found=0

for file in "$@"; do
  [[ -f "${file}" ]] || { echo "ERROR: file not found: ${file}" >&2; exit 1; }

  hits="$(grep -n "${MARKER}" "${file}" | grep -vE '^[0-9]+:[[:space:]]*(#|//)' || true)"

  if [[ -n "${hits}" ]]; then
    while IFS= read -r line; do echo "  ${file}:${line}"; done <<< "${hits}"
    found=1
  fi
done

if [[ ${found} -ne 0 ]]; then
  echo
  echo "ERROR: the lines above still contain the placeholder ${MARKER}."
  echo "       Replace each with your service's value (scripts/init-app.sh does this for you), then commit."
  exit 1
fi

echo "No placeholders remain."
