#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# INITIALISE A CLONE OF THIS BLUEPRINT FOR ONE SERVICE'S APPLICATION
#
# deploy.json ships with the marker CHANGE_ME, and the workflows refuse to run while
# it remains. This sets it, and prepares GitHub to guard each environment. Safe to
# re-run: it rewrites only deploy.json and PUTs GitHub Environments idempotently.
#
# For every ENABLED environment (.github/environments.json):
#
#   GitHub  Environment <env>: deployments from main and from release tags (v*).
#           Reviewers (if given) are required on every environment except the
#           lowest, which deploys automatically. Each gets AWS_REGION. The role
#           secret (AWS_ROLE_ARN) is set later by scripts/fetch-role-arn.sh, once
#           core has created the role.
#
# The values must match what the service's INFRASTRUCTURE repository deploys with:
# the same project, the same service name, the same tier.
#
# Usage:
#   scripts/init-app.sh --project NAME --service NAME --region REGION \
#       [--tier private|internal] [--reviewers login1,login2] [--repo OWNER/REPO] \
#       [--skip-github] [--dry-run]
#
# Needs: bash, jq; gh (authenticated) unless --skip-github or --dry-run.
# ==============================================================================

REPO_ROOT="${INIT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PROJECT="" SERVICE="" REGION="" TIER="private" REVIEWERS="" REPO=""
SKIP_GITHUB=false
DRY_RUN=false

usage() { sed -n '/^# Usage:/,/^# Needs:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n -1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT="${2:-}"; shift 2 ;;
    --service)     SERVICE="${2:-}"; shift 2 ;;
    --region)      REGION="${2:-}"; shift 2 ;;
    --tier)        TIER="${2:-}"; shift 2 ;;
    --reviewers)   REVIEWERS="${2:-}"; shift 2 ;;
    --repo)        REPO="${2:-}"; shift 2 ;;
    --skip-github) SKIP_GITHUB=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'." >&2; usage >&2; exit 1 ;;
  esac
done

errors=()

[[ "${PROJECT}" =~ ^[a-z][a-z0-9-]{1,14}[a-z0-9]$ ]] || errors+=("--project must be 3-16 lowercase letters, digits or hyphens, starting with a letter.")
[[ "${SERVICE}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || errors+=("--service must be 3-22 lowercase letters, digits or hyphens, starting with a letter.")
case "${SERVICE}" in
  database|database-hub|fleet|internal|platform|private|services)
    errors+=("--service '${SERVICE}' is a name the platform itself uses; choose another.") ;;
esac
[[ "${REGION}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || errors+=("--region must look like af-south-1.")
[[ "${TIER}" == "private" || "${TIER}" == "internal" ]] || errors+=("--tier must be private or internal.")
if [[ -n "${REPO}" && ! "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]]; then errors+=("--repo must be OWNER/REPOSITORY."); fi
if [[ -n "${REVIEWERS}" && ! "${REVIEWERS}" =~ ^[A-Za-z0-9-]+(,[A-Za-z0-9-]+)*$ ]]; then errors+=("--reviewers must be comma-separated GitHub logins."); fi

if [[ ${#errors[@]} -gt 0 ]]; then
  printf 'ERROR: %s\n' "${errors[@]}" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: required command not found: jq" >&2; exit 1; }

ENABLED_FILE="${REPO_ROOT}/.github/environments.json"
[[ -f "${ENABLED_FILE}" ]] || { echo "ERROR: ${ENABLED_FILE} not found." >&2; exit 1; }
mapfile -t ENVIRONMENTS < <(jq -r '.[]' "${ENABLED_FILE}")
[[ ${#ENVIRONMENTS[@]} -gt 0 ]] || { echo "ERROR: no environments are enabled in ${ENABLED_FILE}." >&2; exit 1; }

if [[ "${SKIP_GITHUB}" != "true" && "${DRY_RUN}" != "true" ]]; then
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required (or pass --skip-github)." >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated. Run: gh auth login" >&2; exit 1; }
fi

if [[ -z "${REPO}" && "${SKIP_GITHUB}" != "true" ]]; then
  REMOTE_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  [[ -n "${REMOTE_URL}" ]] || { echo "ERROR: no origin remote; pass --repo OWNER/REPOSITORY." >&2; exit 1; }
  REPO="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##; s#/$##' <<< "${REMOTE_URL}")"
fi

# ------------------------------------------------------------------------------
# deploy.json
# ------------------------------------------------------------------------------
write_settings() {
  local file="${REPO_ROOT}/deploy.json"

  echo "  deploy.json: project=${PROJECT} service=${SERVICE} tier=${TIER}"

  [[ "${DRY_RUN}" == "true" ]] && return 0

  jq -n --arg p "${PROJECT}" --arg s "${SERVICE}" --arg t "${TIER}" \
    '{project_name: $p, service_name: $s, tier: $t}' > "${file}.tmp"
  mv "${file}.tmp" "${file}"
}

# ------------------------------------------------------------------------------
# GitHub Environments
# ------------------------------------------------------------------------------
gh_call() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [dry run] gh $2 ${*:3}"
    if [[ "$*" == *"--input -"* ]]; then cat > /dev/null; fi
    return 0
  fi
  gh "${@:2}"
}

reviewer_json() {
  local login id out="[]"
  IFS=',' read -ra logins <<< "${REVIEWERS}"
  for login in "${logins[@]}"; do
    if [[ "${DRY_RUN}" == "true" ]]; then
      id=0
    else
      id="$(gh api "users/${login}" --jq '.id')" || { echo "ERROR: could not find GitHub user '${login}'." >&2; exit 1; }
    fi
    out="$(jq -c --argjson id "${id}" '. + [{type: "User", id: $id}]' <<< "${out}")"
  done
  echo "${out}"
}

configure_environment() {
  local name="$1" reviewers="$2" body

  # Deployments may run from main (manual deploys) and from release tags (the build
  # that a tag push starts). A branch-only policy would refuse the tag runs.
  body="$(jq -cn --argjson reviewers "${reviewers}" \
    '{reviewers: $reviewers, deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}')"

  echo "  environment ${name}: reviewers=$(jq 'length' <<< "${reviewers}") from main and v* tags"

  printf '%s' "${body}" | gh_call "environment ${name}" api -X PUT "repos/${REPO}/environments/${name}" --input -

  # 422 means the policy already exists, which is the state we want.
  printf '%s' '{"name":"main","type":"branch"}' \
    | gh_call "branch policy ${name}" api -X POST "repos/${REPO}/environments/${name}/deployment-branch-policies" --input - 2>/dev/null || true
  printf '%s' '{"name":"v*","type":"tag"}' \
    | gh_call "tag policy ${name}" api -X POST "repos/${REPO}/environments/${name}/deployment-branch-policies" --input - 2>/dev/null || true

  gh_call "AWS_REGION ${name}" variable set AWS_REGION --repo "${REPO}" --env "${name}" --body "${REGION}" >/dev/null
}

configure_github() {
  local env reviewers with_reviewers="[]" first="${ENVIRONMENTS[0]}"

  [[ -n "${REVIEWERS}" ]] && with_reviewers="$(reviewer_json)"

  for env in "${ENVIRONMENTS[@]}"; do
    reviewers="[]"
    if [[ "${env}" != "${first}" ]]; then
      reviewers="${with_reviewers}"
      [[ -z "${REVIEWERS}" ]] && echo "  WARNING: no --reviewers given, so ${env} will have no required reviewer."
    fi

    configure_environment "${env}" "${reviewers}"
  done
}

# ------------------------------------------------------------------------------
echo "Deploy settings"
write_settings

if [[ "${SKIP_GITHUB}" == "true" ]]; then
  echo "GitHub Environments: skipped (--skip-github)."
else
  echo "GitHub Environments in ${REPO}"
  configure_github
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo
  echo "Dry run: nothing was written and GitHub was not called."
  exit 0
fi

echo
bash "${REPO_ROOT}/scripts/ci/check-placeholders.sh" "${REPO_ROOT}/deploy.json"

cat <<NEXT

Done. Next:

  1. Give core this repository's role entry:
       scripts/print-role-entry.sh
     Paste the JSON into core's infrastructure/<env>/data/service-roles.json, next to
     the entry the service's INFRASTRUCTURE repository prints for itself (they must
     share service_name and tier), and open a pull request there.

  2. Once core has applied it, connect this repository to its role:
       scripts/fetch-role-arn.sh --core OWNER/CORE-REPOSITORY --environment development

  3. Commit deploy.json.

See docs/deploy.md for the full walkthrough.
NEXT
