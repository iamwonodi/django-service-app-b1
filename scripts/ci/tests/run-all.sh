#!/usr/bin/env bash
# Offline tests for the deploy pipeline's scripts (needs bash, git, jq; aws, docker and gh are faked).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
failed=0
for suite in test_settings.sh test_service_config.sh test_render.sh test_publish_static.sh test_pipeline.sh test_redeploy.sh test_promotion.sh test_tags_images.sh test_setup.sh; do
  echo "################ ${suite}"
  bash "./${suite}" || failed=1
done
[[ ${failed} -eq 0 ]] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
