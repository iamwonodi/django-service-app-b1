#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
C="${SCRIPTS}/check-commit-messages.sh"
R="${WORK}/repo"; git init -q "$R"; git -C "$R" config user.email t@example.org; git -C "$R" config user.name t
commit(){ git -C "$R" commit -q --allow-empty -m "$1"; }
commit "chore: start"; BASE="$(git -C "$R" rev-parse HEAD)"
runc(){ (cd "$R" && bash "$C" "$BASE" HEAD "$@") > "${WORK}/out.txt" 2>&1; }

echo "== check-commit-messages.sh"
commit "feat: add the orders page"; commit "fix(auth): keep the session on refresh"; commit "docs: explain the deploy"
runc "feat: orders"; rc=$?
check "well-formed commits and title pass"            test $rc -eq 0
commit "Merge branch 'main' into feature"; commit 'Revert "feat: add the orders page"'
runc; check "merges and Git's reverts are accepted"   test $? -eq 0
commit "feat!: drop the old API"
runc; check "a breaking marker is accepted"            test $? -eq 0
commit "Fix login"
runc; rc=$?
check "a message without a type is refused"           test $rc -ne 0
check "and names the commit"                          grep -q "Fix login" "${WORK}/out.txt"
BASE="$(git -C "$R" rev-parse HEAD)"; commit "feat: fine"
runc "Update stuff"; rc=$?
check "a pull request title without a type is refused" bash -c "[ $rc -ne 0 ] && grep -q \"title\" '${WORK}/out.txt'"
BASE="$(git -C "$R" rev-parse HEAD)"; commit "feature: not a type"
runc; check "an unknown type is refused"               test $? -ne 0
BASE="$(git -C "$R" rev-parse HEAD)"; commit "feat:no space"
runc; check "a missing space after the colon is refused" test $? -ne 0
finish
