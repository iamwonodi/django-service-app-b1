#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# FILL IN THE SERVICE'S DEPLOY FILES
#
# app/docker-compose.yml and app/.env are committed as templates. Values that are
# only known once the platform and the infrastructure exist are written as
# __PLACEHOLDERS__ and filled in here, at deploy time:
#
#   __IMAGE__            the full image reference, tag included  (IMAGE)
#   __PORT__             the host port                           (SERVICE_PORT)
#   __SERVICE_NAME__     the service's name                      (SERVICE_NAME)
#   __SERVICE_DOMAIN__   the domain it is served on              (SERVICE_DOMAIN)
#   __DATABASE_HOST__    the database host                        (DATABASE_HOST)
#   __DATABASE_PORT__    the database engine's port               (DATABASE_PORT)
#   __APP_SECRET_ARN__   the ARN of the service's secret          (APP_SECRET_ARN)
#
# Doing it here is what keeps the image and the compose file on the same version:
# without __IMAGE__ a new image could be pushed while the compose file still named
# the previous one, and the fleet would faithfully redeploy the old release.
#
# __FROM_SECRET__ is NOT substituted: it marks a secret the fleet resolves on the
# host, into a scratch file that is deleted at once. No secret value ever passes
# through CI or S3.
#
# Comment lines are skipped, so a placeholder mentioned in an explanation is not
# rewritten. Any other placeholder left unfilled is an error: the alternative is a
# container that starts with a literal "__DATABASE_HOST__" for its host.
#
# Usage: IMAGE=... SERVICE_PORT=... SERVICE_NAME=... SERVICE_DOMAIN=... \
#        APP_SECRET_ARN=... [DATABASE_HOST=... DATABASE_PORT=...] \
#        render-deploy-files.sh <app-dir> <output-dir>
# ==============================================================================

APP_DIR="${1:?Usage: render-deploy-files.sh <app-dir> <output-dir>}"
OUT_DIR="${2:?output-dir is required}"

declare -A SUBSTITUTIONS=(
  [__IMAGE__]="${IMAGE:-}"
  [__PORT__]="${SERVICE_PORT:-}"
  [__SERVICE_NAME__]="${SERVICE_NAME:-}"
  [__SERVICE_DOMAIN__]="${SERVICE_DOMAIN:-}"
  [__DATABASE_HOST__]="${DATABASE_HOST:-}"
  [__DATABASE_PORT__]="${DATABASE_PORT:-}"
  [__APP_SECRET_ARN__]="${APP_SECRET_ARN:-}"
)

# Values reach sed as replacement text, so they are held to a plain-token alphabet
# (no "&", no backslash, no control character).
for placeholder in "${!SUBSTITUTIONS[@]}"; do
  value="${SUBSTITUTIONS[${placeholder}]}"
  if [[ -n "${value}" && ! "${value}" =~ ^[A-Za-z0-9:/._@+=,-]+$ ]]; then
    echo "ERROR: the value for ${placeholder} contains characters that are not allowed." >&2
    exit 1
  fi
done

mkdir -p "${OUT_DIR}"

DELIM=$'\001'

for name in docker-compose.yml .env; do
  source_file="${APP_DIR}/${name}"

  [[ -f "${source_file}" ]] || { echo "ERROR: ${source_file} not found." >&2; exit 1; }

  cp "${source_file}" "${OUT_DIR}/${name}"

  for placeholder in "${!SUBSTITUTIONS[@]}"; do
    value="${SUBSTITUTIONS[${placeholder}]}"
    [[ -n "${value}" ]] || continue

    tmp="$(mktemp)"
    sed "/^[[:space:]]*#/!s${DELIM}${placeholder}${DELIM}${value}${DELIM}g" "${OUT_DIR}/${name}" > "${tmp}"
    cat "${tmp}" > "${OUT_DIR}/${name}"
    rm -f "${tmp}"
  done

  unresolved="$(grep -vE '^[[:space:]]*#' "${OUT_DIR}/${name}" | grep -oE '__[A-Z][A-Z_]*__' | grep -vx '__FROM_SECRET__' | sort -u || true)"

  if [[ -n "${unresolved}" ]]; then
    echo "ERROR: ${name} still contains unfilled placeholders:" >&2
    sed 's/^/         /' <<< "${unresolved}" >&2
    echo "       A placeholder is unfilled when its value was not provided (a service without a" >&2
    echo "       database has no __DATABASE_*__ values: remove those lines from .env)." >&2
    exit 1
  fi
done

echo "Rendered docker-compose.yml and .env into ${OUT_DIR}."
