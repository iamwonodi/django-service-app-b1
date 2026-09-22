#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
P="${SCRIPTS}/publish-deploy-files.sh"
S="${SCRIPTS}/sync-static.sh"
export FAKE_LOG="${WORK}/calls.log"

echo "== publish-deploy-files.sh"
mkdir -p "${WORK}/r"; echo 'a=1' > "${WORK}/r/.env"; echo 'services: {}' > "${WORK}/r/docker-compose.yml"; : > "${FAKE_LOG}"
bash "$P" "${WORK}/r" acme-development-deploy private/auth eu-west-1 >/dev/null 2>&1; rc=$?
check "publishes"                                       test $rc -eq 0
check "to the service's own directory"                  bash -c "grep -q 's3://acme-development-deploy/private/auth/.env' '${FAKE_LOG}' && grep -q 's3://acme-development-deploy/private/auth/docker-compose.yml' '${FAKE_LOG}'"
check "the compose file goes LAST"                      bash -c "[ \"\$(grep -n 'docker-compose.yml' '${FAKE_LOG}' | head -1 | cut -d: -f1)\" -gt \"\$(grep -n '\.env s3' '${FAKE_LOG}' | head -1 | cut -d: -f1)\" ]"
check "nothing outside the prefix is touched"           bash -c "! grep -v 'private/auth' '${FAKE_LOG}' | grep -q 's3://'"
: > "${FAKE_LOG}"; bash "$P" "${WORK}/r" acme-production-auth-config services/auth eu-west-1 >/dev/null 2>&1
check "dedicated: publishes to services/<service>/"      grep -q 's3://acme-production-auth-config/services/auth/docker-compose.yml' "${FAKE_LOG}"
check "a prefix outside <tier>/<service> is refused"    bash -c "! bash '$P' '${WORK}/r' acme-x private/../other eu-west-1 >/dev/null 2>&1"
check "the bucket root is refused"                      bash -c "! bash '$P' '${WORK}/r' acme-x '' eu-west-1 >/dev/null 2>&1"
rm "${WORK}/r/.env"
check "a missing file is refused"                       bash -c "! bash '$P' '${WORK}/r' acme-x private/auth eu-west-1 >/dev/null 2>&1"
echo 'a=1' > "${WORK}/r/.env"
check "an upload failure is a failure"                  bash -c "! FAKE_S3_FAIL=1 bash '$P' '${WORK}/r' acme-x private/auth eu-west-1 >/dev/null 2>&1"

echo "== sync-static.sh"
mkdir -p "${WORK}/static/polls" "${WORK}/static/admin/css"
echo x > "${WORK}/static/polls/style.097cd14f550a.css"; echo x > "${WORK}/static/polls/style.css"
echo x > "${WORK}/static/admin/css/base.0223689e9ac5.css"; echo '{}' > "${WORK}/static/staticfiles.json"
export FAKE_STATIC_DIR="${WORK}/static"; : > "${FAKE_LOG}"
bash "$S" 123.dkr.ecr.eu-west-1.amazonaws.com/auth/web:v1 acme-development-assets static/auth eu-west-1 >/dev/null 2>&1; rc=$?
check "uploads"                                         test $rc -eq 0
check "the files come out of the image's /app/staticfiles" grep -q 'docker cp fake-container-id:/app/staticfiles' "${FAKE_LOG}"
check "they go to the service's own prefix"             bash -c "[ \"\$(grep -c 's3 sync' '${FAKE_LOG}')\" = 2 ] && [ \"\$(grep 's3 sync' '${FAKE_LOG}' | grep -c 's3://acme-development-assets/static/auth/')\" = 2 ]"
check "hashed files are cached for a year"              bash -c "grep 's3 sync' '${FAKE_LOG}' | grep -q 'max-age=31536000, immutable'"
check "unhashed copies get a short cache"               bash -c "grep 's3 sync' '${FAKE_LOG}' | grep -q 'max-age=300'"
check "NEVER --delete (older releases need their files)" bash -c "! grep -q -- '--delete' '${FAKE_LOG}'"
check "the container is removed afterwards"             grep -q 'docker rm fake-container-id' "${FAKE_LOG}"
check "a prefix outside static/<service> is refused"    bash -c "! bash '$S' img acme-x static/../x eu-west-1 >/dev/null 2>&1"
check "the bucket root is refused"                      bash -c "! bash '$S' img acme-x '' eu-west-1 >/dev/null 2>&1"
export FAKE_STATIC_DIR="${WORK}/nonexistent"
check "an image without /app/staticfiles is refused"    bash -c "! bash '$S' img acme-x static/auth eu-west-1 >/dev/null 2>&1"
mkdir -p "${WORK}/empty"; export FAKE_STATIC_DIR="${WORK}/empty"
check "an empty static directory is refused"            bash -c "! bash '$S' img acme-x static/auth eu-west-1 >/dev/null 2>&1"
finish
