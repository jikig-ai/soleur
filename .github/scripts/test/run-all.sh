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
RAN=0

# Minimum-suite floor (#7068). Without it the glob is silently de-existable: delete or rename
# a suite out of `test-*.sh` and this script prints "ALL FIXTURE TESTS PASS" over a smaller
# set, with nothing anywhere asserting the membership. That is the same silent-and-green shape
# the suites here exist to catch, applied to their own runner -- and
# test-infra-suite-registration.sh already carries this exact discipline for ITS input while
# this runner carried none for its own.
#
# A FLOOR, not equality: the count is developer-incremented, so `-eq` would turn every added
# suite into a spurious failure. Derived from a green run (10 suites, 2026-07-30). Raise it
# when suites are added; lower it deliberately, with a reason.
MIN_SUITES=10

for t in "$DIR"/test-*.sh; do
  [[ -e "$t" ]] || continue
  RAN=$((RAN + 1))
  echo "=== $(basename "$t") ==="
  if ! bash "$t"; then
    FAIL=1
  fi
  echo ""
done

if (( RAN < MIN_SUITES )); then
  echo "::error::run-all: ran only $RAN fixture suite(s), expected >= $MIN_SUITES."
  echo "         A suite was deleted or renamed out of the test-*.sh glob. If that was"
  echo "         deliberate, lower MIN_SUITES in the same commit and say why."
  FAIL=1
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL FIXTURE TESTS PASS"
else
  echo "ONE OR MORE FIXTURE TESTS FAILED"
  exit 1
fi
