#!/usr/bin/env bash
# Run all .github/scripts/ fixture tests sequentially. Exits non-zero on
# first failure. Run from repo root via `bash .github/scripts/test/run-all.sh`.
#
# CONTRACT (#6454): the `test-*.sh` glob below feeds `guard-script-fixture-tests`,
# which is a REQUIRED check, runs on `merge_group`, and has NO path filter — so it
# gates every PR in the repo. Suites here must therefore be BASH-ONLY: no terraform,
# no cloud-init, no apt. A suite needing external tooling would either red every PR
# (the tool is absent on that bare runner) or put a package-mirror dependency on the
# merge-queue critical path for docs-only PRs.
#
# That is why `fixtures-validate-infra-templates.sh` sits in this directory but is
# deliberately NOT named `test-*`: it needs terraform + cloud-init, so it runs from
# the `deploy-script-tests` job in infra-validation.yml, which installs both. Do not
# rename it back into this glob.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
FAIL=0

for t in "$DIR"/test-*.sh; do
  echo "=== $(basename "$t") ==="
  if ! bash "$t"; then
    FAIL=1
  fi
  echo ""
done

if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL FIXTURE TESTS PASS"
else
  echo "ONE OR MORE FIXTURE TESTS FAILED"
  exit 1
fi
