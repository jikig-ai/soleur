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

[[ -r "$SUT" ]] || { echo "  FAIL: SUT not readable at $SUT"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }  # before the trap is installed
command -v python3 >/dev/null || { echo "  SKIP: python3 unavailable — the lint did NOT run."; echo "=== Results: 0/0 passed, 0 failed (DECLINED: no python3) ==="; exit 0; }
# PyYAML is a hard requirement, not a decline: the paired `-live` arm imports it unguarded, so
# a green SKIP here would sit beside an ImportError there reported as a FINDING (rc 1). The
# `test-scripts` shard is documented as bash + python3; mirror digest-oracle-guard.test.sh.
python3 -c 'import yaml' 2>/dev/null || { echo "  FATAL: PyYAML unavailable — the lint cannot run and the -live arm would report a finding." >&2; exit 2; }

TMP="$(mktemp -d)" || exit 2
# The verdict rides an EXIT trap, not a trailing command. Routing it through `verdict_ok`
# guards that function's BODY; the CALL was still a trailing command, and replacing it with
# `true` (or deleting it) left the suite printing its own FAIL lines and exiting 0 — the exact
# defect the verdict indirection was added to close, one line up. A trap fires however the
# script ends, so silencing it means deleting the trap, which is not a subtle edit.
_verdict_rc=2   # until the suite reaches its end, any exit is a crash, not a pass
trap 'rm -rf "$TMP"; exit "$_verdict_rc"' EXIT

SHA=0123456789abcdef0123456789abcdef01234567

# --- the floor-clearing filler tree, built ONCE ---------------------------------------------
# 32 clean workflows, each one checkout + one `./` step: 32 same-repo steps >= MIN_SAME_REPO_STEPS.
mkdir -p "$TMP/filler"
for i in $(seq -w 1 32); do
  printf 'name: filler-%s\njobs:\n  j:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@%s\n      - uses: ./.github/actions/filler\n' "$i" "$SHA" > "$TMP/filler/filler-$i.yml"
done
# ...and one clean composite, so MIN_ACTION_FILES is cleared by design too. Without it every
# case would trip the second-surface floor and measure that instead of the rule under test.
mkdir -p "$TMP/filler-actions/filler"
printf 'name: filler\nruns:\n  using: composite\n  steps:\n    - run: echo hi\n      shell: bash\n' > "$TMP/filler-actions/filler/action.yml"

mkwf() { # <name> <body>  (into the workflows dir under test)
  mkdir -p "$TMP/wf"
  printf '%s\n' "$2" > "$TMP/wf/$1"
}
mkaction() { # <path> <body>  (into the sibling actions dir the lint derives from the workflows dir)
  mkdir -p "$TMP/actions/$1"
  printf '%s\n' "$2" > "$TMP/actions/$1/action.yml"
}
run_lint() { python3 "$SUT" "$TMP/wf" >"$TMP/out" 2>"$TMP/err"; RC=$?; }
# reset() restores the filler, never a bare directory — a bare `rm -rf` would drop every case
# below the floor and every RED below would then be measuring the floor, not the rule.
reset() { rm -rf "$TMP/wf" "$TMP/actions"; cp -r "$TMP/filler" "$TMP/wf"; cp -r "$TMP/filler-actions" "$TMP/actions"; }
n_findings() { grep -c '^::error file=' "$TMP/err"; }

# --- must-PASS (i): the filler alone is clean, asserted BEFORE any case runs -----------------
reset
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "(i) the filler tree alone is clean (rc 0) — every later verdict rests on this premise"
else
  fail "(i) the filler tree is not clean: rc=$RC: $(head -1 "$TMP/err")"
fi
same_repo="$(sed -nE 's/^lint-workflow-local-action-checkout: OK — ([0-9]+) workflows scanned, ([0-9]+) local-action steps, ([0-9]+) self-repository steps, ([0-9]+) composite action file\(s\).*/\2+\3/p' "$TMP/out")"
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

python3 "$SUT" "$TMP/does-not-exist" >/dev/null 2>"$TMP/err"; rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'not a directory' "$TMP/err"; then
  pass "8d a MISSING workflows directory exits 2 (usage), never a clean scan of nothing"
else
  fail "8d a missing directory did not error — the lint could pass by scanning nothing: rc=$rc"
fi

# Precedent arm #3: a non-UTF8 file is a PARSE error (2), not a violation (1), and must not
# swallow the findings accumulated before it.
reset
printf 'name: ok\njobs:\n  j:\n    steps:\n      - run: echo hi\n' > "$TMP/wf/aaa.yml"
printf '\xff\xfe\x00\x01binary' > "$TMP/wf/zzz.yml"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'zzz.yml' "$TMP/err"; then
  pass "8e a non-UTF8 workflow exits 2 (parse error), not 1 (which reads as a violation)"
else
  fail "8e a binary file did not produce the documented parse-error code: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
printf 'name: nojobs\non: push\n' > "$TMP/wf/nojobs.yml"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'nojobs.yml' "$TMP/err"; then
  pass "8f a file with no jobs mapping exits 2 naming the file"
else
  fail "8f a jobs-less file was silently skipped: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
python3 "$SUT" "$TMP/wf" "$TMP/wf" >/dev/null 2>"$TMP/err"; rc=$?
if [[ "$rc" -eq 2 ]] && grep -qi 'expected at most one path' "$TMP/err"; then
  pass "8g extra argv is rejected (rc 2) rather than silently ignored"
else
  fail "8g a second path argument was ignored — a typo'd path would be invisible: rc=$rc"
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
  cp -r "$ROOT/.github/actions" "$TMP/live9/actions" || { echo "  FATAL: could not copy the live actions tree"; exit 2; }
  python3 "$SUT" "$TMP/live9/workflows" >"$TMP/out" 2>"$TMP/err"; crc=$?
  control_n="$(n_findings)"
  cp "$TMP/err" "$TMP/control-findings"
  # The control's own rc is an assertion, not decoration: an rc 2 control prints no findings, so
  # control_n reads 0 and the delta below would compare two zeros.
  if [[ "$crc" -eq 0 && "$control_n" -eq 0 ]]; then
    pass "9 the UNMUTATED live-tree copy is clean (rc 0, 0 findings) — the delta has a baseline"
  else
    fail "9 the unmutated live copy is not clean (rc=$crc findings=$control_n) — every verdict below is void"
  fi
  python3 - "$TMP/live9/workflows/$TARGET" <<'PY' || { echo "  FATAL: row 9 mutator failed"; exit 2; }
import sys, yaml
p = sys.argv[1]
lines = open(p).read().split("\n")
# Drop the FIRST `- uses: actions/checkout@…` line in the file AND its indented `with:` block
# (the live shape carries `with:`), by textual span. NOT job-scoped — it lands in drift-check
# only because this workflow has exactly one job and one checkout. The post-assert below
# re-parses and fails loudly if that ever stops holding, which is what makes the row safe.
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
  # PLACEMENT, not just presence: the new finding must be ABSENT from the control. A
  # `grep -q "job 'drift-check'"` alone passes vacuously whenever that finding pre-existed.
  if [[ "$mrc" -eq 1 ]] \
     && grep -q "$TARGET: job 'drift-check'" "$TMP/err" \
     && ! grep -q "$TARGET: job 'drift-check'" "$TMP/control-findings"; then
    pass "9 deleting a live sibling's checkout is CAUGHT by name, and that finding is NEW vs the control"
  else
    fail "9 the mutation's finding was absent, or was already in the control (so the row measured nothing): rc=$mrc: $(tr '\n' ' ' < "$TMP/err" | cut -c1-300)"
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
  pass "(b) a checkout carrying with: fetch-depth/persist-credentials (the live shape) satisfies a later ./ step"
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

# --- RED 13: a composite nested DEEPER than one level (a `git mv` must not move it out of reach)
reset
mkaction outer/inner 'name: nested
runs:
  using: composite
  steps:
    - uses: ./.github/actions/y
    - run: echo hi
      shell: bash'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "actions/outer/inner/action.yml" "$TMP/err"; then
  pass "13 a ./ inside a composite nested two levels deep is REFUSED (the walk is recursive)"
else
  fail "13 a nested composite escaped the walk — a git mv moves any action out of reach: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 14: the $/…@ref reject applies inside a composite too, not only in workflows --------
reset
mkaction selfat 'name: selfat
runs:
  using: composite
  steps:
    - uses: $/.github/actions/y@v1
    - run: echo hi
      shell: bash'
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "actions/selfat/action.yml" "$TMP/err" && grep -q '@' "$TMP/err"; then
  pass "14 a \$/…@ref inside a composite is REFUSED (the reject is not workflow-only)"
else
  fail "14 a \$/…@ref inside a composite slipped through — GitHub rejects it at setup: rc=$RC"
fi

# --- RED 15: a checkout carrying continue-on-error is NOT a usable checkout ------------------
reset
mkwf coe.yml "name: coe
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        continue-on-error: true
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "coe.yml: job 'j'" "$TMP/err"; then
  pass "15 a checkout that may fail (continue-on-error) does not satisfy a later ./ step"
else
  fail "15 a continue-on-error checkout was accepted — the original defect, one step earlier: rc=$RC"
fi

# --- RED 16: workflows reference ./.github/actions/… but the actions root is ABSENT -----------
# Without this the composite surface walks zero files and still reports OK.
reset
rm -rf "$TMP/actions"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'composite surface' "$TMP/err"; then
  pass "16 an absent actions root with ./.github/actions references exits 2 (never a silent zero-file walk)"
else
  fail "16 a missing actions directory reported OK while scanning zero composites: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- must-PASS (j): the composite count is REPORTED, so 'scanned nothing' is legible ---------
reset
mkaction clean 'name: clean
runs:
  using: composite
  steps:
    - uses: $/.github/actions/y
    - run: echo hi
      shell: bash'
run_lint
if [[ "$RC" -eq 0 ]] && grep -qE ' 2 composite action file\(s\)' "$TMP/out"; then
  pass "(j) a clean composite is accepted and the composite-file count appears in the OK line"
else
  fail "(j) the composite count is absent from the OK line, or a clean composite was flagged: rc=$RC: $(head -1 "$TMP/out")"
fi

# --- RED 17: a checkout whose sparse cone excludes .github cannot materialise the action ------
reset
mkwf sparse.yml "name: sparse
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        with:
          sparse-checkout: apps/web-platform
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "sparse.yml: job 'j'" "$TMP/err"; then
  pass "17 a sparse checkout excluding .github does not satisfy a ./ step"
else
  fail "17 a .github-excluding sparse cone was accepted — the workspace has no action to resolve: rc=$RC"
fi

# ...and a cone that INCLUDES .github does satisfy it (the guard must not reject every sparse form).
reset
mkwf sparseok.yml "name: sparseok
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        with:
          sparse-checkout: |
            .github
            apps
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 0 ]]; then
  pass "17 a sparse cone that INCLUDES .github is accepted (the rule is not 'reject all sparse')"
else
  fail "17 a legitimate .github-including sparse checkout was rejected: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 18: with: path: / with: repository: put the tree somewhere ./ does not resolve -------
reset
mkwf wpath.yml "name: wpath
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        with:
          path: src
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "wpath.yml: job 'j'" "$TMP/err"; then
  pass "18 a checkout into a workspace subdirectory (with: path:) does not satisfy a ./ step"
else
  fail "18 with: path: was accepted — ./ resolves at the workspace root, not the subdirectory: rc=$RC"
fi

reset
mkwf wrepo.yml "name: wrepo
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$SHA
        with:
          repository: other/repo
      - uses: ./.github/actions/x"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "wrepo.yml: job 'j'" "$TMP/err"; then
  pass "18 a checkout of a DIFFERENT repository does not satisfy a ./ step"
else
  fail "18 with: repository: was accepted — the workspace holds another repo's tree: rc=$RC"
fi

# --- RED 19: the second surface has its own floor — an actions tree that moved walks nothing --
reset
rm -rf "$TMP/actions"; mkdir -p "$TMP/actions"   # present but empty: the "it moved" shape
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'MIN_ACTION_FILES' "$TMP/err"; then
  pass "19 an empty actions tree exits 2 naming MIN_ACTION_FILES (the second surface is floored too)"
else
  fail "19 the composite surface walked zero files and still reported OK: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 20: a composite that does not parse to an action is rc 2, never counted-and-clean ----
reset
mkdir -p "$TMP/actions/notanaction"
printf -- '- just\n- a\n- list\n' > "$TMP/actions/notanaction/action.yml"
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'notanaction' "$TMP/err"; then
  pass "20 an action.yml that is not a mapping exits 2 naming it (counted-as-scanned is not clean)"
else
  fail "20 a non-mapping action.yml was counted as scanned and walked as clean: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 21-24: the four rc-2 guards the docstring promises but nothing fixtured. Neutering
# `steps`-not-a-list and `job`-not-a-mapping degrades to a CLEAN rc 0 over an unresolvable ./ step.
reset
mkwf nonstring.yml 'name: nonstring
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - uses: 42'
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'not a string' "$TMP/err"; then
  pass "21 a non-string uses: exits 2 naming the cause"
else
  fail "21 a non-string uses: did not exit 2: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
mkwf stepnonmap.yml 'name: stepnonmap
jobs:
  j:
    runs-on: ubuntu-24.04
    steps:
      - just-a-string'
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'is not a mapping' "$TMP/err"; then
  pass "22 a step that is not a mapping exits 2 naming the cause"
else
  fail "22 a non-mapping step did not exit 2: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
mkwf stepsnonlist.yml 'name: stepsnonlist
jobs:
  j:
    runs-on: ubuntu-24.04
    steps: not-a-list'
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'is not a list' "$TMP/err"; then
  pass "23 a steps: that is not a list exits 2 (neutered, it degrades to a CLEAN rc 0)"
else
  fail "23 a non-list steps: did not exit 2 — the silent-clean class: rc=$RC: $(head -1 "$TMP/err")"
fi

reset
mkwf jobnonmap.yml 'name: jobnonmap
jobs:
  j: not-a-mapping'
run_lint
if [[ "$RC" -eq 2 ]] && grep -q "job 'j' is not a mapping" "$TMP/err"; then
  pass "24 a job that is not a mapping exits 2 (neutered, it degrades to a CLEAN rc 0)"
else
  fail "24 a non-mapping job did not exit 2 — the silent-clean class: rc=$RC: $(head -1 "$TMP/err")"
fi

# --- RED 25: bracket MIN_SAME_REPO_STEPS from BELOW. Row 8b (0 steps) discriminates against any
# floor >= 1, and (i) asserts the reported count, not the constant — so 30 -> 1 stayed green.
reset
rm -rf "$TMP/wf"; mkdir -p "$TMP/wf"
for i in $(seq -w 1 29); do
  printf 'name: near-%s\njobs:\n  j:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@%s\n      - uses: ./.github/actions/near\n' "$i" "$SHA" > "$TMP/wf/near-$i.yml"
done
run_lint
if [[ "$RC" -eq 2 ]] && grep -q 'MIN_SAME_REPO_STEPS' "$TMP/err"; then
  pass "25 a tree one step BELOW the floor exits 2 (the constant is bracketed, not just >= 1)"
else
  fail "25 29 same-repo steps did not trip the floor — MIN_SAME_REPO_STEPS could be lowered to 1 unnoticed: rc=$RC"
fi

# --- RED 26: the composite walk's `.yaml` term had zero fixtures (mkaction hard-coded .yml) ----
reset
mkdir -p "$TMP/actions/yamlext"
printf 'name: yamlext\nruns:\n  using: composite\n  steps:\n    - uses: ./.github/actions/y\n' > "$TMP/actions/yamlext/action.yaml"
run_lint
if [[ "$RC" -eq 1 ]] && grep -q "actions/yamlext/action.yaml" "$TMP/err"; then
  pass "26 a composite named action.yaml is walked too (the .yaml term is pinned, mirroring row 11)"
else
  fail "26 the composite .yaml glob is unpinned — dropping it is a silent bypass: rc=$RC"
fi

# --- HARNESS CANARY + a floor that does NOT dispatch through the helper it guards ----------
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
# BOTH synthetic verdicts are unwound. Decrementing only FAIL leaves the canary's PASS in TOTAL,
# where it pads FAIL_FLOOR_MIN by one — so a future author could delete a real assertion and
# hold the floor green with a synthetic one.
PASS=$((PASS - 1))
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
FAIL_FLOOR_MIN=48
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$FAIL_FLOOR_MIN" ]]; then
  echo "  FATAL: anti-vacuity — ran $TOTAL assertions, expected >= $FAIL_FLOOR_MIN. Fix the extraction, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if verdict_ok "$FAIL"; then _verdict_rc=0; else _verdict_rc=1; fi
