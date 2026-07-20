#!/usr/bin/env bash
# infra-validate-gate-verdict.sh — fail-closed verdict for the
# `infra-validate-required` aggregator gate job (#6766).
#
# Usage:
#   infra-validate-gate-verdict.sh <detect_result> <validate_result> \
#                                  <deploy_result> <directories> <suite_relevant>
#
#   detect/validate/deploy are GitHub Actions `needs.<job>.result`
#     (success | failure | cancelled | skipped | "").
#   directories    is `needs.detect-changes.outputs.directories`, a JSON array
#                  literal — `[]` when no terraform root changed.
#   suite_relevant is `needs.detect-changes.outputs.suite_relevant`, the
#                  literal string "true" or "false".
#
# WHY THIS IS A SCRIPT AND NOT INLINE YAML. The verdict this replaces was an
# inline step that opened with `if [[ "$DIRS" == "[]" ]]; then exit 0; fi`.
# `directories` enumerates TERRAFORM ROOTS ONLY, so a PR touching only
# .github/workflows/restart-inngest-server.yml gives directories='[]' — while
# suite_relevant='true', because deploy-script-tests runs cross-file drift
# guards over that file. A RED deploy-script-tests therefore produced a GREEN
# required check and the PR merged. That is precisely the failure #6766 names:
# a check that certifies a different property than the one it names. Extracted
# here so the verdict is unit-tested by
# tests/scripts/test-infra-validate-gate-verdict.sh rather than asserted by
# grepping the workflow for a string — a string can sit in unreachable code
# after an early `exit 0` and satisfy the grep.
#
# ALLOW-LIST. Exit 0 ONLY on the three enumerated rows below. Everything else
# — `cancelled`, a `skipped` the table does not enumerate, an empty string, an
# impossible axis combination, or a future GitHub-added result state — exits 1.
#
#   | detect  | directories | suite_relevant | validate | deploy  | verdict |
#   |---------|-------------|----------------|----------|---------|---------|
#   | success | []          | false          | skipped  | skipped | 0 — nothing in scope
#   | success | []          | true           | skipped  | success | 0 — non-terraform guard surface only
#   | success | non-[]      | true           | success  | success | 0 — full pass
#   | success | any         | true           | any      | failure | 1 — the defect above
#   | success | non-[]      | any            | ≠success | any     | 1
#   | ≠success| any         | any            | any      | any     | 1 — detect itself failed
#
# The final row is load-bearing beyond its obvious purpose, and is inherited
# from the scripts/tenant-integration-gate-verdict.sh precedent: on a
# `merge_group` event github.base_ref is empty, so if detect-changes' routing
# is ever regressed it runs `git diff origin/...HEAD`, dies, and reports
# `failure`. This row is what makes that fail LOUDLY instead of passing green
# — a second, independent defence for the merge_group routing.
set -uo pipefail

detect="${1:-}"
validate="${2:-}"
deploy="${3:-}"
dirs="${4:-}"
relevant="${5:-}"

_pass() {
  printf 'infra-validate gate: PASS — %s (detect=%s validate=%s deploy-script-tests=%s directories=%s suite_relevant=%s)\n' \
    "$1" "$detect" "$validate" "$deploy" "$dirs" "$relevant"
  exit 0
}

# `directories` must be a JSON array literal. An empty string is NOT "no
# terraform roots" — it is a detect-changes step that never wrote its output,
# and treating it as non-empty (it is `!= "[]"`, after all) would send it down
# the full-pass row.
dirs_empty=false
dirs_wellformed=false
case "$dirs" in
  "[]")  dirs_empty=true;  dirs_wellformed=true ;;
  "["*"]") dirs_wellformed=true ;;
esac

if [[ "$detect" == "success" && "$dirs_wellformed" == "true" ]]; then
  # Row 1 — nothing in scope. Docs-only PR, or a merge_group candidate (whose
  # routing emits directories='[]' + suite_relevant=false by construction).
  if [[ "$dirs_empty" == "true" && "$relevant" == "false" \
        && "$validate" == "skipped" && "$deploy" == "skipped" ]]; then
    _pass "nothing in scope"
  fi

  # Row 2 — non-terraform guard surface only. No terraform root changed, so the
  # validate matrix correctly fanned to zero, but the cross-file drift guards
  # were in scope and had to come back green.
  if [[ "$dirs_empty" == "true" && "$relevant" == "true" \
        && "$validate" == "skipped" && "$deploy" == "success" ]]; then
    _pass "non-terraform guard surface only, deploy-script-tests green"
  fi

  # Row 3 — full pass. Terraform roots changed and both suites succeeded.
  if [[ "$dirs_empty" == "false" && "$relevant" == "true" \
        && "$validate" == "success" && "$deploy" == "success" ]]; then
    _pass "terraform roots validated and deploy-script-tests green"
  fi
fi

printf '::error::infra-validate gate FAILED closed (detect-changes=%s, validate=%s, deploy-script-tests=%s, directories=%s, suite_relevant=%s). The required check passes only on an enumerated state: nothing-in-scope, guard-surface-only with deploy-script-tests=success, or terraform-roots-changed with validate=success AND deploy-script-tests=success.\n' \
  "${detect:-<empty>}" "${validate:-<empty>}" "${deploy:-<empty>}" \
  "${dirs:-<empty>}" "${relevant:-<empty>}" >&2
exit 1
