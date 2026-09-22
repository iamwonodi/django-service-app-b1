#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# REDEPLOY A TIER'S HOSTS, AND WAIT FOR THE RESULT
#
# Sends the update document -- and nothing else -- to the hosts tagged with this
# project and the given Service tag, then follows the command until every host
# has finished. On a shared fleet the tag is the tier and the document is core's
# fleet-update; on dedicated hosts the tag is the service and the document is the
# service's own. Core's policy allows exactly that pair and nothing wider.
#
# The earlier pipeline fired the command and moved on, so a host that failed to pull
# the image, or refused the compose file, left the workflow green and the service on
# the old release. This exits non-zero if ANY host does not report Success, if no host
# answers at all, or if the hosts are still busy after the timeout.
#
# jitterSeconds is 0: a CI deploy should not wait. (Secret rotation, which restarts a
# whole tier, spreads its restarts out with a jitter of its own.)
#
# Usage: redeploy.sh <document> <project> <service-tag> <aws-region> <release-tag>
#
# Environment (all optional):
#   REDEPLOY_INTERVAL     seconds between checks                           (default 5)
#   REDEPLOY_TIMEOUT      seconds to wait for every host to finish         (default 900)
#   REDEPLOY_EMPTY_GRACE  seconds to wait for a first host to appear       (default 60)
# ==============================================================================

DOCUMENT="${1:?Usage: redeploy.sh <document> <project> <tier> <aws-region> <tag>}"
PROJECT="${2:?project is required}"
TIER="${3:?tier is required}"
REGION="${4:?aws-region is required}"
TAG="${5:?tag is required}"

INTERVAL="${REDEPLOY_INTERVAL:-5}"
TIMEOUT="${REDEPLOY_TIMEOUT:-900}"
EMPTY_GRACE="${REDEPLOY_EMPTY_GRACE:-60}"

# The Service tag the target hosts carry: a tier on a shared fleet, the service's
# own name on dedicated hosts.
[[ "${TIER}" =~ ^[a-z][a-z0-9-]{1,20}[a-z0-9]$ ]] || { echo "ERROR: '${TIER}' is not a Service tag value." >&2; exit 1; }
[[ "${DOCUMENT}" =~ ^[A-Za-z0-9_.-]{3,128}$ ]] || { echo "ERROR: '${DOCUMENT}' is not a document name." >&2; exit 1; }

echo "Sending ${DOCUMENT} to hosts tagged Project=${PROJECT}, Service=${TIER} (deploying ${TAG})."

if ! COMMAND_ID="$(aws ssm send-command \
    --document-name "${DOCUMENT}" \
    --targets "Key=tag:Project,Values=${PROJECT}" "Key=tag:Service,Values=${TIER}" \
    --parameters "jitterSeconds=0" \
    --comment "Deploy ${TAG}" \
    --query "Command.CommandId" --output text \
    --region "${REGION}" 2>&1)"; then
  echo "ERROR: could not send the command: ${COMMAND_ID}" >&2
  exit 1
fi

echo "Command ${COMMAND_ID} sent. Waiting for the hosts."

START="${SECONDS}"

while true; do

  INVOCATIONS="$(aws ssm list-command-invocations \
    --command-id "${COMMAND_ID}" --details \
    --query "CommandInvocations[].{id:InstanceId,status:Status,detail:StatusDetails,out:CommandPlugins[0].Output}" \
    --output json --region "${REGION}")"

  COUNT="$(jq 'length' <<< "${INVOCATIONS}")"
  ELAPSED=$(( SECONDS - START ))

  if [[ "${COUNT}" -eq 0 ]]; then
    if [[ ${ELAPSED} -ge ${EMPTY_GRACE} ]]; then
      echo "ERROR: no host answered. Do any running hosts carry the tags Project=${PROJECT} and Service=${TIER}?" >&2
      exit 1
    fi
  else
    BUSY="$(jq '[.[] | select(.status == "Pending" or .status == "InProgress" or .status == "Delayed")] | length' <<< "${INVOCATIONS}")"

    if [[ "${BUSY}" -eq 0 ]]; then
      break
    fi

    echo "  ${BUSY} of ${COUNT} host(s) still working (${ELAPSED}s)."
  fi

  if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
    echo "ERROR: the hosts were still working after ${TIMEOUT}s; giving up waiting." >&2
    exit 1
  fi

  sleep "${INTERVAL}"

done

FAILED=0

while IFS= read -r invocation; do
  ID="$(jq -r '.id' <<< "${invocation}")"
  STATUS="$(jq -r '.status' <<< "${invocation}")"

  echo
  echo "--- ${ID}: ${STATUS}"
  jq -r '.out // "" | split("\n") | .[-25:] | .[]' <<< "${invocation}" | sed 's/^/    /'

  [[ "${STATUS}" == "Success" ]] || FAILED=$(( FAILED + 1 ))
done < <(jq -c '.[]' <<< "${INVOCATIONS}")

echo

if [[ ${FAILED} -gt 0 ]]; then
  echo "ERROR: ${FAILED} of ${COUNT} host(s) did not deploy ${TAG} successfully." >&2
  exit 1
fi

echo "All ${COUNT} host(s) deployed ${TAG}."
