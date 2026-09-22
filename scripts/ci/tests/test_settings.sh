#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="${SCRIPTS}/read-deploy-settings.sh"
P="${SCRIPTS}/check-placeholders.sh"
E="${SCRIPTS}/resolve-environments.sh"

echo "== read-deploy-settings.sh"
printf '{"project_name":"acme","service_name":"auth","tier":"internal"}' > "${WORK}/deploy.json"
out="$(bash "$S" "${WORK}/deploy.json" 2>/dev/null)"
check "reads the three values"                         bash -c "grep -qx 'PROJECT_NAME=acme' <<< \"$out\" && grep -qx 'SERVICE_NAME=auth' <<< \"$out\" && grep -qx 'SERVICE_TIER=internal' <<< \"$out\""
check "output is safe to append to GITHUB_ENV"         bash -c "! grep -vE '^[A-Z_]+=' <<< \"$out\""
printf '{"project_name":"CHANGE_ME","service_name":"auth","tier":"private"}' > "${WORK}/bad.json"
check "the CHANGE_ME placeholder is refused"           bash -c "! bash '$S' '${WORK}/bad.json' >/dev/null 2>&1"
printf '{"project_name":"acme","service_name":"auth","tier":"edge"}' > "${WORK}/bad.json"
check "an unknown tier is refused"                     bash -c "! bash '$S' '${WORK}/bad.json' >/dev/null 2>&1"
printf '{"project_name":"acme\\nX=1","service_name":"auth","tier":"private"}' > "${WORK}/bad.json"
check "a value that could inject into GITHUB_ENV is refused" bash -c "! bash '$S' '${WORK}/bad.json' >/dev/null 2>&1"
printf 'not json' > "${WORK}/bad.json"
check "invalid JSON is refused"                        bash -c "! bash '$S' '${WORK}/bad.json' >/dev/null 2>&1"
check "a missing file is refused"                      bash -c "! bash '$S' '${WORK}/none.json' >/dev/null 2>&1"

echo "== check-placeholders.sh"
printf '{"a":"x"}\n' > "${WORK}/ok.json"
check "a configured file passes"                       bash "$P" "${WORK}/ok.json"
printf '{"a":"CHANGE_ME"}\n' > "${WORK}/no.json"
check "a marker fails"                                 bash -c "! bash '$P' '${WORK}/no.json' >/dev/null 2>&1"
printf '# CHANGE_ME is described here\nkey=1\n' > "${WORK}/comment.txt"
check "a marker in a comment line is ignored"          bash "$P" "${WORK}/comment.txt"
check "a missing file is an error"                     bash -c "! bash '$P' '${WORK}/none' >/dev/null 2>&1"
check "no arguments is an error"                       bash -c "! bash '$P' >/dev/null 2>&1"

echo "== resolve-environments.sh"
mkdir -p "${WORK}/r/.github"
run(){ RESOLVE_ROOT="${WORK}/r" bash "$E" "$@" 2>/dev/null; }
printf '["development","staging","production"]' > "${WORK}/r/.github/environments.json"
check "auto is the lowest environment only"            test "$(run auto)" = '["development"]'
check "all is every environment in order"              test "$(run all)" = '["development","staging","production"]'
check "one: an enabled environment"                    test "$(run one staging)" = '["staging"]'
check "one: an unknown environment is refused"         bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$E' one qa >/dev/null 2>&1"
check "lower of the lowest is nothing"                 test -z "$(run lower development)"
check "lower of staging is development"                test "$(run lower staging)" = development
check "lower of production is staging"                 test "$(run lower production)" = staging
printf '["development"]' > "${WORK}/r/.github/environments.json"
check "a disabled environment is refused for one"      bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$E' one staging >/dev/null 2>&1"
check "a disabled environment is refused for lower"    bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$E' lower production >/dev/null 2>&1"
printf '{"not":"an array"}' > "${WORK}/r/.github/environments.json"
check "a malformed file is refused"                    bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$E' auto >/dev/null 2>&1"
printf '[]' > "${WORK}/r/.github/environments.json"
check "an empty list is refused"                       bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$E' auto >/dev/null 2>&1"
check "an unknown mode is refused"                     bash -c "! RESOLVE_ROOT='${WORK}/r' bash '$E' frobnicate >/dev/null 2>&1"
finish
