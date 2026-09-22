#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# WHICH RELEASE TAGS?
#
#   single <tag>       exactly that tag (a tag push)
#   latest             the newest release tag (a config-only change to main)
#   manual <list|all>  comma-separated tags, or every release tag (a backfill)
#
# Only release tags (vMAJOR.MINOR.PATCH, optionally with a suffix) qualify; every
# tag named must exist. Appends tags=<json array> to GITHUB_OUTPUT.
#
# Usage: resolve-tags.sh single|latest|manual [tag-input]
# ==============================================================================

MODE="${1:?Usage: resolve-tags.sh single|latest|manual [tag-input]}"
INPUT="${2:-}"

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"
PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$'

release_tags() { git tag --sort=-v:refname | grep -E "${PATTERN}" || true; }

require_tag() {
  [[ "$1" =~ ${PATTERN} ]] || { echo "ERROR: '$1' is not a release tag (vMAJOR.MINOR.PATCH)." >&2; exit 1; }
  git rev-parse -q --verify "refs/tags/$1" >/dev/null || { echo "ERROR: tag '$1' does not exist in this repository." >&2; exit 1; }
}

TAGS=()

case "${MODE}" in
  single)
    [[ -n "${INPUT}" ]] || { echo "ERROR: 'single' needs a tag." >&2; exit 1; }
    require_tag "${INPUT}"
    TAGS=("${INPUT}")
    ;;
  latest)
    LATEST="$(release_tags | head -n 1)"
    [[ -n "${LATEST}" ]] || { echo "ERROR: no release tags exist yet, so there is nothing to deploy." >&2; exit 1; }
    TAGS=("${LATEST}")
    ;;
  manual)
    [[ -n "${INPUT}" ]] || { echo "ERROR: 'manual' needs a tag list, or 'all'." >&2; exit 1; }
    if [[ "${INPUT}" == "all" ]]; then
      mapfile -t TAGS < <(release_tags | sort -V)
      [[ ${#TAGS[@]} -gt 0 ]] || { echo "ERROR: no release tags exist yet." >&2; exit 1; }
    else
      IFS=',' read -ra RAW <<< "${INPUT}"
      for raw in "${RAW[@]}"; do
        tag="$(xargs <<< "${raw}")"
        [[ -n "${tag}" ]] || continue
        require_tag "${tag}"
        TAGS+=("${tag}")
      done
      [[ ${#TAGS[@]} -gt 0 ]] || { echo "ERROR: no tags could be read from '${INPUT}'." >&2; exit 1; }
    fi
    ;;
  *)
    echo "ERROR: unknown mode '${MODE}'." >&2
    exit 1
    ;;
esac

JSON="$(printf '%s\n' "${TAGS[@]}" | jq -R . | jq -sc .)"
echo "tags=${JSON}" >> "${OUTPUT_FILE}"
echo "Resolved ${#TAGS[@]} tag(s): ${JSON}"
