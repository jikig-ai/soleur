#!/usr/bin/env bash
# Regression suite for `TEST_GROUP=affected` — since #8621 a COMPAT ALIAS of the
# declared-edge `--affected` axis, not a selector of its own.
#
# WHY THIS EXISTS. #8591 shipped a second, heuristic affected selector (argv-path
# containment, content references, stem equality, grep-based census backstop at the
# run_suite chokepoint). #8621 measured its decline set against the declared-edge
# index's on 19 real diffs
# (knowledge-base/project/specs/feat-one-shot-8621-converge-selectors/measurements.md):
# the heuristic declined 49-355 suites per diff that the index selected — including
# always-on ratchets its grep backstop could not classify, and ~300+ on runner/index
# diffs where the declared gate correctly degrades to full. Misses land = the
# issue's fold criterion: the heuristic machinery came out, the declared index is
# the single selector, and the `TEST_GROUP=affected` spelling survives as a
# parse-time alias of `--affected` because the refusal bodies and skill prose
# prescribe it.
#
# WHAT THIS SUITE PROVES.
#
#   Part A  the structural contract — the group token still validates, the alias
#           arms _AFFECTED, normalisation happens after the ambiguity refusal and
#           before every consumer, the ambiguity rc=2 refusal still guards
#           --affected/--full combinations, the heuristic machinery is GONE, the
#           always-on census floor survives, the refusals still name the
#           substitute, and the epilogue names the alias.
#   Part B  the alias BEHAVES like --affected — --print-selection output is
#           byte-identical under both spellings, the surviving selector declines
#           an edge suite on a known-irrelevant diff and selects it on its
#           subject diff, the always-on floor selects on both, the combo
#           refusals fire rc=2, and a sandbox run proves the refusal exemptions
#           dispatch (subagent + sibling).
#
# WHAT IT DOES NOT CLAIM. Selection semantics themselves are
# scripts/test-all-affected.test.sh's subject — this suite pins the ALIAS
# contract and that nothing heuristic-shaped survived the fold.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the suite can be pointed at a mutated copy and PROVED to red against it.
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
PASS=0; FAIL=0

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
dump() { sed 's/^/    /' <<<"$1"; }

echo "=== test-all.sh TEST_GROUP=affected (alias) suite ==="
echo ""
echo "--- Part A: the structural contract ---"

# A1 — the group token still validates (it is the alias spelling, still accepted)
# and the usage error names it: deleting it from the enum would break every
# prescribed-substitute invocation the refusals print.
if grep -q 'all|webplat|bun|scripts|scripts-heavy|infra|affected)' "$TARGET"; then
  pass "A1 — validation case accepts affected"
else
  fail "A1 — validation case does not list affected"
fi
if grep -q 'must be one of: all, webplat, bun, scripts, scripts-heavy, infra, affected' "$TARGET"; then
  pass "A1 — usage error text names affected"
else
  fail "A1 — usage error text omits affected"
fi

# A2 — the alias arms the declared-edge axis: naming the group sets _AFFECTED=1
# and remembers the spelling in _TG_AFFECTED_ALIAS for the deprecation note.
if grep -q '_aff_group_req" == "affected"' "$TARGET" \
   && grep -q '_TG_AFFECTED_ALIAS=1' "$TARGET" \
   && awk '/_aff_group_req" == "affected"/,/fi/' "$TARGET" | grep -q '_AFFECTED=1'; then
  pass "A2 — TEST_GROUP=affected arms _AFFECTED and the alias marker"
else
  fail "A2 — the alias does not arm the --affected axis"
fi

# A3 — normalisation to `all` happens AFTER the ambiguity refusal and before any
# downstream consumer could observe the group value.
_norm_line=$(grep -n 'if \[\[ "$TEST_GROUP" == "affected" \]\]; then TEST_GROUP=all; fi' "$TARGET" | head -1 | cut -d: -f1)
_refuse_line=$(grep -n 'TEST_GROUP=affected cannot be combined' "$TARGET" | head -1 | cut -d: -f1)
if [[ -n "$_norm_line" && -n "$_refuse_line" && "$_norm_line" -gt "$_refuse_line" ]]; then
  pass "A3 — the alias normalises to all after the ambiguity refusal"
else
  fail "A3 — normalisation missing or precedes the refusal (norm=$_norm_line refuse=$_refuse_line)"
fi

# A4 — the ambiguity refusal guards only the contradictory spellings now:
# --affected (same axis twice, tracked by _AFFECTED_FLAG) and --full.
if grep -q '_AFFECTED_FLAG == 1 || _FULL_REQ == 1' "$TARGET" \
   && grep -q '_AFFECTED_FLAG=1' "$TARGET"; then
  pass "A4 — combo refusal keys on the --affected flag and --full"
else
  fail "A4 — combo refusal conjunct drifted"
fi

# A5 — the heuristic machinery is GONE. A presence grep pins the removal: any
# resurrection of the chokepoint predicate fails loudly here.
for tok in _suite_affected _aff_stem _AFFECT_PATTERNS _AFFECT_STEMS 'skip=affected' '(affected)'; do
  if grep -qF "$tok" "$TARGET"; then
    fail "A5 — heuristic residue survives: $tok"
  else
    pass "A5 — removed: $tok"
  fi
done

# A6 — the census backstop survives as the always-on floor: ALWAYS_ON_SUITES is
# declared in the index and the below-floor refusal still exists.
if grep -q 'ALWAYS_ON_SUITES' "$REPO_ROOT/scripts/lib/test-affected-paths.sh" \
   && grep -q '_AC_CLASS="always_on"' "$TARGET" \
   && grep -q 'reason=below-floor' "$TARGET"; then
  pass "A6 — the always-on census floor is intact"
else
  fail "A6 — always-on floor machinery missing"
fi

# A7 — both refusal bodies still name the scoped substitute (the alias spelling
# the refused agent can copy-paste) AND the canonical flag.
_sub_refusal_line=$(grep -n 'SOLEUR_SUBAGENT:-}' "$TARGET" | head -1 | cut -d: -f1)
if sed -n "${_sub_refusal_line},+25p" "$TARGET" | grep -c >/dev/null 'TEST_GROUP=affected bash scripts/test-all.sh' \
   && sed -n "${_sub_refusal_line},+25p" "$TARGET" | grep -c >/dev/null 'bash scripts/test-all.sh --affected'; then
  pass "A7 — subagent refusal names both scoped spellings"
else
  fail "A7 — subagent refusal lost a substitute spelling"
fi
_sib_refusal_line=$(grep -n '^if \[\[ "${TC_SIBLING_RUN_COUNT:-0}"' "$TARGET" | head -1 | cut -d: -f1)
if [[ -n "$_sib_refusal_line" ]] \
   && sed -n "${_sib_refusal_line},+30p" "$TARGET" | grep -c >/dev/null 'TEST_GROUP=affected bash scripts/test-all.sh'; then
  pass "A7 — sibling refusal still names the scoped substitute"
else
  fail "A7 — sibling refusal does not name the substitute"
fi

# A8 — the epilogue names the alias: a run under the deprecated spelling must
# say so rather than read as either the heuristic it replaced or a full battery.
if grep -q 'NOTE: TEST_GROUP=affected is a deprecated alias' "$TARGET" \
   && grep -q '_TG_AFFECTED_ALIAS == 1' "$TARGET"; then
  pass "A8 — epilogue announces the deprecated alias"
else
  fail "A8 — no deprecation note keyed on _TG_AFFECTED_ALIAS"
fi

echo ""
echo "--- Part B: the alias behaves like --affected ---"

# B1 — selection parity: --print-selection under the alias is BYTE-IDENTICAL to
# the flag spelling on the same pathset (stdout only; stderr telemetry may
# legitimately differ — derive-cache hits depend on call order).
P1=plugins/soleur/skills/ship/SKILL.md
env -u CI bash "$TARGET" --print-selection --paths="$P1" > "$TMP/decl-p1.out" 2>/dev/null
DRC1=$?
env -u CI TEST_GROUP=affected bash "$TARGET" --print-selection --paths="$P1" > "$TMP/tg-p1.out" 2>/dev/null
TRC1=$?
if [[ "$DRC1" == 0 && "$TRC1" == 0 ]] && cmp -s "$TMP/decl-p1.out" "$TMP/tg-p1.out" \
   && grep -q 'AFFECTED_SELECTED' "$TMP/tg-p1.out"; then
  pass "B1 — alias --print-selection is byte-identical to --affected's ($(grep -c AFFECTED_SELECTED "$TMP/tg-p1.out") rows)"
else
  fail "B1 — alias selection output diverges (rc=$DRC1/$TRC1)"; diff "$TMP/decl-p1.out" "$TMP/tg-p1.out" | head -10
fi

# B2 — the surviving selector's contract on fixture diffs: an edge-class suite
# DECLINES on a diff it cannot reach and SELECTS on its subject diff; the
# always-on floor selects on both (the census backstop that outlived the fold).
P_IRREL='knowledge-base/support/community/2026-10-26-digest.md'
P_SUBJ='scripts/lint-rule-ids.py'
env -u CI bash "$TARGET" --print-selection --paths="$P_IRREL" > "$TMP/irrel.out" 2>/dev/null
env -u CI bash "$TARGET" --print-selection --paths="$P_SUBJ" > "$TMP/subj.out" 2>/dev/null
_row() { grep -P "^AFFECTED_SELECTED\t$1\t" "$2" | cut -f3; }
if [[ "$(_row 'tests/scripts/lint-rule-ids' "$TMP/irrel.out")" == "0" ]]; then
  pass "B2 — edge suite declines on a known-irrelevant diff"
else
  fail "B2 — edge suite not declined on irrelevant diff: $(_row 'tests/scripts/lint-rule-ids' "$TMP/irrel.out")"
fi
if [[ "$(_row 'tests/scripts/lint-rule-ids' "$TMP/subj.out")" == "1" ]]; then
  pass "B2 — edge suite selects on its touched-subject diff"
else
  fail "B2 — edge suite not selected on subject diff"
fi
if grep -qP 'AFFECTED_SELECTED\tscripts/lint-guard-contract\t1\talways_on' "$TMP/irrel.out" \
   && grep -qP 'AFFECTED_SELECTED\tscripts/lint-guard-contract\t1\talways_on' "$TMP/subj.out"; then
  pass "B2 — the always-on census floor selects on both diffs"
else
  fail "B2 — an always-on suite fell off the floor"
fi

# B3 — the contradiction refusals still fire rc=2 under the alias.
OUT=$(env -u CI TEST_GROUP=affected bash "$TARGET" --affected 2>&1); RC=$?
if [[ "$RC" == "2" ]] && grep -qF 'cannot be combined' <<<"$OUT"; then
  pass "B3 — TEST_GROUP=affected --affected refuses rc=2"
else
  fail "B3 --affected combo gave rc=$RC"; dump "$OUT"
fi
OUT=$(env -u CI TEST_GROUP=affected bash "$TARGET" --full 2>&1); RC=$?
if [[ "$RC" == "2" ]] && grep -qF 'cannot be combined' <<<"$OUT"; then
  pass "B3 — TEST_GROUP=affected --full refuses rc=2"
else
  fail "B3 --full combo gave rc=$RC"; dump "$OUT"
fi
# ...while the non-contradictory spellings compose: positional `affected` and
# --print-selection both work under the alias.
env -u CI bash "$TARGET" --print-selection --paths="$P1" affected > "$TMP/pos-p1.out" 2>/dev/null; RC=$?
if [[ "$RC" == "0" ]] && cmp -s "$TMP/pos-p1.out" "$TMP/tg-p1.out"; then
  pass "B3 — positional `affected` + --print-selection selects identically"
else
  fail "B3 — positional alias diverged (rc=$RC)"
fi
BADG_OUT=$(env -u CI TEST_GROUP=bogus bash "$TARGET" 2>&1); BADG_RC=$?
if [[ "$BADG_RC" == "2" ]] && grep -q 'affected' <<<"$BADG_OUT"; then
  pass "B3 — an unknown TEST_GROUP still exits 2 and names affected in usage"
else
  fail "B3 — bad TEST_GROUP gave rc=$BADG_RC or stale usage"; dump "$BADG_OUT"
fi

# B4 — the refusals exempt the alias exactly like the flag. A sandboxed runner
# (fixture registrations, neutered lock, the declarations lib beside it so the
# axis is pure, not degraded) proves SOLEUR_SUBAGENT=1 and a measured sibling do
# not refuse a TEST_GROUP=affected run — and DO refuse --full.
FX="$TMP/fixture-repo"
mkdir -p "$FX/scripts"
(
  cd "$FX" || exit 1
  git init -q
  git config user.email fixture@test && git config user.name fixture
  git config commit.gpgsign false
  printf 'exit 0\n' > scripts/alpha.test.sh
  git add -A && git commit -qm base
  git update-ref refs/remotes/origin/main HEAD
)

SB="$TMP/sb"; mkdir -p "$SB/lib"
cp "$TARGET" "$SB/runner.sh" || { echo "FATAL: sandbox copy failed"; exit 2; }
for lib in test-relevance-paths.sh repo-write-boundary.sh test-affected-paths.sh affected-glob.sh; do
  cp "$REPO_ROOT/scripts/lib/$lib" "$SB/lib/" || { echo "FATAL: lib copy $lib failed"; exit 2; }
done
python3 - "$SB/runner.sh" <<'PY' || { echo "FATAL: sandbox splice failed"; exit 2; }
import re, sys
path = sys.argv[1]
s = open(path).read()
def sub_once(hay, old, new, what):
    assert hay.count(old) == 1, f"expected exactly one {what}, found {hay.count(old)}"
    return hay.replace(old, new)
# Splice fixture registrations between the lock and the epilogue (the anchors
# test-all-killed-classification uses).
start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1 and s.count(end_anchor) == 1
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)
calls = '\nrun_suite "alpha-fixture" bash scripts/alpha.test.sh\n'
s = s[:i] + calls + s[j:]
s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
s = sub_once(s, 'if [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0',
             'TC_SIBLING_RUN_COUNT_PID=$$\nif [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0',
             'sibling refusal opener')
# The runner-changed self-edge is live on THIS diff (the runner is the SUT);
# neuter its membership computation so the alias arms measure _AFFECTED, not
# the degraded-full fallback ladder (same seam fanout-suite-scope's SANDBOX_AFF uses).
old = ('_aff_runner_in_diff=0\n'
       '  if grep -qF \'scripts/test-all.sh\' <<<"$_diff_names" \\\n'
       '    || grep -qF \'scripts/lib/test-affected-paths.sh\' <<<"$_diff_names"; then\n'
       '    _aff_runner_in_diff=1\n'
       '  fi')
assert s.count(old) == 1, "runner-changed membership anchor drifted"
s = s.replace(old, '_aff_runner_in_diff=0  # sandbox: self-edge disabled to isolate the exemption')
open(path, 'w').write(s)
PY

SIB_SCRUB="-u TC_SIBLING_RUN_COUNT -u TC_SIBLING_RUN_COUNT_PID"
run_sb() { # <env pairs...> -- <runner argv...> — runs the sandbox inside the fixture repo
  local envs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  (cd "$FX" && env $SIB_SCRUB SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
          SOLEUR_TEST_FORCE_ALL= TEST_TIMING_LOG=/dev/null "${envs[@]+"${envs[@]}"}" \
          timeout 120 bash "$SB/runner.sh" "$@" 2>&1)
}

OUT=$(run_sb TEST_GROUP=affected); RC=$?
if [[ "$RC" == "0" ]] && grep -qE '^\[ok\] alpha-fixture ' <<<"$OUT" \
   && grep -q 'NOTE: TEST_GROUP=affected is a deprecated alias' <<<"$OUT"; then
  pass "B4 — the alias runs affected-shaped and announces itself"
else
  fail "B4 — alias run misbehaved (rc=$RC)"; dump "$OUT"
fi

OUT=$(run_sb SOLEUR_SUBAGENT=1 TEST_GROUP=affected); RC=$?
if [[ "$RC" == "0" ]] && grep -qE '^\[ok\] alpha-fixture ' <<<"$OUT"; then
  pass "B4 — SOLEUR_SUBAGENT=1 does not refuse the alias"
else
  fail "B4 — subagent refused the alias (rc=$RC)"; dump "$OUT"
fi
OUT=$(run_sb SOLEUR_SUBAGENT=1 TEST_GROUP=affected -- --full); RC=$?
if [[ "$RC" == "2" ]]; then
  pass "B4 — subagent + --full under the alias hits the ambiguity refusal (rc=2)"
else
  fail "B4 — subagent + --full gave rc=$RC"; dump "$OUT"
fi
OUT=$(run_sb TC_SIBLING_RUN_COUNT=2 TEST_GROUP=affected); RC=$?
if [[ "$RC" == "0" ]] && grep -qE '^\[ok\] alpha-fixture ' <<<"$OUT"; then
  pass "B4 — a measured sibling does not refuse the alias"
else
  fail "B4 — sibling refused the alias (rc=$RC)"; dump "$OUT"
fi
OUT=$(run_sb TC_SIBLING_RUN_COUNT=2 SOLEUR_ALLOW_FULL_GATE= TEST_GROUP=all -- --full); RC=$?
if [[ "$RC" == "4" ]]; then
  pass "B4 — the sibling refusal still fires on a genuine full-gate ask (rc=4)"
else
  fail "B4 — sibling full-gate refusal broken (rc=$RC)"; dump "$OUT"
fi

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" == "0" ]]
