#!/usr/bin/env bash
# Tests scripts/lint-workflow-local-action-checkout.py.
#
# The lint exists because scheduled-marketplace-drift.yml's checkout-free drift-check job ended
# in `uses: ./.github/actions/sentry-heartbeat` under `continue-on-error: true`: the runner could
# not resolve the composite (there is no workspace to resolve it from), the step went green, and
# the Sentry monitor stayed dark for every run since the workflow was created. Every fixture
# below is SYNTHESIZED (cq-test-fixtures-synthesized-only) except row 9, which MUTATES a copy of
# the live tree and asserts the delta, so it proves the verifier against a real sibling on every
# run, on either reference-form arm, before and after the fix lands.
#
# Every fixture tree clears MIN_SAME_REPO_STEPS on purpose: the filler tree is built once and
# every case starts from a copy of it, so the floor is exercised by design rather than bypassed.
# Only row 8's below-floor sub-cases start from a bare directory.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$ROOT/scripts/lint-workflow-local-action-checkout.py"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -r "$SUT" ]] || { echo "  FAIL: SUT not readable at $SUT"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }
command -v python3 >/dev/null || { echo "  SKIP: python3 unavailable — the lint did NOT run."; echo "=== Results: 0/0 passed, 0 failed (DECLINED: no python3) ==="; exit 0; }
python3 -c 'import yaml' 2>/dev/null || { echo "  SKIP: PyYAML unavailable — the lint did NOT run."; echo "=== Results: 0/0 passed, 0 failed (DECLINED: no PyYAML) ==="; exit 0; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

SHA=0123456789abcdef0123456789abcdef01234567

# --- the floor-clearing filler tree, built ONCE ---------------------------------------------
# 32 clean workflows, each one checkout + one `./` step: 32 same-repo steps >= MIN_SAME_REPO_STEPS.
mkdir -p "$TMP/filler"
for i in $(seq -w 1 32); do
  printf 'name: filler-%s\njobs:\n  j:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@%s\n      - uses: ./.github/actions/filler\n' "$i" "$SHA" > "$TMP/filler/filler-$i.yml"
done

mkwf() { # <name> <body>  (into the workflows dir under test)
  mkdir -p "$TMP/wf"
  printf '%s\n' "$2" > "$TMP/wf/$1"
}
mkaction() { # <name> <body>  (into the sibling actions dir the lint derives from the workflows dir)
  mkdir -p "$TMP/actions/$1"
  printf '%s\n' "$2" > "$TMP/actions/$1/action.yml"
}
run_lint() { python3 "$SUT" "$TMP/wf" >"$TMP/out" 2>"$TMP/err"; RC=$?; }
# reset() restores the filler, never a bare directory — a bare `rm -rf` would drop every case
# below the floor and every RED below would then be measuring the floor, not the rule.
reset() { rm -rf "$TMP/wf" "$TMP/actions"; cp -r "$TMP/filler" "$TMP/wf"; }
n_findings() { grep -c '^::error file=' "$TMP/err"; }

# --- must-PASS (i): the filler alone is clean, asserted BEFORE any case runs -----------------
reset
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(i) the filler tree alone is clean (rc 0) — every later verdict rests on this premise"
else
  fail "(i) the filler tree is not clean: rc=$RC: $(head -1 "$TMP/err")"
fi
same_repo="$(sed -nE 's/^lint-workflow-local-action-checkout: OK — ([0-9]+) workflows scanned, ([0-9]+) local-action steps, ([0-9]+) self-repository steps.*/\2+\3/p' "$TMP/out")"
if [[ -n "$same_repo" ]] && [[ "$((same_repo))" -ge 30 ]]; then
  pass "(i) the OK line has the canonical shape and the filler carries >= 30 same-repo steps ($((same_repo)))"
else
  fail "(i) the OK line is malformed or the filler is below the floor: $(head -1 "$TMP/out")"
fi

# --- RED 1: a `./` step with no actions/checkout in the job at all --------------------------
reset
mkwf bad.yml 'name: bad
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: ./.github/actions/x'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "bad.yml: job 'j'" "$TMP/err"; then
  pass "1 a local action with no checkout in its job is REFUSED, naming file and job"
else
  fail "1 the defect that shipped was not caught: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 2: the checkout exists but comes AFTER the `./` step (order, not presence) ---------
reset
mkwf after.yml "name: after
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: ./.github/actions/x
      - uses: actions/checkout@$SHA"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "after.yml: job 'j'" "$TMP/err"; then
  pass "2 a checkout AFTER the local step does not satisfy it (order is the property)"
else
  fail "2 a late checkout was accepted — presence was checked, not order: rc=$RC"
fi

# --- RED 3: job A's checkout must not satisfy job B; a THIRD file must still be walked ------
reset
mkwf multi.yml "name: multi
jobs:
  a:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
      - uses: ./.github/actions/x
  b:
    runs-on: ubuntu-24.04
    steps:
      - uses: ./.github/actions/x"
mkwf zz-third.yml 'name: third
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: ./.github/actions/x'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "multi.yml: job 'b'" "$TMP/err" && ! grep -q "multi.yml: job 'a'" "$TMP/err" && grep -q "zz-third.yml: job 'j'" "$TMP/err"; then
  pass "3 checkouts are per-job (B named, A not) and the walk reaches a later file"
else
  fail "3 cross-job satisfaction or a truncated walk: rc=$RC: $(tr '\n' ' ' < "$TMP/err" | cut -c1-300)"
fi

# --- RED 4: the production shape — neither continue-on-error nor if: always() exempts it ----
reset
mkwf prod.yml 'name: prod
jobs:
  canary:
    runs-on: ubuntu-24.04
    steps:
      - run: echo canary
  drift-check:
    needs: canary
    if: ${{ !cancelled() }}
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        arm: [a, b]
    steps:
      - run: echo check
      - name: Sentry check-in (final)
        uses: ./.github/actions/sentry-heartbeat
        if: always()
        continue-on-error: true
        with:
          sentry-ingest-domain: ${{ secrets.A }}
          sentry-project-id: ${{ secrets.B }}
          sentry-public-key: ${{ secrets.C }}
          monitor-slug: scheduled-x
          status: ok'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "prod.yml: job 'drift-check', step 'Sentry check-in (final)'" "$TMP/err"; then
  pass "4 the shipped shape (matrix job, if: always(), continue-on-error) is REFUSED by step name"
else
  fail "4 the production shape was exempted by one of its keys: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 5: a CONDITIONAL checkout followed by an unconditional local step -----------------
reset
mkwf cond.yml "name: cond
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        if: \${{ inputs.x }}
      - uses: ./.github/actions/x
        if: always()"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "cond.yml: job 'j'" "$TMP/err"; then
  pass "5 a checkout skipped by its own if: is no checkout for an always() local step"
else
  fail "5 a conditional checkout satisfied an unconditional local step: rc=$RC"
fi

# --- RED 6: a checkout LOOKALIKE (an unanchored substring match passes rows 1-5) -----------
reset
mkwf lookalike.yml "name: lookalike
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout-foo@$SHA
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "lookalike.yml: job 'j'" "$TMP/err"; then
  pass "6 actions/checkout-foo is not actions/checkout (the match is anchored)"
else
  fail "6 a lookalike satisfied the rule — the checkout match is a substring: rc=$RC"
fi

# --- RED 7: a self-repository ref carrying @ref (actionlint 1.7.7 accepts, GitHub rejects) --
reset
mkwf selfat.yml 'name: selfat
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: $/.github/actions/x@v1'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "selfat.yml: job 'j'" "$TMP/err" && grep -q '@' "$TMP/err"; then
  pass "7 a \$/ reference with an @ref suffix is REFUSED (GitHub rejects it; actionlint does not)"
else
  fail "7 \$/…@ref slipped through — the one form the runtime rejects that actionlint accepts: rc=$RC"
fi

# --- RED 8: dispatch — every non-scan outcome is rc 2 AND names its cause --------------------
rm -rf "$TMP/wf" "$TMP/actions"; mkdir -p "$TMP/wf"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'scanned 0' "$TMP/err"; then
  pass "8a an EMPTY directory exits 2 naming the zero scan, never a clean verdict"
else
  fail "8a an empty directory did not exit 2 with the cause named: rc=$RC: $(head -1 "$TMP/err")"
fi

rm -rf "$TMP/wf" "$TMP/actions"; mkdir -p "$TMP/wf"
for i in $(seq -w 1 40); do
  printf 'name: nouses-%s\njobs:\n  j:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n' "$i" > "$TMP/wf/nouses-$i.yml"
done
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'MIN_SAME_REPO_STEPS' "$TMP/err"; then
  pass "8b 40 workflows with 0 same-repo steps exit 2 naming the floor (a scan of nothing is not clean)"
else
  fail "8b a below-floor tree did not exit 2 naming MIN_SAME_REPO_STEPS: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
printf 'jobs:\n  j:\n    steps:\n      - uses: [\n' > "$TMP/wf/broken.yml"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'broken.yml' "$TMP/err"; then
  pass "8c an unparseable workflow exits 2 naming the file (parse error, not a finding, not a skip)"
else
  fail "8c a broken file was skipped or read as a finding: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
printf 'name: nojobs\non: push\n' > "$TMP/wf/nojobs.yml"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'nojobs.yml' "$TMP/err"; then
  pass "8d a file with no jobs mapping exits 2 naming the file"
else
  fail "8d a jobs-less file was silently skipped: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
python3 "$SUT" "$TMP/wf" "$TMP/wf" >/dev/null 2>"$TMP/err"; rc=$?
if [[ "$rc" -eq 2 ]] && grep -qi 'expected at most one path' "$TMP/err"; then
  pass "8e extra argv is rejected (rc 2) rather than silently ignored"
else
  fail "8e a second path argument was ignored — a typo'd path would be invisible: rc=$rc"
fi

# --- RED 9: VERIFY THE VERIFIER on the live tree — delete a real sibling's checkout ----------
# Arm- and phase-independent: the control is the unmutated copy's finding count, and the
# assertion is the DELTA, so this row is green before the marketplace-drift fix lands and on
# either reference-form arm.
LIVE="$ROOT/.github/workflows"
TARGET=scheduled-domain-model-drift.yml
if [[ -f "$LIVE/$TARGET" ]]; then
  mkdir -p "$TMP/live9"
  cp -r "$LIVE" "$TMP/live9/workflows" || { echo "  FATAL: could not copy the live workflows tree"; exit 2; }
  python3 "$SUT" "$TMP/live9/workflows" >"$TMP/out" 2>"$TMP/err"; crc=$?
  control_n="$(n_findings)"
  python3 - "$TMP/live9/workflows/$TARGET" <<'PY' || { echo "  FATAL: row 9 mutator failed"; exit 2; }
import sys, yaml
p = sys.argv[1]
lines = open(p).read().split("\n")
# Drop the `- uses: actions/checkout@…` line AND its indented `with:` block (the live shape
# carries `with:`), inside the drift-check job only, by textual span.
out, n, i = [], 0, 0
while i < len(lines):
    l = lines[i]
    if n == 0 and l.lstrip().startswith("- uses: actions/checkout@"):
        indent = len(l) - len(l.lstrip())
        i += 1
        while i < len(lines) and (lines[i].strip() == "" or (len(lines[i]) - len(lines[i].lstrip())) > indent):
            i += 1
        n += 1
        continue
    out.append(l)
    i += 1
assert n == 1, "row 9 mutator removed no checkout STEP"
open(p, "w").write("\n".join(out))
d = yaml.safe_load(open(p))
steps = d["jobs"]["drift-check"]["steps"]
assert not any(str(s.get("uses", "")).startswith("actions/checkout") for s in steps), "row 9: deletion did not land in steps[]"
assert any(str(s.get("uses", "")).startswith("./") for s in steps), "row 9: the job has no ./ step left to flag"
PY
  python3 "$SUT" "$TMP/live9/workflows" >"$TMP/out" 2>"$TMP/err"; mrc=$?
  mutant_n="$(n_findings)"
  if [[ "$mrc" -eq 1 ]] && grep -q "$TARGET: job 'drift-check'" "$TMP/err"; then
    pass "9 deleting a live sibling's checkout is CAUGHT by name ($TARGET: job 'drift-check')"
  else
    fail "9 the real defect re-introduced into a live tree copy was NOT caught: rc=$mrc: $(tr '\n' ' ' < "$TMP/err" | cut -c1-300)"
  fi
  if [[ "$mutant_n" -eq $((control_n + 1)) ]]; then
    pass "9 the mutated copy reports exactly control+1 findings ($control_n -> $mutant_n; control rc=$crc)"
  else
    fail "9 the delta is not +1 (control=$control_n mutant=$mutant_n) — the row measured something other than the mutation"
  fi
else
  fail "9 $TARGET is absent from the live tree — row 9 has no sibling to mutate"
  fail "9 (delta) not measured"
fi

# --- RED 10: a commented-out checkout, or one named in a run: body, is not a checkout --------
reset
mkwf comment.yml "name: comment
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      # - uses: actions/checkout@$SHA
      - run: echo actions/checkout is mentioned but never used
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "comment.yml: job 'j'" "$TMP/err"; then
  pass "10 a commented-out or run:-quoted checkout does not count (YAML parse, not text scan)"
else
  fail "10 text mentioning actions/checkout satisfied the rule — the lint is a text scan: rc=$RC"
fi

# --- RED 11: the .yaml extension is scanned too --------------------------------------------
reset
mkwf bad.yaml 'name: badyaml
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: ./.github/actions/x'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "bad.yaml: job 'j'" "$TMP/err"; then
  pass "11 a .yaml (not .yml) workflow is scanned too"
else
  fail "11 the .yaml glob is unpinned — dropping it is a silent bypass: rc=$RC"
fi

# --- RED 12: the second surface — a composite whose own steps use ./ -------------------------
reset
mkaction x 'name: x
runs:
  using: composite
  steps:
    - uses: ./.github/actions/y
    - run: echo hi
      shell: bash'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "actions/x/action.yml" "$TMP/err"; then
  pass "12 a ./ reference inside a composite action is REFUSED (it resolves from the CALLER's workspace)"
else
  fail "12 a nested ./ inside .github/actions/*/action.yml was not flagged: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- must-PASS (a): a self-repository ref needs no checkout ---------------------------------
reset
mkwf selfref.yml 'name: selfref
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: $/.github/actions/x'
run_lint
if [[ "$RC" -eq 0 ]] && grep -q ' 1 self-repository step' "$TMP/out"; then
  pass "(a) \$/.github/actions/x with no checkout is clean and counted as a self-repository step"
else
  fail "(a) the \$/ form was flagged or not counted: rc=$RC: $(head -1 "$TMP/err") / $(head -1 "$TMP/out")"
fi

# --- must-PASS (b): the live checkout shape carries with: ----------------------------------
reset
mkwf withblock.yml "name: withblock
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(b) a checkout carrying with: (the live shape) satisfies a later ./ step"
else
  fail "(b) the live checkout shape was rejected: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- must-PASS (c): a tag-pinned checkout (pin-ness is a separate property) ----------------
reset
mkwf tag.yml 'name: tag
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/x'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(c) actions/checkout@v4 is a checkout (pin-ness is not this lint's property)"
else
  fail "(c) a tag-pinned checkout was rejected: rc=$RC"
fi

# --- must-PASS (d): a job-level uses: (reusable workflow) has no steps and is skipped ------
reset
mkwf reusable.yml 'name: reusable
jobs:
  j:
    uses: ./.github/workflows/reusable.yml
    secrets: inherit'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(d) a job-level uses: ./.github/workflows/… (reusable workflow) is not a local-action step"
else
  fail "(d) a reusable-workflow call was flagged: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- must-PASS (e): run:-only steps ---------------------------------------------------------
reset
mkwf runonly.yml 'name: runonly
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - run: echo one
      - run: echo two'
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(e) a job with run:-only steps is clean"
else
  fail "(e) a uses:-free job was flagged: rc=$RC"
fi

# --- must-PASS (f): checkout and ./ step share a byte-identical if: ------------------------
reset
mkwf sameif.yml "name: sameif
jobs:
  preflight:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        if: \${{ inputs.clean_stray }}
      - uses: ./.github/actions/x
        if: \${{ inputs.clean_stray }}"
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(f) a conditional checkout satisfies a ./ step with the byte-identical if:"
else
  fail "(f) the same-if: shape (workspaces-luks-cutover preflight) was rejected: rc=$RC"
fi

# --- must-PASS (g): the remote subdirectory form (the documented fallback) -----------------
reset
mkwf remote.yml "name: remote
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: jikig-ai/soleur/.github/actions/x@$SHA"
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(g) owner/repo/path@sha with no checkout is clean (resolved at Set up job)"
else
  fail "(g) the remote subdirectory form was flagged: rc=$RC"
fi

# --- must-PASS (h): any qualifying earlier checkout satisfies the step --------------------
reset
mkwf anyok.yml "name: anyok
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
      - uses: actions/checkout@$SHA
        if: \${{ inputs.x }}
        with:
          path: other
      - uses: ./.github/actions/x
        if: always()"
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(h) an unconditional checkout satisfies an always() step even when a later conditional one would not"
else
  fail "(h) a qualifying earlier checkout was ignored in favour of a later conditional one: rc=$RC"
fi

# --- HARNESS CANARY + a floor that does NOT dispatch through the helper it guards ----------
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
FAIL=$((FAIL - 1))

# THE FINAL GATE NEEDS ITS OWN GUARD, and it is the one thing neither check above covers.
# The canary proves pass()/fail() still COUNT; the floor proves enough assertions RAN. Nothing
# proved the line that converts a non-zero FAIL into a non-zero EXIT. Measured: replacing the
# bare `[[ "$FAIL" -eq 0 ]]` tail with `true` left the suite printing its own FAIL lines and
# exiting 0 — CI reads that as green. So route the verdict through ONE function, prove that
# function discriminates in BOTH directions, and then use the same function as the exit status.
verdict_ok() { [[ "$1" -eq 0 ]]; }
if verdict_ok 0 && ! verdict_ok 1; then
  pass "the exit verdict discriminates: FAIL=0 succeeds, FAIL=1 does not"
else
  echo "  FATAL: the exit verdict does not discriminate — a failing suite could exit 0." >&2
  exit 2
fi

# LITERAL, on the line directly above the test. scripts/guard-vacuity-floor.test.sh widens its
# mutant slice BACKWARD only over contiguous simple assignments, so a threshold computed further
# up does not bind and the floor is scored "not constructible" — counted as UNCOVERED by ADR-193
# rather than as passing. `scripts/` is a COVERED directory, so this must bind from the start.
FAIL_FLOOR_MIN=29
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$FAIL_FLOOR_MIN" ]]; then
  echo "  FATAL: anti-vacuity — ran $TOTAL assertions, expected >= $FAIL_FLOOR_MIN. Fix the extraction, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
verdict_ok "$FAIL"
