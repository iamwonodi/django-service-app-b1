#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TOP="$(cd "${SCRIPTS}/.." && pwd)"
INIT="${TOP}/init-app.sh"; ENTRY="${TOP}/print-role-entry.sh"; FETCH="${TOP}/fetch-role-arn.sh"
SOURCE_ROOT="$(cd "${TOP}/.." && pwd)"

fresh(){
  rm -rf "${WORK}/repo"; mkdir -p "${WORK}/repo/scripts/ci" "${WORK}/repo/.github"
  cp "${SOURCE_ROOT}/deploy.json" "${WORK}/repo/"; cp "${SOURCE_ROOT}/.github/environments.json" "${WORK}/repo/.github/"
  cp "${SCRIPTS}/check-placeholders.sh" "${WORK}/repo/scripts/ci/"
  git -C "${WORK}/repo" init -q; git -C "${WORK}/repo" remote add origin https://github.com/acme/auth-app.git
  export INIT_REPO_ROOT="${WORK}/repo" FAKE_GH_LOG="${WORK}/gh.log"; : > "${FAKE_GH_LOG}"
}
ARGS=(--project acme --service auth --region eu-west-1 --reviewers alice)
run(){ bash "${INIT}" "${ARGS[@]}" "$@"; }
body_of(){ grep -A1 "environments/$1 --input" "${FAKE_GH_LOG}" | grep '^BODY' | head -1 | sed 's/^BODY //'; }
export FAKE_GH_REPO_JSON='{"id": 333, "full_name": "acme/auth-app", "created_at": "2026-09-01T10:00:00Z", "owner": {"id": 111}}'

echo "== init-app.sh"
fresh; run >"${WORK}/out.txt" 2>&1; rc=$?
check "run succeeds"                                     test $rc -eq 0
check "deploy.json is written"                           bash -c "jq -e '.project_name == \"acme\" and .service_name == \"auth\" and .tier == \"private\"' '${WORK}/repo/deploy.json' >/dev/null"
check "no placeholder remains"                           bash "${WORK}/repo/scripts/ci/check-placeholders.sh" "${WORK}/repo/deploy.json"
snap="$(sha256sum "${WORK}/repo/deploy.json")"; run >/dev/null 2>&1
check "re-running changes nothing (idempotent)"          test "$(sha256sum "${WORK}/repo/deploy.json")" = "$snap"
fresh; run --tier internal >/dev/null 2>&1
check "--tier is honoured"                               bash -c "jq -e '.tier == \"internal\"' '${WORK}/repo/deploy.json' >/dev/null"

echo "== GitHub environments"
fresh; run >/dev/null 2>&1
check "the enabled environment is configured"            grep -q "^gh api -X PUT repos/acme/auth-app/environments/development --input -" "${FAKE_GH_LOG}"
check "no -plan environment (this repository has no plan)" bash -c "! grep -q 'development-plan' '${FAKE_GH_LOG}'"
check "deployments may come from main"                   grep -q 'BODY {"name":"main","type":"branch"}' "${FAKE_GH_LOG}"
check "and from release tags (a tag push starts a build)" grep -q 'BODY {"name":"v\*","type":"tag"}' "${FAKE_GH_LOG}"
check "the lowest environment has no reviewers"          bash -c "echo '$(body_of development)' | jq -e '.reviewers == []' >/dev/null"
check "AWS_REGION is set"                                grep -q "^gh variable set AWS_REGION --repo acme/auth-app --env development --body eu-west-1" "${FAKE_GH_LOG}"
check "staging is untouched while not enabled"           bash -c "! grep -q 'environments/staging' '${FAKE_GH_LOG}'"
fresh; echo '["development","staging","production"]' > "${WORK}/repo/.github/environments.json"; run >/dev/null 2>&1
check "an enabled staging requires the reviewers"        bash -c "echo '$(body_of staging)' | jq -e '(.reviewers | length) == 1 and .reviewers[0].id == 4242' >/dev/null"
check "and production"                                   bash -c "echo '$(body_of production)' | jq -e '(.reviewers | length) == 1' >/dev/null"
check "the lowest of three still has none"               bash -c "echo '$(body_of development)' | jq -e '.reviewers == []' >/dev/null"
fresh; bash "${INIT}" --project acme --service auth --region eu-west-1 --skip-github >/dev/null 2>&1
check "--skip-github makes no gh call"                   test ! -s "${FAKE_GH_LOG}"

echo "== dry run and validation"
fresh; before="$(sha256sum "${WORK}/repo/deploy.json")"; run --dry-run >/dev/null 2>&1
check "dry run changes no file and calls nothing"        bash -c "[ \"$(sha256sum "${WORK}/repo/deploy.json")\" = \"$before\" ] && [ ! -s '${FAKE_GH_LOG}' ]"
bad(){ fresh; before="$(sha256sum "${WORK}/repo/deploy.json")"; bash "${INIT}" "$@" >/dev/null 2>&1; rc=$?; [[ $rc -ne 0 && "$(sha256sum "${WORK}/repo/deploy.json")" = "$before" && ! -s "${FAKE_GH_LOG}" ]]; }
check "bad project"                                      bad --project Bad --service auth --region eu-west-1
check "bad service"                                      bad --project acme --service Auth_1 --region eu-west-1
check "a platform-reserved service name"                 bad --project acme --service platform --region eu-west-1
check "bad region"                                       bad --project acme --service auth --region nowhere
check "bad tier"                                         bad --project acme --service auth --region eu-west-1 --tier edge
check "bad reviewers"                                    bad --project acme --service auth --region eu-west-1 --reviewers 'a b'
check "unknown option"                                   bad --project acme --service auth --region eu-west-1 --bogus
fresh; FAKE_GH_NO_USER=1 bash "${INIT}" "${ARGS[@]}" >/dev/null 2>&1
check "an unknown reviewer login fails"                  test $? -ne 0

echo "== print-role-entry.sh"
fresh; bash "${INIT}" "${ARGS[@]}" --skip-github >/dev/null 2>&1
out="$(bash "$ENTRY" 2>/dev/null)"; rc=$?
check "prints an entry"                                  test $rc -eq 0
check "kind is app"                                      bash -c "echo '$out' | jq -e '.[\"acme/auth-app\"].kind == \"app\"' >/dev/null"
check "service and tier come from deploy.json"           bash -c "echo '$out' | jq -e '.[\"acme/auth-app\"].service_name == \"auth\" and .[\"acme/auth-app\"].tier == \"private\"' >/dev/null"
check "the IDs are strings, as core expects"             bash -c "echo '$out' | jq -e '.[\"acme/auth-app\"].owner_id == \"111\" and .[\"acme/auth-app\"].repository_id == \"333\"' >/dev/null"
fresh
check "refuses while the service is not configured"      bash -c "! bash '$ENTRY' >/dev/null 2>&1"
check "a gh failure is reported"                         bash -c "! FAKE_GH_FAIL=1 bash '$ENTRY' >/dev/null 2>&1"

echo "== fetch-role-arn.sh"
fresh
printf '{"environment":"development","service_role_arns":{"acme/auth-infra":"arn:aws:iam::123456789012:role/services/auth/infra","acme/auth-app":"arn:aws:iam::123456789012:role/services/auth/app"}}' > "${WORK}/arns.json"
export FAKE_GH_ROLE_ARNS_FILE="${WORK}/arns.json"
bash "$FETCH" --core acme/core --environment development >/dev/null 2>&1; rc=$?
check "succeeds"                                         test $rc -eq 0
check "sets AWS_ROLE_ARN with THIS repository's role"    grep -q 'gh secret set AWS_ROLE_ARN --repo acme/auth-app --env development --body arn:aws:iam::123456789012:role/services/auth/app' "${FAKE_GH_LOG}"
check "never the infrastructure repository's role"       bash -c "! grep -q 'services/auth/infra' '${FAKE_GH_LOG}'"
check "only the environment itself (no -plan)"           bash -c "! grep -q 'development-plan' '${FAKE_GH_LOG}'"
: > "${FAKE_GH_LOG}"
check "a repository with no role is refused"             bash -c "! bash '$FETCH' --core acme/core --environment development --repo acme/unknown >/dev/null 2>&1"
check "and nothing is set"                               bash -c "! grep -q 'secret set' '${FAKE_GH_LOG}'"
printf '{"service_role_arns":{"acme/auth-app":"nope"}}' > "${WORK}/bad.json"; export FAKE_GH_ROLE_ARNS_FILE="${WORK}/bad.json"
check "a malformed ARN is refused"                       bash -c "! bash '$FETCH' --core acme/core --environment development >/dev/null 2>&1"
export FAKE_GH_ROLE_ARNS_FILE="${WORK}/missing.json"
check "a missing role-arns file is reported"             bash -c "! bash '$FETCH' --core acme/core --environment development >/dev/null 2>&1"
check "bad --core"                                       bash -c "! bash '$FETCH' --core nonsense --environment development >/dev/null 2>&1"
check "bad --environment"                                bash -c "! bash '$FETCH' --core acme/core --environment qa >/dev/null 2>&1"
finish
