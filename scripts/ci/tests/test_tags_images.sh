#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
T="${SCRIPTS}/resolve-tags.sh"
I="${SCRIPTS}/check-image-exists.sh"
V="${SCRIPTS}/validate-confirmation.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkdir -p "${WORK}/g"; cd "${WORK}/g" && git init -q -b main && git commit -q --allow-empty -m init
for t in v1.0.0 v1.2.0 v1.10.0 v1.2.1-rc.1 not-a-release; do git tag "$t"; done
out(){ rm -f "${WORK}/o"; GITHUB_OUTPUT="${WORK}/o" bash "$T" "$@" >/dev/null 2>&1 && cat "${WORK}/o"; }

echo "== resolve-tags.sh"
check "single: an existing release tag"                 test "$(out single v1.2.0)" = 'tags=["v1.2.0"]'
check "single: a missing tag is refused"                bash -c "! GITHUB_OUTPUT='${WORK}/o' bash '$T' single v9.9.9 >/dev/null 2>&1"
check "single: a non-release tag is refused"            bash -c "! GITHUB_OUTPUT='${WORK}/o' bash '$T' single not-a-release >/dev/null 2>&1"
check "latest sorts by version, not alphabetically"     test "$(out latest)" = 'tags=["v1.10.0"]'
check "manual: a list"                                  test "$(out manual 'v1.0.0, v1.2.0')" = 'tags=["v1.0.0","v1.2.0"]'
check "manual: all, oldest first, releases only"        test "$(out manual all)" = 'tags=["v1.0.0","v1.2.0","v1.2.1-rc.1","v1.10.0"]'
check "manual: an unknown tag in the list is refused"   bash -c "! GITHUB_OUTPUT='${WORK}/o' bash '$T' manual 'v1.0.0,v7.7.7' >/dev/null 2>&1"
check "manual: an empty input is refused"               bash -c "! GITHUB_OUTPUT='${WORK}/o' bash '$T' manual '' >/dev/null 2>&1"
check "an unknown mode is refused"                      bash -c "! GITHUB_OUTPUT='${WORK}/o' bash '$T' frobnicate >/dev/null 2>&1"
mkdir -p "${WORK}/empty"; cd "${WORK}/empty" && git init -q -b main && git commit -q --allow-empty -m init
check "latest with no release tags is an error"         bash -c "! GITHUB_OUTPUT='${WORK}/o' bash '$T' latest >/dev/null 2>&1"

echo "== check-image-exists.sh"
export FAKE_LOG="${WORK}/aws.log"
rm -f "${WORK}/o"; FAKE_ECR_EXISTS=true GITHUB_OUTPUT="${WORK}/o" bash "$I" auth/web v1.2.0 eu-west-1 >/dev/null 2>&1
check "an existing tag -> exists=true"                  grep -qx 'exists=true' "${WORK}/o"
rm -f "${WORK}/o"; GITHUB_OUTPUT="${WORK}/o" bash "$I" auth/web v1.2.0 eu-west-1 >/dev/null 2>&1
check "a missing tag -> exists=false (not an error)"    grep -qx 'exists=false' "${WORK}/o"
check "it asks about the repository and tag"            grep -q 'ecr describe-images --repository-name auth/web --image-ids imageTag=v1.2.0' "${FAKE_LOG}"
check "missing arguments are refused"                   bash -c "! bash '$I' auth/web >/dev/null 2>&1"

echo "== validate-confirmation.sh"
check "the environment's name confirms it"              bash "$V" production production ALL
check "a different name does not"                       bash -c "! bash '$V' production staging ALL >/dev/null 2>&1"
check "an empty confirmation does not"                  bash -c "! bash '$V' production '' ALL >/dev/null 2>&1"
check "all needs the keyword"                           bash "$V" all ALL ALL
check "all is not confirmed by 'all'"                   bash -c "! bash '$V' all all ALL >/dev/null 2>&1"
finish
