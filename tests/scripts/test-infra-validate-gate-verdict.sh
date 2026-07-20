#!/usr/bin/env bash
# Tests for scripts/infra-validate-gate-verdict.sh — the fail-closed verdict
# for the `infra-validate-required` aggregator gate job (#6766).
#
# Modelled on tests/scripts/test-tenant-integration-gate-verdict.sh (the
# in-repo precedent for a unit-tested, fail-closed aggregator verdict).
#
# WHY THIS SUITE EXISTS. The verdict it guards used to be inline workflow YAML
# that opened with:
#
#     if [[ "$DIRS" == "[]" ]]; then echo "nothing to validate"; exit 0; fi
#
# A PR touching ONLY .github/workflows/restart-inngest-server.yml yields
# directories='[]' (it is not a terraform root) but suite_relevant='true' (the
# cross-file drift guards in deploy-script-tests read it). With the early
# `exit 0`, a RED deploy-script-tests produced a GREEN required check and the
# PR merged. That is the exact defect #6766 exists to name — a guard that
# certifies a different property than the one it names — and T14 below is its
# dedicated control. Any refactor that reintroduces an early return keyed on
# `directories` alone must turn T14 red.
#
# Allow-list semantics: the script exits 0 ONLY on the three enumerated PASS
# rows; every other combination — including `cancelled`, a `skipped` where the
# table does not enumerate it, an empty string, or a future GitHub-added result
# state — fails closed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/infra-validate-gate-verdict.sh"
pass=0; fail=0

if [[ ! -f "$SCRIPT" ]]; then
  echo "[FAIL] $SCRIPT does not exist" >&2
  exit 1
fi

# _expect <expected-rc> <detect> <validate> <deploy> <dirs> <suite_relevant> <label>
_expect() {
  local want="$1" detect="$2" validate="$3" deploy="$4" dirs="$5" relevant="$6" label="$7" got
  if bash "$SCRIPT" "$detect" "$validate" "$deploy" "$dirs" "$relevant" >/dev/null 2>&1; then
    got=0
  else
    got=1
  fi
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label (detect=$detect validate=$validate deploy=$deploy dirs=$dirs relevant=$relevant -> rc=$got)"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label: want rc=$want got rc=$got (detect=$detect validate=$validate deploy=$deploy dirs=$dirs relevant=$relevant)" >&2
  fi
}

DIRS_SOME='["apps/web-platform/infra","infra/github"]'

echo "=== infra-validate-gate-verdict: PASS rows (the allow-list) ==="

# Row 1 — nothing in scope. Docs-only PR, and the merge_group route (which
# emits directories='[]' + suite_relevant=false by construction).
_expect 0 success skipped skipped '[]' false \
  "T13: nothing in scope (docs-only PR / merge_group) -> PASS"

# Row 2 — non-terraform guard surface only. THE case #6766 is about: a PR
# touching only restart-inngest-server.yml. No terraform root changed, but the
# cross-file drift guards must run and must be green.
_expect 0 success skipped success '[]' true \
  "T13b: non-terraform guard surface only, deploy green -> PASS"

# Row 3 — full pass: terraform roots changed, both suites green.
_expect 0 success success success "$DIRS_SOME" true \
  "T16: terraform roots changed, validate+deploy green -> PASS"

echo ""
echo "=== infra-validate-gate-verdict: FAIL rows (fail-closed) ==="

# ---- T14: THE F1 DEFECT CONTROL. This is the single most important row in
# this suite. directories='[]' so the old inline gate returned 0 before ever
# looking at deploy-script-tests; suite_relevant='true' so the drift guards
# were in scope; deploy=failure so they were RED. Green here = #6766 shipped
# again. Asserted on BOTH deploy=failure and deploy=cancelled so a fix that
# only special-cases the literal string "failure" still reds.
_expect 1 success skipped failure '[]' true \
  "T14: dirs=[] suite_relevant=true deploy=failure -> FAIL (the F1 defect)"
_expect 1 success skipped cancelled '[]' true \
  "T14b: dirs=[] suite_relevant=true deploy=cancelled -> FAIL"
_expect 1 success skipped skipped '[]' true \
  "T14c: dirs=[] suite_relevant=true but deploy never ran -> FAIL (gated job vanished)"

# deploy=failure must red regardless of the directories axis.
_expect 1 success success failure "$DIRS_SOME" true \
  "T14d: terraform roots changed, validate green, deploy red -> FAIL"

# ---- T15: validate red while terraform roots changed.
_expect 1 success failure success "$DIRS_SOME" true \
  "T15: dirs non-empty, validate=failure -> FAIL"
_expect 1 success cancelled success "$DIRS_SOME" true \
  "T15b: dirs non-empty, validate=cancelled -> FAIL"
_expect 1 success skipped success "$DIRS_SOME" true \
  "T15c: dirs non-empty but validate skipped -> FAIL (matrix silently fanned to zero)"

# ---- T17: unenumerated / malformed states fail closed.
_expect 1 success bogus_future_state success "$DIRS_SOME" true \
  "T17: unknown validate state -> FAIL (allow-list)"
_expect 1 success success bogus_future_state "$DIRS_SOME" true \
  "T17b: unknown deploy state -> FAIL (allow-list)"
_expect 1 success skipped skipped '[]' maybe \
  "T17c: suite_relevant is neither true nor false -> FAIL"
_expect 1 success skipped skipped '' false \
  "T17d: empty directories string -> FAIL (not the literal [])"
_expect 1 success success success '' true \
  "T17e: empty directories with green suites -> FAIL (must not read as non-empty)"
_expect 1 success skipped skipped '[]' '' \
  "T17f: empty suite_relevant -> FAIL"
_expect 1 '' '' '' '' '' \
  "T17g: all args empty -> FAIL"

# ---- detect ≠ success. Load-bearing and inherited from the precedent: it is
# what makes an UNROUTED merge_group (F3) fail loudly rather than pass green.
# On merge_group, github.base_ref is empty, so an unrouted detect-changes runs
# `git diff origin/...HEAD`, which is fatal -> detect-changes=failure. Without
# this row the aggregator would green every merge-queue candidate.
_expect 1 failure skipped skipped '[]' false \
  "T-detect1: detect-changes failed (unrouted merge_group) -> FAIL"
_expect 1 failure success success "$DIRS_SOME" true \
  "T-detect2: detect-changes failed but both suites green -> FAIL closed"
_expect 1 cancelled skipped skipped '[]' false \
  "T-detect3: detect-changes cancelled -> FAIL"
_expect 1 skipped skipped skipped '[]' false \
  "T-detect4: detect-changes skipped -> FAIL"

# ---- Cross-axis: suite_relevant=false must not license a non-empty matrix.
# Only merge_group emits suite_relevant=false, and it emits directories='[]'
# alongside. dirs non-empty + relevant=false is an impossible state, so it
# fails closed rather than being silently accepted.
_expect 1 success success success "$DIRS_SOME" false \
  "T-cross1: dirs non-empty with suite_relevant=false is unreachable -> FAIL"

echo ""
echo "=== infra-validate-gate-verdict: diagnostics ==="

# Fail-closed DIAGNOSTIC, not just the exit code: CI surfaces the failure via
# the ::error:: annotation, and a regression that drops it would still exit 1
# but go silent in the checks UI.
#
# Captured into a variable rather than piped: under `set -o pipefail` a
# `producer | grep -q` can early-match, SIGPIPE the producer (141) and flake to
# a false negative. `grep -Eq <<<"$var"` has no pipe to poison.
err_out=$(bash "$SCRIPT" success skipped failure '[]' true 2>&1 >/dev/null) || true
if grep -Eq '::error::' <<<"$err_out"; then
  pass=$((pass + 1)); echo "[ok] fail-closed emits ::error:: diagnostic on stderr"
else
  fail=$((fail + 1)); echo "[FAIL] fail-closed path did not emit ::error:: on stderr" >&2
fi

# The diagnostic must name the offending axis, not just say "failed". An
# operator reading the checks UI has to know WHICH input reds the gate.
if grep -Eq 'deploy-script-tests=failure' <<<"$err_out"; then
  pass=$((pass + 1)); echo "[ok] diagnostic names the failing input (deploy-script-tests=failure)"
else
  fail=$((fail + 1)); echo "[FAIL] diagnostic does not name the failing input: $err_out" >&2
fi

# The PASS path must announce itself on stdout so a green run is auditable.
ok_out=$(bash "$SCRIPT" success success success "$DIRS_SOME" true 2>/dev/null)
if grep -Eq 'PASS' <<<"$ok_out"; then
  pass=$((pass + 1)); echo "[ok] pass path prints a PASS line on stdout"
else
  fail=$((fail + 1)); echo "[FAIL] pass path printed no PASS line: $ok_out" >&2
fi

echo ""
echo "=== infra-validate-gate-verdict: workflow wiring ==="

# The script is worthless if the workflow does not call it. Anchor on the call
# SHAPE (`bash …/infra-validate-gate-verdict.sh` with five quoted args), not a
# bare filename token that a comment mentioning the script would also match.
WF="$REPO_ROOT/.github/workflows/infra-validation.yml"
wf_body=$(cat "$WF")
if grep -Eq 'bash[[:space:]]+(\$\{?GITHUB_WORKSPACE\}?/)?scripts/infra-validate-gate-verdict\.sh([[:space:]]+"\$[A-Z_]+"){5}' <<<"$wf_body"; then
  pass=$((pass + 1)); echo "[ok] infra-validation.yml invokes the verdict script with 5 args"
else
  fail=$((fail + 1)); echo "[FAIL] infra-validation.yml does not invoke the verdict script with 5 quoted args" >&2
fi

# The early-return that WAS the defect must be gone. `$DIRS == "[]"` followed
# by `exit 0` in the aggregator is the literal F1 shape.
#
# Comment lines are stripped FIRST. The aggregator's own comment quotes the
# defect verbatim to explain why the verdict was extracted, and a bare token
# match would red on that documentation — a guard that fires on the description
# of the bug instead of the bug is the same class of error this suite exists to
# catch. Anchor on executable syntax only.
wf_code=$(grep -vE '^[[:space:]]*#' <<<"$wf_body")
# shellcheck disable=SC2016  # single quotes are intentional — the pattern must match the LITERAL text "$DIRS" in the workflow, not this shell's expansion of it
if grep -Eq '\$DIRS"?[[:space:]]*==[[:space:]]*"\[\]"' <<<"$wf_code"; then
  fail=$((fail + 1)); echo "[FAIL] infra-validation.yml still branches on \$DIRS == \"[]\" (the F1 early-return)" >&2
else
  pass=$((pass + 1)); echo "[ok] the \$DIRS == \"[]\" early-return is gone from the workflow"
fi

# The aggregator must actually depend on deploy-script-tests — otherwise
# needs.deploy-script-tests.result is the empty string and every run reds
# (or, worse, a future edit defaults it to something benign).
if grep -Eq '^[[:space:]]*needs:[[:space:]]*\[[^]]*deploy-script-tests[^]]*\]' <<<"$wf_body"; then
  pass=$((pass + 1)); echo "[ok] an aggregator needs: list includes deploy-script-tests"
else
  fail=$((fail + 1)); echo "[FAIL] no needs: list includes deploy-script-tests" >&2
fi

echo "---"
echo "infra-validate-gate-verdict: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
