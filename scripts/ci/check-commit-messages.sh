#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# ARE THE COMMITS WORDED SO A RELEASE WILL SEE THEM?
#
# semantic-release decides the next version from commit messages, read with its
# default (angular) convention: "feat: ..." is a minor release, "fix: ..." or
# "perf: ..." a patch, a "BREAKING CHANGE:" note a major one. A message in any
# other shape is ignored without a word, and the change it carries never gets a
# release. This checks every commit a pull request adds, and its title (which
# becomes the commit when the pull request is squash-merged).
#
#   <type>(<optional scope>): <subject>
#   type: feat fix perf refactor docs style test build ci chore revert
#
# Merge commits and Git's own 'Revert "..."' are accepted.
#
# Usage: check-commit-messages.sh <base-sha> <head-sha> [<pull request title>]
# ==============================================================================

BASE="${1:?Usage: check-commit-messages.sh <base-sha> <head-sha> [<title>]}"
HEAD="${2:?head sha is required}"
TITLE="${3:-}"

PATTERN='^(feat|fix|perf|refactor|docs|style|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].*$'

bad=0
check_line() { # <what> <line>
  if [[ "$2" =~ ${PATTERN} || "$2" =~ ^Merge\  || "$2" =~ ^Revert\ \" ]]; then
    return 0
  fi
  echo "::error::$1 is not a Conventional Commit, so a release would ignore it: $2"
  bad=1
}

while IFS=$'\t' read -r sha subject; do
  [[ -z "${sha}" ]] && continue
  check_line "Commit ${sha:0:7}" "${subject}"
done < <(git log --format='%H%x09%s' "${BASE}..${HEAD}")

if [[ -n "${TITLE}" ]]; then
  check_line "The pull request's title" "${TITLE}"
fi

if [[ ${bad} -ne 0 ]]; then
  echo "Write each as <type>: <what changed>, e.g. \"feat: add the orders page\" or \"fix: keep the session on refresh\"." >&2
  echo "feat makes a minor release, fix or perf a patch; a \"BREAKING CHANGE:\" note in the body a major one." >&2
  exit 1
fi

echo "Every message is a Conventional Commit."
