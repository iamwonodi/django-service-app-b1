#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
C="${SCRIPTS}/check-promotion.sh"
W="${SCRIPTS}/record-deployment.sh"
export FAKE_GH_LOG="${WORK}/gh.log" FAKE_GH_STATUSES_DIR="${WORK}/statuses" FAKE_GH_DEPLOYMENTS_FILE="${WORK}/deployments.json"
mkdir -p "${WORK}/statuses" "${WORK}/repo/.github" "${WORK}/repo/scripts/ci"
cp "${SCRIPTS}/check-promotion.sh" "${SCRIPTS}/resolve-environments.sh" "${WORK}/repo/scripts/ci/"
printf '["development","staging","production"]' > "${WORK}/repo/.github/environments.json"
CP="${WORK}/repo/scripts/ci/check-promotion.sh"
: > "${FAKE_GH_LOG}"

echo "== check-promotion.sh"
check "the lowest environment needs no gate"            bash "$CP" acme/auth development v1.2.0
echo '[]' > "${FAKE_GH_DEPLOYMENTS_FILE}"
check "staging: a tag never deployed to development is refused" bash -c "! bash '$CP' acme/auth staging v1.2.0 >/dev/null 2>&1"
echo '[{"id": 11}]' > "${FAKE_GH_DEPLOYMENTS_FILE}"; echo '[{"state":"failure"}]' > "${WORK}/statuses/11.json"
check "a FAILED deployment does not count"              bash -c "! bash '$CP' acme/auth staging v1.2.0 >/dev/null 2>&1"
echo '[{"state":"in_progress"}]' > "${WORK}/statuses/11.json"
check "a deployment still in progress does not count"   bash -c "! bash '$CP' acme/auth staging v1.2.0 >/dev/null 2>&1"
echo '[{"id": 11}, {"id": 12}]' > "${FAKE_GH_DEPLOYMENTS_FILE}"; echo '[{"state":"success"}]' > "${WORK}/statuses/12.json"
check "a successful deployment allows the promotion"    bash "$CP" acme/auth staging v1.2.0
check "it asked about the LOWER environment and the tag" grep -q 'environment=development&ref=v1.2.0' "${FAKE_GH_LOG}"
: > "${FAKE_GH_LOG}"; bash "$CP" acme/auth production v1.2.0 >/dev/null 2>&1
check "production asks about STAGING"                   grep -q 'environment=staging&ref=v1.2.0' "${FAKE_GH_LOG}"
check "a bad tag is refused"                            bash -c "! bash '$CP' acme/auth staging main >/dev/null 2>&1"
check "a bad environment is refused"                    bash -c "! bash '$CP' acme/auth 'st;x' v1.2.0 >/dev/null 2>&1"
check "a bad repository is refused"                     bash -c "! bash '$CP' nonsense staging v1.2.0 >/dev/null 2>&1"
check "a disabled environment is refused"               bash -c "printf '[\"development\"]' > '${WORK}/repo/.github/environments.json'; ! bash '$CP' acme/auth staging v1.2.0 >/dev/null 2>&1"
check "a gh failure is reported"                        bash -c "! FAKE_GH_FAIL=1 bash '$CP' acme/auth production v1.2.0 >/dev/null 2>&1"

echo "== record-deployment.sh"
: > "${FAKE_GH_LOG}"
bash "$W" acme/auth development v1.2.0 https://github.com/acme/auth/actions/runs/1 >/dev/null 2>&1; rc=$?
check "records"                                         test $rc -eq 0
check "the deployment's ref is the TAG"                 bash -c "grep '^BODY' '${FAKE_GH_LOG}' | sed 's/^BODY //' | head -1 | jq -e '.ref == \"v1.2.0\" and .environment == \"development\" and .auto_merge == false and .required_contexts == []' >/dev/null"
check "a success status follows, with the log URL"      bash -c "grep '^BODY' '${FAKE_GH_LOG}' | sed 's/^BODY //' | tail -1 | jq -e '.state == \"success\" and (.log_url | startswith(\"https://\"))' >/dev/null"
check "the status is posted to the new deployment"      grep -q 'deployments/4242/statuses' "${FAKE_GH_LOG}"
check "a bad tag is refused"                            bash -c "! bash '$W' acme/auth development main https://x.org >/dev/null 2>&1"
check "a non-https URL is refused"                      bash -c "! bash '$W' acme/auth development v1.2.0 'http://x.org' >/dev/null 2>&1"
check "a bad environment is refused"                    bash -c "! bash '$W' acme/auth 'dev;x' v1.2.0 https://x.org >/dev/null 2>&1"
check "a gh failure is reported"                        bash -c "! FAKE_GH_FAIL=1 bash '$W' acme/auth development v1.2.0 https://x.org >/dev/null 2>&1"
finish
