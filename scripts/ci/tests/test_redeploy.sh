#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="${SCRIPTS}/redeploy.sh"
export FAKE_LOG="${WORK}/calls.log" REDEPLOY_INTERVAL=0 REDEPLOY_TIMEOUT=30 REDEPLOY_EMPTY_GRACE=30

seq_dir(){ rm -rf "${WORK}/inv"; mkdir -p "${WORK}/inv"; export FAKE_INVOCATIONS_DIR="${WORK}/inv"; : > "${FAKE_LOG}"; }
inv(){ printf '%s' "$2" > "${WORK}/inv/$1.json"; }
run(){ bash "$R" acme-fleet-update acme private eu-west-1 v1.2.0; }
OK='[{"id":"i-1","status":"Success","detail":"Success","out":"pulled\nstarted"},{"id":"i-2","status":"Success","detail":"Success","out":"pulled\nstarted"}]'

echo "== redeploy.sh"
seq_dir; inv 1 "$OK"
out="$(run 2>&1)"; rc=$?
check "all hosts succeed -> success"                    test $rc -eq 0
check "sends the fleet-update document and nothing else" bash -c "grep -c 'ssm send-command' '${FAKE_LOG}' | grep -qx 1 && grep -q -- '--document-name acme-fleet-update' '${FAKE_LOG}'"
check "targets only this project's hosts on this tier"  grep -q -- '--targets Key=tag:Project,Values=acme Key=tag:Service,Values=private' "${FAKE_LOG}"
check "the jitter is zero for a CI deploy"              grep -q -- '--parameters jitterSeconds=0' "${FAKE_LOG}"
check "never uses AWS-RunShellScript"                   bash -c "! grep -q 'RunShellScript' '${FAKE_LOG}'"
check "each host's status and output are shown"         bash -c "grep -q -- '--- i-1: Success' <<< \"$out\" && grep -q 'started' <<< \"$out\""

seq_dir; inv 1 '[{"id":"i-1","status":"InProgress","detail":"InProgress","out":""},{"id":"i-2","status":"Pending","detail":"Pending","out":""}]'; inv 2 "$OK"
run >/dev/null 2>&1
check "waits while hosts are still working, then succeeds" test $? -eq 0
check "it polled more than once"                        bash -c "[ \"\$(grep -c 'list-command-invocations' '${FAKE_LOG}')\" -ge 2 ]"

seq_dir; inv 1 '[{"id":"i-1","status":"Success","detail":"Success","out":"ok"},{"id":"i-2","status":"Failed","detail":"Failed","out":"pull access denied"}]'
out="$(run 2>&1)"; rc=$?
check "ONE failed host fails the deploy"                test $rc -ne 0
check "the failure output is shown"                     bash -c "grep -q 'pull access denied' <<< \"$out\""
check "the message counts the failures"                 bash -c "grep -q '1 of 2 host' <<< \"$out\""

seq_dir; inv 1 '[{"id":"i-1","status":"TimedOut","detail":"TimedOut","out":""}]'
check "a timed-out host fails the deploy"               bash -c "! bash '$R' acme-fleet-update acme private eu-west-1 v1.0.0 >/dev/null 2>&1"
seq_dir; inv 1 '[{"id":"i-1","status":"Cancelled","detail":"Cancelled","out":""}]'
check "a cancelled host fails the deploy"               bash -c "! bash '$R' acme-fleet-update acme private eu-west-1 v1.0.0 >/dev/null 2>&1"

seq_dir; inv 1 '[]'
check "no host answering fails (after the grace period)" bash -c "! REDEPLOY_EMPTY_GRACE=1 REDEPLOY_INTERVAL=1 bash '$R' acme-fleet-update acme private eu-west-1 v1.0.0 >/dev/null 2>&1"
seq_dir; inv 1 '[]'; inv 2 "$OK"
check "hosts that appear after a moment are accepted"   bash -c "REDEPLOY_EMPTY_GRACE=30 bash '$R' acme-fleet-update acme private eu-west-1 v1.0.0 >/dev/null 2>&1"
seq_dir; inv 1 '[{"id":"i-1","status":"InProgress","detail":"InProgress","out":""}]'
check "hosts that never finish fail after the timeout"  bash -c "! REDEPLOY_TIMEOUT=1 REDEPLOY_INTERVAL=1 bash '$R' acme-fleet-update acme private eu-west-1 v1.0.0 >/dev/null 2>&1"

seq_dir; inv 1 "$OK"
check "a send failure is reported"                      bash -c "! FAKE_SEND_FAIL=1 bash '$R' acme-fleet-update acme private eu-west-1 v1.0.0 >/dev/null 2>&1"
check "a Service tag that is not a name is refused"    bash -c "! bash '$R' acme-fleet-update acme 'Bad Tag' eu-west-1 v1.0.0 >/dev/null 2>&1"
seq_dir; inv 1 "$OK"
bash "$R" acme-auth-update acme auth eu-west-1 v1.2.0 >/dev/null 2>&1
check "dedicated: the service's own document, to its own hosts" bash -c "grep -q -- '--document-name acme-auth-update' '${FAKE_LOG}' && grep -q -- '--targets Key=tag:Project,Values=acme Key=tag:Service,Values=auth' '${FAKE_LOG}'"
check "a document name with a space is refused"         bash -c "! bash '$R' 'AWS RunShellScript' acme private eu-west-1 v1.0.0 >/dev/null 2>&1"
check "missing arguments are refused"                   bash -c "! bash '$R' acme-fleet-update >/dev/null 2>&1"
finish
