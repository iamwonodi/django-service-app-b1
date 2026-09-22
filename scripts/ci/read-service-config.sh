#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# READ THE SERVICE'S CONFIG FROM THE PLATFORM
#
# The service's infrastructure repository publishes one SSM parameter,
#   /<project>/services/<service>/config
# holding what this repository needs to deploy: where to push the image, where to
# publish files, which document redeploys, the port, the domain, the secret. This
# reads it, checks it, and prints KEY=VALUE lines for GITHUB_ENV. Nothing here
# comes from Terraform state or outputs.
#
# When the service has a database, its engine's port is read too: the platform
# team publishes it under the config's database.port_parameter.
#
# Every value must be a plain token (letters, digits and : / . _ @ + = , -). A
# value with a newline or a quote could otherwise inject variables into GITHUB_ENV.
#
# The optional tier is what deploy.json says. A config that names a different tier
# is refused: the redeploy would otherwise go to the wrong tier's hosts.
#
# Usage: read-service-config.sh <project> <service> <aws-region> [expected-tier]
# Needs: aws, jq.
# ==============================================================================

PROJECT="${1:?Usage: read-service-config.sh <project> <service> <aws-region>}"
SERVICE="${2:?service is required}"
REGION="${3:?aws-region is required}"
EXPECTED_TIER="${4:-}"

NAME="/${PROJECT}/services/${SERVICE}/config"

if ! RAW="$(aws ssm get-parameter --name "${NAME}" --query Parameter.Value --output text --region "${REGION}" 2>&1)"; then
  echo "ERROR: could not read ${NAME}." >&2
  echo "       ${RAW}" >&2
  echo "       Has the service's infrastructure repository applied yet, and can this role read it?" >&2
  exit 1
fi

jq -e 'type == "object"' <<< "${RAW}" >/dev/null 2>&1 || { echo "ERROR: ${NAME} is not a JSON object." >&2; exit 1; }

get() { jq -r "$1 // empty" <<< "${RAW}"; }

VERSION="$(get .schema_version)"
[[ "${VERSION}" == "1" ]] || { echo "ERROR: ${NAME} has schema_version '${VERSION}'; this pipeline was written for 1." >&2; exit 1; }

[[ "$(get .service_name)" == "${SERVICE}" ]] || { echo "ERROR: ${NAME} describes service '$(get .service_name)', not '${SERVICE}'." >&2; exit 1; }

# Two hosting models, decided by the platform per environment:
#   shared        the tier's hosts, tagged Service=<tier>, redeployed by core's
#                 fleet-update document; files under <tier>/<service>/
#   dedicated     the service's own hosts, tagged Service=<service>, redeployed by
#                 the service's own document; files under services/<service>/
# The deploy steps are identical: only where the files go and which hosts are
# told to redeploy differ, and the config says both.
HOSTING="$(get .hosting_model)"
case "${HOSTING}" in
  shared)    TARGET_SERVICE_TAG="$(get .tier)" ;;
  dedicated) TARGET_SERVICE_TAG="${SERVICE}" ;;
  *) echo "ERROR: hosting_model is '${HOSTING}', which this pipeline does not know how to deploy to." >&2; exit 1 ;;
esac

if [[ -n "${EXPECTED_TIER}" && "$(get .tier)" != "${EXPECTED_TIER}" ]]; then
  echo "ERROR: ${NAME} says the service runs on the '$(get .tier)' tier, but deploy.json says '${EXPECTED_TIER}'." >&2
  echo "       They must agree with the service's infrastructure repository." >&2
  exit 1
fi

REPOSITORY_URL="$(get .ecr.repository_url)"

declare -A VALUES=(
  [ECR_REPOSITORY_URL]="${REPOSITORY_URL}"
  [ECR_REGISTRY_HOST]="${REPOSITORY_URL%%/*}"
  [ECR_REPOSITORY_NAME]="${REPOSITORY_URL#*/}"
  [SERVICE_PORT]="$(get .port)"
  [SERVICE_DOMAIN]="$(get .domain)"
  [APP_SECRET_ARN]="$(get .secret.arn)"
  [DEPLOY_BUCKET]="$(get .deploy.bucket)"
  [DEPLOY_PREFIX]="$(get .deploy.prefix)"
  [UPDATE_DOCUMENT]="$(get .deploy.update_document)"
  [STATIC_BUCKET]="$(get .static.bucket)"
  [STATIC_PREFIX]="$(get .static.prefix)"
  [SERVICE_TIER]="$(get .tier)"
  [HOSTING_MODEL]="${HOSTING}"
  [TARGET_SERVICE_TAG]="${TARGET_SERVICE_TAG}"
)

ORDER=(ECR_REPOSITORY_URL ECR_REGISTRY_HOST ECR_REPOSITORY_NAME SERVICE_PORT SERVICE_DOMAIN APP_SECRET_ARN DEPLOY_BUCKET DEPLOY_PREFIX UPDATE_DOCUMENT STATIC_BUCKET STATIC_PREFIX SERVICE_TIER HOSTING_MODEL TARGET_SERVICE_TAG)

DATABASE_ENGINE="$(get .database.engine)"

if [[ -n "${DATABASE_ENGINE}" ]]; then
  PORT_PARAMETER="$(get .database.port_parameter)"

  VALUES[DATABASE_ENGINE]="${DATABASE_ENGINE}"
  VALUES[DATABASE_HOST]="$(get .database.host)"

  [[ -n "${PORT_PARAMETER}" ]] || { echo "ERROR: ${NAME} has a database but no database.port_parameter." >&2; exit 1; }

  if ! DATABASE_PORT="$(aws ssm get-parameter --name "${PORT_PARAMETER}" --query Parameter.Value --output text --region "${REGION}" 2>&1)"; then
    echo "ERROR: could not read the database port at ${PORT_PARAMETER}." >&2
    echo "       ${DATABASE_PORT}" >&2
    echo "       The platform team publishes each engine's port there once the engine is registered." >&2
    exit 1
  fi

  VALUES[DATABASE_PORT]="${DATABASE_PORT}"
  ORDER+=(DATABASE_ENGINE DATABASE_HOST DATABASE_PORT)
fi

for key in "${ORDER[@]}"; do
  value="${VALUES[${key}]}"

  [[ -n "${value}" ]] || { echo "ERROR: ${NAME} has no value for ${key}." >&2; exit 1; }
  [[ "${value}" =~ ^[A-Za-z0-9:/._@+=,-]+$ ]] || { echo "ERROR: the value for ${key} contains characters that are not allowed." >&2; exit 1; }
done

[[ "${VALUES[SERVICE_PORT]}" =~ ^[0-9]+$ ]] || { echo "ERROR: port '${VALUES[SERVICE_PORT]}' is not a number." >&2; exit 1; }
# The prefix must be this service's own directory: <tier>/<service> on a shared
# fleet, services/<service> on dedicated hosts. Anything else would publish into
# another service's directory.
if [[ "${HOSTING}" == "dedicated" ]]; then
  [[ "${VALUES[DEPLOY_PREFIX]}" == "services/${SERVICE}" ]] || { echo "ERROR: deploy prefix '${VALUES[DEPLOY_PREFIX]}' is not services/${SERVICE}." >&2; exit 1; }
else
  [[ "${VALUES[DEPLOY_PREFIX]}" =~ ^(private|internal)/${SERVICE}$ ]] || { echo "ERROR: deploy prefix '${VALUES[DEPLOY_PREFIX]}' is not <tier>/${SERVICE}." >&2; exit 1; }
fi
[[ "${VALUES[STATIC_PREFIX]}" =~ ^static/[a-z0-9-]+$ ]] || { echo "ERROR: static prefix '${VALUES[STATIC_PREFIX]}' is not static/<service>." >&2; exit 1; }
[[ -z "${DATABASE_ENGINE}" || "${VALUES[DATABASE_PORT]}" =~ ^[0-9]+$ ]] || { echo "ERROR: the database port '${VALUES[DATABASE_PORT]:-}' is not a number." >&2; exit 1; }

for key in "${ORDER[@]}"; do
  echo "${key}=${VALUES[${key}]}"
done
