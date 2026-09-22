#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="${SCRIPTS}/render-deploy-files.sh"
APP="$(cd "${SCRIPTS}/../../app" && pwd)"
export IMAGE=123456789012.dkr.ecr.eu-west-1.amazonaws.com/auth/web:v1.2.0 SERVICE_PORT=1024 SERVICE_NAME=auth SERVICE_DOMAIN=auth.dev.example.org DATABASE_HOST=db.dev.example.org DATABASE_PORT=20001 APP_SECRET_ARN=arn:aws:secretsmanager:eu-west-1:123456789012:secret:acme-auth-development-secret-vault-AbC123

echo "== render-deploy-files.sh (against the real templates in app/)"
rm -rf "${WORK}/out"; bash "$R" "${APP}" "${WORK}/out" >/dev/null 2>&1; rc=$?
check "renders the real compose file and .env"        test $rc -eq 0
check "the image and port are filled in"              bash -c "grep -q 'image: ${IMAGE}' '${WORK}/out/docker-compose.yml' && grep -q '\"1024:8000\"' '${WORK}/out/docker-compose.yml'"
check "the service's values are filled in"            bash -c "grep -q '^SERVICE_NAME=auth' '${WORK}/out/.env' && grep -q '^DJANGO_ALLOWED_HOSTS=auth.dev.example.org' '${WORK}/out/.env' && grep -q '^DATABASE_PORT=20001' '${WORK}/out/.env' && grep -q '^DATABASE_HOST=db.dev.example.org' '${WORK}/out/.env'"
check "the secret ARN is filled in"                   bash -c "grep -q '^APP_SECRET_ARN=${APP_SECRET_ARN}' '${WORK}/out/.env'"
check "__FROM_SECRET__ references are left for the host" bash -c "grep -c '^[A-Z_]*=__FROM_SECRET__:APP_SECRET_ARN' '${WORK}/out/.env' | grep -qx 4"
check "no other placeholder remains outside comments" bash -c "! grep -v '^[[:space:]]*#' '${WORK}/out/'{docker-compose.yml,.env} | grep -oE '__[A-Z_]+__' | grep -vx '__FROM_SECRET__' | grep -q ."
check "the templates in app/ are not modified"        bash -c "grep -q '__IMAGE__' '${APP}/docker-compose.yml' && grep -q '__SERVICE_DOMAIN__' '${APP}/.env'"
check "placeholders mentioned in comments are untouched" bash -c "grep -q '^#   __SERVICE_NAME__' '${WORK}/out/.env'"

echo "== failures"
check "a missing value leaves a placeholder: refused"  bash -c "! SERVICE_PORT= bash '$R' '${APP}' '${WORK}/o2' >/dev/null 2>&1"
check "a missing database host is refused (never a literal __DATABASE_HOST__)" bash -c "! DATABASE_HOST= bash '$R' '${APP}' '${WORK}/o3' >/dev/null 2>&1"
check "a value with a shell or sed metacharacter is refused" bash -c "! IMAGE='a&b' bash '$R' '${APP}' '${WORK}/o4' >/dev/null 2>&1"
check "a value with a newline is refused"              bash -c "! SERVICE_DOMAIN=\$'a.org\nX=1' bash '$R' '${APP}' '${WORK}/o5' >/dev/null 2>&1"
check "a missing template is refused"                  bash -c "! bash '$R' '${WORK}/nowhere' '${WORK}/o6' >/dev/null 2>&1"

echo "== a service without a database"
mkdir -p "${WORK}/nodb"; cp "${APP}/docker-compose.yml" "${WORK}/nodb/"; grep -v '^DATABASE_\|DATABASE_NAME\|DATABASE_USERNAME\|DATABASE_PASSWORD' "${APP}/.env" > "${WORK}/nodb/.env"
check "renders once the DATABASE_ lines are removed"   bash -c "DATABASE_HOST= DATABASE_PORT= bash '$R' '${WORK}/nodb' '${WORK}/o7' >/dev/null 2>&1"
finish
