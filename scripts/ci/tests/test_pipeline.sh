#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
APP="$(cd "${SCRIPTS}/../../app" && pwd)"
export FAKE_LOG="${WORK}/aws.log" FAKE_SSM_DIR="${WORK}/ssm" FAKE_INVOCATIONS_DIR="${WORK}/inv" REDEPLOY_INTERVAL=0
mkdir -p "${FAKE_SSM_DIR}" "${FAKE_INVOCATIONS_DIR}" "${WORK}/static/polls"
: > "${FAKE_LOG}"
echo x > "${WORK}/static/polls/style.097cd14f550a.css"; export FAKE_STATIC_DIR="${WORK}/static"
param(){ printf '%s' "$2" > "${FAKE_SSM_DIR}/$(printf '%s' "$1" | tr '/' '_')"; }
param /acme/services/auth/config '{"schema_version":1,"service_name":"auth","service_type":"web","environment":"development","tier":"private","hosting_model":"shared","domain":"auth.dev.example.org","port":1024,"health_check_path":"/health","secret":{"arn":"arn:aws:secretsmanager:eu-west-1:123456789012:secret:acme-auth-development-secret-vault-AbC123","name":"acme-auth-development-secret-vault"},"ecr":{"repository_url":"123456789012.dkr.ecr.eu-west-1.amazonaws.com/auth/web","repository_name":"auth/web"},"target_group_arn":"arn:x","deploy":{"bucket":"acme-development-deploy","prefix":"private/auth","update_document":"acme-fleet-update"},"static":{"bucket":"acme-development-assets","prefix":"static/auth"},"database":{"engine":"postgres","host":"db.dev.example.org","port_parameter":"/acme/database/engines/postgres/port","secret_fields":{"name":"db_name","user":"db_user","password":"db_password"}}}'
param /acme/database/engines/postgres/port 20001
printf '[{"id":"i-1","status":"Success","detail":"Success","out":"started"}]' > "${FAKE_INVOCATIONS_DIR}/1.json"
printf '{"project_name":"acme","service_name":"auth","tier":"private"}' > "${WORK}/deploy.json"

# One step of a workflow: run it, and let its KEY=VALUE output become the next steps' environment,
# exactly as appending to GITHUB_ENV does.
GITHUB_ENV_FILE="${WORK}/github_env"; : > "${GITHUB_ENV_FILE}"
step_env(){ set -a; # shellcheck disable=SC1090
            source "${GITHUB_ENV_FILE}"; set +a; }

echo "== the deploy job, step by step, as the workflow runs it"
export TAG=v1.2.0 AWS_REGION=eu-west-1
bash "${SCRIPTS}/read-deploy-settings.sh" "${WORK}/deploy.json" >> "${GITHUB_ENV_FILE}" 2>&1; rc=$?
check "Read Deploy Settings"                             test $rc -eq 0
step_env
bash "${SCRIPTS}/read-service-config.sh" "${PROJECT_NAME}" "${SERVICE_NAME}" "${AWS_REGION}" "${SERVICE_TIER}" >> "${GITHUB_ENV_FILE}" 2>&1; rc=$?
check "Read Service Config (with the tier cross-check)"  test $rc -eq 0
step_env
export IMAGE="${ECR_REPOSITORY_URL}:${TAG}"
bash "${SCRIPTS}/sync-static.sh" "${IMAGE}" "${STATIC_BUCKET}" "${STATIC_PREFIX}" "${AWS_REGION}" >/dev/null 2>&1
check "Upload Static Files"                              test $? -eq 0
bash "${SCRIPTS}/render-deploy-files.sh" "${APP}" "${WORK}/rendered" >/dev/null 2>&1
check "Render Deploy Files: every value came from the platform" test $? -eq 0
bash "${SCRIPTS}/publish-deploy-files.sh" "${WORK}/rendered" "${DEPLOY_BUCKET}" "${DEPLOY_PREFIX}" "${AWS_REGION}" >/dev/null 2>&1
check "Publish Deploy Files"                             test $? -eq 0
bash "${SCRIPTS}/redeploy.sh" "${UPDATE_DOCUMENT}" "${PROJECT_NAME}" "${SERVICE_TIER}" "${AWS_REGION}" "${TAG}" >/dev/null 2>&1
check "Redeploy And Wait"                                test $? -eq 0

echo "== what reached AWS"
check "the image reference names the release"            grep -q "image: 123456789012.dkr.ecr.eu-west-1.amazonaws.com/auth/web:v1.2.0" "${WORK}/rendered/docker-compose.yml"
check "the host port is the one the infrastructure chose" grep -q '"1024:8000"' "${WORK}/rendered/docker-compose.yml"
check "the database port is the platform's, read at deploy time" grep -q '^DATABASE_PORT=20001' "${WORK}/rendered/.env"
check "static files went to the service's prefix, then the deploy files (order)" bash -c "[ \"\$(grep -n 's3 sync' '${FAKE_LOG}' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 's3 cp' '${FAKE_LOG}' | head -1 | cut -d: -f1)\" ]"
check "the redeploy came LAST"                           bash -c "[ \"\$(grep -n 'ssm send-command' '${FAKE_LOG}' | head -1 | cut -d: -f1)\" -gt \"\$(grep -n 's3 cp' '${FAKE_LOG}' | tail -1 | cut -d: -f1)\" ]"
check "only the service's own S3 locations were written" bash -c "grep -o 's3://[^ ]*' '${FAKE_LOG}' | sort -u | grep -vE '^s3://(acme-development-assets/static/auth/|acme-development-deploy/private/auth/)' | wc -l | grep -qx 0"
check "the only SSM command was the fleet-update document" bash -c "[ \"\$(grep -c 'ssm send-command' '${FAKE_LOG}')\" = 1 ] && grep 'ssm send-command' '${FAKE_LOG}' | grep -q -- '--document-name acme-fleet-update'"
check "no secret value was ever read by the pipeline"    bash -c "! grep -qi 'get-secret-value' '${FAKE_LOG}'"
check "no script runs Terraform (comments may mention it)" bash -c "! grep -hE '^[^#]*\\bterraform +(init|output|plan|apply|-chdir)' '${SCRIPTS}'/*.sh | grep -q ."

echo "== the pipeline stops at the first problem"
: > "${GITHUB_ENV_FILE}"; param /acme/services/auth/config '{"schema_version":1,"service_name":"auth","tier":"internal","hosting_model":"shared"}'
check "a tier mismatch stops the deploy before anything is published" bash -c "! bash '${SCRIPTS}/read-service-config.sh' acme auth eu-west-1 private >/dev/null 2>&1"
finish
