#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="${SCRIPTS}/read-service-config.sh"
export FAKE_SSM_DIR="${WORK}/ssm" FAKE_LOG="${WORK}/aws.log"; mkdir -p "${FAKE_SSM_DIR}"; : > "${FAKE_LOG}"
param(){ printf '%s' "$2" > "${FAKE_SSM_DIR}/$(printf '%s' "$1" | tr '/' '_')"; }
CFG='{"schema_version":1,"service_name":"auth","service_type":"web","environment":"development","tier":"private","hosting_model":"shared","domain":"auth.dev.example.org","port":1024,"health_check_path":"/health","secret":{"arn":"arn:aws:secretsmanager:eu-west-1:123456789012:secret:acme-auth-development-secret-vault-AbC123","name":"acme-auth-development-secret-vault"},"ecr":{"repository_url":"123456789012.dkr.ecr.eu-west-1.amazonaws.com/auth/web","repository_name":"auth/web"},"target_group_arn":"arn:x","deploy":{"bucket":"acme-development-deploy","prefix":"private/auth","update_document":"acme-fleet-update"},"static":{"bucket":"acme-development-assets","prefix":"static/auth"},"database":{"engine":"postgres","host":"db.dev.example.org","port_parameter":"/acme/database/engines/postgres/port","secret_fields":{"name":"db_name","user":"db_user","password":"db_password"}}}'
NAME=/acme/services/auth/config
param $NAME "$CFG"; param /acme/database/engines/postgres/port 20001
run(){ bash "$R" acme auth eu-west-1; }
val(){ grep -x "$1=.*" <<< "$out" | cut -d= -f2-; }

echo "== read-service-config.sh"
out="$(run 2>/dev/null)"; rc=$?
check "reads the config"                               test $rc -eq 0
check "the registry host and repository name are split" bash -c "[ \"$(val ECR_REGISTRY_HOST)\" = 123456789012.dkr.ecr.eu-west-1.amazonaws.com ] && [ \"$(val ECR_REPOSITORY_NAME)\" = auth/web ]"
check "port, domain, secret"                           bash -c "[ \"$(val SERVICE_PORT)\" = 1024 ] && [ \"$(val SERVICE_DOMAIN)\" = auth.dev.example.org ] && [[ \"$(val APP_SECRET_ARN)\" == arn:aws:secretsmanager:* ]]"
check "deploy and static locations"                    bash -c "[ \"$(val DEPLOY_BUCKET)\" = acme-development-deploy ] && [ \"$(val DEPLOY_PREFIX)\" = private/auth ] && [ \"$(val STATIC_PREFIX)\" = static/auth ] && [ \"$(val UPDATE_DOCUMENT)\" = acme-fleet-update ]"
check "the database port comes from the platform's parameter" bash -c "[ \"$(val DATABASE_PORT)\" = 20001 ] && [ \"$(val DATABASE_HOST)\" = db.dev.example.org ]"
check "output is safe to append to GITHUB_ENV"         bash -c "! grep -vE '^[A-Z_]+=' <<< \"$out\""
check "no secret VALUE is ever read (only the ARN)"    bash -c "! grep -q 'secretsmanager get-secret-value' '${FAKE_LOG}'"

nodb="$(jq '.database = null' <<< "$CFG")"; param $NAME "$nodb"
out="$(run 2>/dev/null)"
check "a service without a database has no DATABASE_ lines" bash -c "! grep -q '^DATABASE_' <<< \"$out\""
param $NAME "$CFG"
check "a matching expected tier is accepted"           bash -c "bash '$R' acme auth eu-west-1 private >/dev/null 2>&1"
check "a DIFFERENT expected tier is refused"           bash -c "! bash '$R' acme auth eu-west-1 internal >/dev/null 2>&1"
check "a missing config is reported"                   bash -c "! bash '$R' acme other eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.schema_version = 2' <<< "$CFG")"
check "a newer schema version is refused"              bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$CFG"
shared="$(bash "$R" acme auth eu-west-1 2>/dev/null)"
check "a shared fleet targets the TIER's hosts"         grep -qx 'TARGET_SERVICE_TAG=private' <<< "$shared"

DED="$(jq '.hosting_model = "dedicated" | .deploy = {"bucket":"acme-production-auth-config","prefix":"services/auth","update_document":"acme-auth-update"}' <<< "$CFG")"
param $NAME "$DED"
out="$(bash "$R" acme auth eu-west-1 2>/dev/null)"; rc=$?
check "a dedicated environment is accepted"            test $rc -eq 0
check "it targets the SERVICE's own hosts"             bash -c "grep -qx 'TARGET_SERVICE_TAG=auth' <<< \"$out\""
check "with the service's own bucket and document"     bash -c "grep -qx 'DEPLOY_BUCKET=acme-production-auth-config' <<< \"$out\" && grep -qx 'DEPLOY_PREFIX=services/auth' <<< \"$out\" && grep -qx 'UPDATE_DOCUMENT=acme-auth-update' <<< \"$out\""
param $NAME "$(jq '.deploy.prefix = "services/billing"' <<< "$DED")"
check "a dedicated prefix naming another service is refused" bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.hosting_model = "serverless"' <<< "$CFG")"
check "an unknown hosting model is refused"            bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.hosting_model = "shared-fleet"' <<< "$CFG")"
check "the retired name shared-fleet is refused, so a half-migrated config fails loudly" bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.service_name = "billing"' <<< "$CFG")"
check "a config for another service is refused"        bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.secret.arn = null' <<< "$CFG")"
check "a missing value is refused"                     bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.domain = "a.example.org\nINJECTED=1"' <<< "$CFG")"
check "a value that could inject into GITHUB_ENV is refused" bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.deploy.prefix = "private/billing"' <<< "$CFG")"
check "a shared prefix naming another service is refused" bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$(jq '.deploy.prefix = "private/../other"' <<< "$CFG")"
check "a deploy prefix outside the service is refused" bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME "$CFG"; rm "${FAKE_SSM_DIR}/_acme_database_engines_postgres_port"
check "an unpublished database port is reported"       bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param /acme/database/engines/postgres/port "abc"
check "a non-numeric database port is refused"         bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
param $NAME 'not json'
check "a corrupt config is refused"                    bash -c "! bash '$R' acme auth eu-west-1 >/dev/null 2>&1"
finish
