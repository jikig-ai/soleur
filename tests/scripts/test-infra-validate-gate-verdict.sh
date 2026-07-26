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

# COMMENT LINES ARE STRIPPED ONCE, HERE, AND EVERY WORKFLOW GREP BELOW READS
# wf_code — never wf_body. The aggregator's own comments quote the defects these
# assertions exist to catch VERBATIM (the `$DIRS == "[]"` early-return, the
# script filename, the needs: wiring), so a grep over the raw body is satisfied
# by the DOCUMENTATION of the defect even after the executable code has been
# deleted. Measured: replacing the verdict invocation with `echo "gate
# disabled"` left this suite fully green, because the comment above the step
# names the script. A guard that fires on the description of the bug instead of
# the bug is the same defect class this suite exists to catch — anchor on
# executable syntax only.
wf_code=$(grep -vE '^[[:space:]]*#' <<<"$wf_body")

if grep -Eq 'bash[[:space:]]+(\$\{?GITHUB_WORKSPACE\}?/)?scripts/infra-validate-gate-verdict\.sh([[:space:]]+"\$[A-Z_]+"){5}' <<<"$wf_code"; then
  pass=$((pass + 1)); echo "[ok] infra-validation.yml invokes the verdict script with 5 args"
else
  fail=$((fail + 1)); echo "[FAIL] infra-validation.yml does not invoke the verdict script with 5 quoted args" >&2
fi

# ---------------------------------------------------------------------------
# THE GATE'S WIRING, NOT JUST ITS LOGIC.
#
# Everything above this point pins what the verdict script DECIDES. Nothing
# above it pins what the workflow FEEDS it — and a gate wired to the wrong
# inputs is #6766 verbatim regardless of how correct its logic is.
#
# Measured: changing exactly one token, `DEPLOY: ${{ needs.deploy-script-tests
# .result }}` -> `${{ needs.validate.result }}`, left BOTH suites fully green
# (verdict 28/0, detect 41/0). The `needs:` list still named deploy-script-tests
# and the call shape was untouched, so every existing assertion held — while in
# real CI (terraform roots changed, validate green, deploy-script-tests RED) the
# gate exited 0 and certified a red suite as green. T14d pins that state's
# VERDICT; it cannot see that DEPLOY no longer carries deploy-script-tests.
#
# The call-shape regex above is deliberately order-blind (`("\$[A-Z_]+"){5}`),
# so swapping two positional args also survived it. Both axes are pinned below:
# each env name against the exact expression it must bind, and the five
# positionals against the script's documented order.
#
# Scoped to the `infra-validate-required` job block so a same-named env binding
# in some other job cannot satisfy these.
agg_job=$(awk '/^  infra-validate-required:$/{f=1} f&&/^  [a-z][a-z0-9-]*:$/&&!/^  infra-validate-required:$/{exit} f' <<<"$wf_code")

if [[ -z "$agg_job" ]]; then
  fail=$((fail + 1)); echo "[FAIL] could not locate the infra-validate-required job block in the workflow" >&2
else
  pass=$((pass + 1)); echo "[ok] located the infra-validate-required job block"

  # F3 — `if: always()`. Without it the job SKIPS whenever any `needs` job
  # fails, which is EXACTLY when the fail-closed verdict has to run: the
  # required context then never reports failure and the PR is merge-eligible on
  # a red suite. Deleting the line left both suites green before this assertion.
  if grep -Eq '^[[:space:]]+if:[[:space:]]*always\(\)[[:space:]]*$' <<<"$agg_job"; then
    pass=$((pass + 1)); echo "[ok] infra-validate-required declares if: always()"
  else
    fail=$((fail + 1)); echo "[FAIL] infra-validate-required has no 'if: always()' — it will skip when a needs: job fails" >&2
  fi

  # F2a — each env name binds to the ONE expression it must carry.
  while IFS='|' read -r env_name expr; do
    # `expr` is a regex (dots escaped); strip the backslashes for the message so
    # an operator reading the checks UI sees the expression, not the pattern.
    expr_display="${expr//\\/}"
    if grep -Eq "^[[:space:]]+${env_name}:[[:space:]]*\\\$\{\{[[:space:]]*${expr}[[:space:]]*\}\}[[:space:]]*$" <<<"$agg_job"; then
      pass=$((pass + 1)); echo "[ok] ${env_name} binds \${{ ${expr_display} }}"
    else
      fail=$((fail + 1)); echo "[FAIL] ${env_name} does not bind \${{ ${expr_display} }} in infra-validate-required" >&2
    fi
  done <<'BINDINGS'
DETECT|needs\.detect-changes\.result
VALIDATE|needs\.validate\.result
DEPLOY|needs\.deploy-script-tests\.result
DIRS|needs\.detect-changes\.outputs\.directories
SUITE_RELEVANT|needs\.detect-changes\.outputs\.suite_relevant
BINDINGS

  # F2b — the five positionals in the script's DOCUMENTED order:
  #   <detect> <validate> <deploy> <directories> <suite_relevant>
  # (see the Usage block in scripts/infra-validate-gate-verdict.sh). Swapping
  # any two survives the order-blind call-shape regex above while silently
  # re-pointing every row of the verdict table at the wrong axis.
  # shellcheck disable=SC2016  # single quotes intentional — match the LITERAL "$DETECT" etc. text in the workflow, not this shell's expansion
  if grep -Eq 'bash[[:space:]]+(\$\{?GITHUB_WORKSPACE\}?/)?scripts/infra-validate-gate-verdict\.sh[[:space:]]+"\$DETECT"[[:space:]]+"\$VALIDATE"[[:space:]]+"\$DEPLOY"[[:space:]]+"\$DIRS"[[:space:]]+"\$SUITE_RELEVANT"[[:space:]]*$' <<<"$agg_job"; then
    pass=$((pass + 1)); echo "[ok] the five positional args are passed in the script's documented order"
  else
    fail=$((fail + 1)); echo "[FAIL] verdict-script args are not in the documented order (detect validate deploy dirs suite_relevant)" >&2
  fi

  # F2c — SUITE_RELEVANT must come from detect-changes, never a literal. A
  # hardcoded 'false' routes every run to the nothing-in-scope PASS row.
  if grep -Eq "^[[:space:]]+SUITE_RELEVANT:[[:space:]]*'?(true|false)'?[[:space:]]*$" <<<"$agg_job"; then
    fail=$((fail + 1)); echo "[FAIL] SUITE_RELEVANT is hardcoded to a literal — the gate no longer reads detect-changes" >&2
  else
    pass=$((pass + 1)); echo "[ok] SUITE_RELEVANT is not hardcoded to a literal"
  fi
fi

# ---------------------------------------------------------------------------
# A RED MAIN MUST REACH AN OPERATOR (#6766, F4).
#
# The push-to-main trigger is worth nothing on its own: without a consumer, a
# red main is a red square nobody is looking at, which is #6766's complaint
# RELOCATED rather than fixed. No other workflow covers this one —
# post-merge-monitor.yml is scoped to workflow "CI" AND `[bot-fix]` commits, and
# main-health-monitor.yml re-runs scripts/test-all.sh, which explicitly excludes
# this workflow's heavy jobs. `notify-main-red` is the consumer; these
# assertions are what stop it being deleted as dead weight.
notify_job=$(awk '/^  notify-main-red:$/{f=1} f&&/^  [a-z][a-z0-9-]*:$/&&!/^  notify-main-red:$/{exit} f' <<<"$wf_code")

if [[ -z "$notify_job" ]]; then
  fail=$((fail + 1)); echo "[FAIL] no notify-main-red job — a red main reaches no operator" >&2
else
  pass=$((pass + 1)); echo "[ok] notify-main-red job exists"

  # Must fire on aggregator failure, and only for push-to-main.
  if grep -Eq "^[[:space:]]+if:[[:space:]]*failure\(\)[[:space:]]*&&[[:space:]]*github\.event_name[[:space:]]*==[[:space:]]*'push'[[:space:]]*$" <<<"$notify_job"; then
    pass=$((pass + 1)); echo "[ok] notify-main-red fires on failure() && push"
  else
    fail=$((fail + 1)); echo "[FAIL] notify-main-red is not gated on failure() && github.event_name == 'push'" >&2
  fi

  # It must depend on the aggregator, or failure() has nothing to observe.
  if grep -Eq '^[[:space:]]+needs:[[:space:]]*\[[^]]*infra-validate-required[^]]*\]' <<<"$notify_job"; then
    pass=$((pass + 1)); echo "[ok] notify-main-red needs infra-validate-required"
  else
    fail=$((fail + 1)); echo "[FAIL] notify-main-red does not need: infra-validate-required" >&2
  fi

  # Without issues: write the gh calls 403 and the job reds silently-uselessly.
  if grep -Eq '^[[:space:]]+issues:[[:space:]]*write[[:space:]]*$' <<<"$notify_job"; then
    pass=$((pass + 1)); echo "[ok] notify-main-red grants issues: write"
  else
    fail=$((fail + 1)); echo "[FAIL] notify-main-red does not grant issues: write" >&2
  fi

  # SHARED ISSUE IDENTITY with main-health-monitor.yml. Dedupe here is by label
  # and the auto-close lives in that workflow's `Close issue on success` step,
  # which selects by `ci/main-broken` alone. A renamed label would open a P1
  # that nothing ever closes — so the label set is load-bearing, not cosmetic.
  #
  # Scoped to the `gh issue create` invocation specifically. A job-wide grep is
  # satisfied by the `gh issue list --label "ci/main-broken"` dedupe query even
  # after the CREATE call has been relabelled — which is the same
  # assertion-matches-the-wrong-line failure this suite exists to prevent.
  create_call=$(awk '/gh issue create/{f=1} f' <<<"$notify_job")
  if [[ -z "$create_call" ]]; then
    fail=$((fail + 1)); echo "[FAIL] notify-main-red never calls gh issue create" >&2
  else
    for lbl in 'ci/main-broken' 'priority/p1-high'; do
      if grep -Eq -- "--label[[:space:]]+\"${lbl}\"" <<<"$create_call"; then
        pass=$((pass + 1)); echo "[ok] notify-main-red creates the issue with ${lbl}"
      else
        fail=$((fail + 1)); echo "[FAIL] gh issue create does not apply ${lbl} (breaks shared dedupe/auto-close)" >&2
      fi
    done
  fi

  # Dedupe before create, or every red push opens a duplicate P1. The dedupe
  # query must select on the SAME label the create call applies.
  if grep -Eq -- 'gh issue list' <<<"$notify_job" \
     && grep -Eq -- '--label "ci/main-broken"' <<<"$notify_job" \
     && grep -Eq -- 'gh issue comment' <<<"$notify_job"; then
    pass=$((pass + 1)); echo "[ok] notify-main-red dedupes onto the existing open ci/main-broken issue"
  else
    fail=$((fail + 1)); echo "[FAIL] notify-main-red does not dedupe on ci/main-broken (needs gh issue list --label + gh issue comment)" >&2
  fi

  # The auto-close counterpart must still exist in main-health-monitor.yml.
  # This assertion is what makes the shared identity a real contract rather
  # than a comment: if that step is ever dropped, these P1s become immortal.
  MHM="$REPO_ROOT/.github/workflows/main-health-monitor.yml"
  if [[ -f "$MHM" ]]; then
    mhm_code=$(grep -vE '^[[:space:]]*#' "$MHM")
    if grep -Eq 'gh issue close' <<<"$mhm_code" && grep -Eq -- '--label "ci/main-broken"' <<<"$mhm_code"; then
      pass=$((pass + 1)); echo "[ok] main-health-monitor.yml still auto-closes ci/main-broken"
    else
      fail=$((fail + 1)); echo "[FAIL] main-health-monitor.yml no longer auto-closes ci/main-broken — notify-main-red's P1s would never close" >&2
    fi
  else
    fail=$((fail + 1)); echo "[FAIL] main-health-monitor.yml is missing — the shared issue lifecycle is broken" >&2
  fi
fi

# The early-return that WAS the defect must be gone. `$DIRS == "[]"` followed
# by `exit 0` in the aggregator is the literal F1 shape. Reads wf_code (see the
# stripping rationale above) so the aggregator's own comment, which quotes the
# defect verbatim, cannot invert this into a permanent FAIL on correct code.
# shellcheck disable=SC2016  # single quotes are intentional — the pattern must match the LITERAL text "$DIRS" in the workflow, not this shell's expansion of it
if grep -Eq '\$DIRS"?[[:space:]]*==[[:space:]]*"\[\]"' <<<"$wf_code"; then
  fail=$((fail + 1)); echo "[FAIL] infra-validation.yml still branches on \$DIRS == \"[]\" (the F1 early-return)" >&2
else
  pass=$((pass + 1)); echo "[ok] the \$DIRS == \"[]\" early-return is gone from the workflow"
fi

# The aggregator must actually depend on deploy-script-tests — otherwise
# needs.deploy-script-tests.result is the empty string and every run reds
# (or, worse, a future edit defaults it to something benign).
if grep -Eq '^[[:space:]]*needs:[[:space:]]*\[[^]]*deploy-script-tests[^]]*\]' <<<"$wf_code"; then
  pass=$((pass + 1)); echo "[ok] an aggregator needs: list includes deploy-script-tests"
else
  fail=$((fail + 1)); echo "[FAIL] no needs: list includes deploy-script-tests" >&2
fi

echo "---"
echo "infra-validate-gate-verdict: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
