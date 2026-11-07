#!/usr/bin/env bash
# Regression suite for the runner's `TEST_GROUP` handling. Parts A and B pin
# `TEST_GROUP=affected` — since #8621 a COMPAT ALIAS of the declared-edge `--affected`
# axis, not a selector of its own. Part C pins that the group never leaks into the
# suites the runner spawns (#11939), which has nothing to do with the alias.
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
#   Part C  environment hygiene (#11939) — whichever channel selected the group (the
#           monitor's step env, ci.yml's positional), no suite or grandchild the runner
#           spawns finds TEST_GROUP in its environment. It must survive removal of the
#           alias: it guards `export -n TEST_GROUP` in the runner, not the alias.
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

echo "=== test-all.sh TEST_GROUP handling suite (alias contract + environment hygiene) ==="
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
   && grep -q '_AFFECTED=1' < <(awk '/_aff_group_req" == "affected"/,/fi/' "$TARGET"); then
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
   && grep -q '_TG_AFFECTED_ALIAS:-0} == 1' "$TARGET"; then
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
  pass "B3 — positional 'affected' + --print-selection selects identically"
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
cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$SB/lib/" || { echo "FATAL: lib copy repo-write-boundary failed"; exit 2; }
for lib in test-relevance-paths.sh test-affected-paths.sh affected-glob.sh; do
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
echo "--- Part C: environment hygiene — a runner-spawned suite never observes TEST_GROUP ---"
# WHY (#11939). main-health-monitor.yml delivers the group as a step `env:` while ci.yml
# passes it positionally. The runner resolves `TEST_GROUP="${TEST_GROUP:-${1:-all}}"`
# (env wins) and, before the fix, left the variable EXPORTED, so every suite it spawned
# inherited TEST_GROUP=scripts and any suite that itself ran a nested
# `test-all.sh --enumerate-commands | --print-selection` got a narrowed or refused answer
# (lint-orphan-test-suites-mutations-a/b and Part B above, red only under the monitor).
# The fix consumes the carrier at the point of coupling, next to `unset SCRIPTS_SHARD`.
#
# HOW. Two probe suites are spliced into a sandbox runner; each records whether
# TEST_GROUP is in its own environment and in a grandchild's. C3 is the positive
# control: the same sandbox with the demotion line removed MUST read `set`, which is what
# proves the probes can see a leak (C1 pins that the line exists exactly once, so a
# control that removed nothing cannot pass). The splice removes the registration region
# (tc_acquire .. tc_epilogue), and the probes run serially without a log directory, so the
# registration region, the tee branch and the parallel launcher are not exercised by them:
# C1b is the static half for those. It is LEXICAL: a line-oriented pass over heredoc-, comment-
# and quote-stripped text that flags any line assigning, env-prefixing or exporting the variable
# (or an eval mentioning it, or allexport) unless it is one of three reviewed lines in the runner.
# What it cannot see is stated, not hoped away: an indirect `export "$name"`, a name built at run
# time, and an executed heredoc (`source /dev/stdin <<X`). The probes (C2-C9) catch those wherever
# they run; in the registration region nothing does, which is the residual risk this suite
# accepts. The durable alternative is a runtime recorder (check every spawn's environment), which
# is out of scope for a one-line fix. C6-C9 vary the environment the monitor really has: the
# other groups, the alias, CI=true, and shard bindings.
SB_REAL="$SB/real.sh"; SB_CTL="$SB/ctl.sh"   # beside runner.sh so they resolve $SB/lib
C_P0=$PASS; C_F0=$FAIL; C_ASSERTED=0
for probe in probe-a probe-b; do
  cat > "$FX/scripts/$probe.test.sh" <<'PROBE'
#!/usr/bin/env bash
# Records whether TEST_GROUP is exported into this process and into a grandchild.
: "${PROBE_DIR:?PROBE_DIR is not set}"
name="$(basename "$0" .test.sh)"
if [ -n "${TEST_GROUP+x}" ]; then own=set; else own=absent; fi
gc="$(bash -c 'if [ -n "${TEST_GROUP+x}" ]; then echo set; else echo absent; fi')"
printf 'child=%s\ngrandchild=%s\n' "$own" "$gc" > "$PROBE_DIR/$name.reading"
exit 0
PROBE
done
python3 -I - "$TARGET" "$SB_REAL" "$SB_CTL" <<'PY' || { echo "FATAL: part C sandbox splice failed"; exit 2; }
import re, sys
src, real_out, ctl_out = sys.argv[1:4]
s = open(src).read()
start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1 and s.count(end_anchor) == 1
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)
calls = ('\nrun_suite "probe-a" bash scripts/probe-a.test.sh\n'
         'run_suite "probe-b" bash scripts/probe-b.test.sh\n')
s = s[:i] + calls + s[j:]
s = s.replace('tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
open(real_out, 'w').write(s)
# Control: the same runner with the export-attribute demotion removed. Zero or one hit is
# tolerated HERE on purpose; the suite's own C1 row pins the count to exactly one.
open(ctl_out, 'w').write(re.sub(r'^export -n TEST_GROUP$', '', s, flags=re.M))
PY
# The static detector. Heredoc bodies, comment lines, trailing comments and quoted strings are
# not code, so a sentence that merely MENTIONS the words cannot trip it; what remains is
# matched in three shapes (assignment or env-pair, an export-family word with the name as any
# operand, allexport) and compared against the reviewed set by exact normalised line.
cat > "$TMP/c_static.py" <<'PYS'
import os, re, sys
REVIEWED = {
    'TEST_GROUP=Q',                                      # the resolution line
    'if [[ Q == Q ]]; then TEST_GROUP=all; fi',          # the affected -> all alias
    'export -n TEST_GROUP',                              # the demotion itself
}
path = sys.argv[1]
base = os.path.basename(path)
reviewed = REVIEWED if (len(sys.argv) > 2 and sys.argv[2] == 'runner') else set()
ASSIGN = re.compile(r'(^|[^A-Za-z0-9_$-])TEST_GROUP\+?=')
EXPORT = re.compile(r'\b(export|declare|typeset|local|readonly)\b[^;|&]*\bTEST_GROUP\b')
EVAL = re.compile(r'\beval\b.*TEST_GROUP')
ALLEXPORT = re.compile(r'(^|[;&|(\s])set(\s+-\S+)*\s+(-[a-z]*a[a-z]*|-o\s+allexport)\b')
OPENER = re.compile(r"(?<!<)<<-?\s*[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?")
hd = None
buf = ''
def analyse(line):
    global hd
    s = line.strip()
    if s.startswith('#'):
        return
    m = OPENER.search(line)
    if m:
        hd = m.group(1)
    if EVAL.search(s):
        print('%s: %s' % (base, s))
        return
    s = re.sub(r"[\"']TEST_GROUP(?=[\"'=])", 'TEST_GROUP', s)
    s = re.sub(r'"[^"]*"', 'Q', s)
    s = re.sub(r"'[^']*'", 'Q', s)
    s = re.sub(r'\s#.*$', '', s)
    if s in reviewed:
        return
    if ASSIGN.search(s) or EXPORT.search(s) or ALLEXPORT.search(s):
        print('%s: %s' % (base, s))
for raw in open(path, errors='replace'):
    line = raw.rstrip('\n')
    if hd is not None:
        if line.strip() == hd:
            hd = None
        continue
    if line.endswith('\\'):
        buf += line[:-1] + ' '
        continue
    analyse(buf + line)
    buf = ''
if buf:
    analyse(buf)
if hd is not None:
    # a `<<` inside a string or an arithmetic expression opens a phantom heredoc that would hide
    # the rest of the file; fail loudly instead of reporting clean
    print('%s: UNTERMINATED-HEREDOC <%s> (a << inside a string or arithmetic?)' % (base, hd))
PYS
c_static() { python3 -I "$TMP/c_static.py" "$1" "${2:-lib}"; } # <file> [runner|lib] -> offending lines, empty = clean

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
run_sbx() { # <runner> <probe-dir> <env pairs...> -- <runner argv...> — serial (no _pj_submit deferral)
  local runner="$1" pd="$2"; shift 2
  local envs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  assert_fixture_dir "$pd"
  rm -rf "$pd"; mkdir -p "$pd"
  (cd "$FX" && env $SIB_SCRUB -u SOLEUR_TEST_JOBS -u TEST_GROUP -u SCRIPTS_SHARD \
          SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= SOLEUR_TEST_FORCE_ALL= \
          TEST_TIMING_LOG=/dev/null PROBE_DIR="$pd" "${envs[@]+"${envs[@]}"}" \
          timeout 120 bash "$runner" "$@" 2>&1)
}
c_clean=$'child=absent\ngrandchild=absent'
c_leak=$'child=set\ngrandchild=set'
C_ROWS=0
# Both probes dispatched (a run that executed zero probes cannot pass), both read `want`,
# and the run itself succeeded. A failure names which of the three it is: a sandbox run that
# did not complete is a harness problem; a control that did not leak means the probes or the
# control are broken; any other wrong reading is the leak itself.
c_check() { # <label> <runner> <want> <env pairs...> -- <runner argv...>
  local label="$1" runner="$2" want="$3"; shift 3
  local pd="$TMP/probe-out" out rc ra rb dispatched kind
  C_ROWS=$((C_ROWS + 1)); C_ASSERTED=$((C_ASSERTED + 1))
  out=$(run_sbx "$runner" "$pd" "$@"); rc=$?
  ra=$(cat "$pd/probe-a.reading" 2>/dev/null); rb=$(cat "$pd/probe-b.reading" 2>/dev/null)
  dispatched=$(grep -cE '^\[ok\] probe-(a|b) ' <<<"$out")
  if [[ "$rc" == "0" && "$dispatched" == "2" && "$ra" == "$want" && "$rb" == "$want" ]]; then
    pass "$label"
  else
    if [[ "$rc" != "0" || "$dispatched" != "2" ]]; then
      kind="HARNESS failure (the sandbox run did not complete both probes), not a leak"
    elif [[ "$want" == "$c_leak" ]]; then
      kind="the CONTROL did not leak: the probes cannot see a leak, or ctl.sh no longer removes the demotion"
    else
      kind="TEST_GROUP readings differ from the contract: scripts/test-all.sh lost its export-attribute demotion (#11939)"
    fi
    fail "$label — $kind (rc=$rc dispatched=$dispatched probe-a=[${ra//$'\n'/ }] probe-b=[${rb//$'\n'/ }])"; dump "$out"
  fi
}
# Shards 5/6/7 were the incident. With a shard bound the probes split across the legs: each probe
# runs on exactly one leg, and every reading must be absent. Run with a 2-way and a 7-way split.
c_shard_check() { # <label> <runner> <group> <n legs>
  local label="$1" runner="$2" group="$3" n="$4" pd="$TMP/probe-out" k out rc bad="" seen_a=0 seen_b=0
  C_ROWS=$((C_ROWS + 1)); C_ASSERTED=$((C_ASSERTED + 1))
  for ((k = 1; k <= n; k++)); do
    out=$(run_sbx "$runner" "$pd" SCRIPTS_SHARD=$k/$n TEST_GROUP=$group); rc=$?
    [[ "$rc" == "0" ]] || bad+=" leg $k/$n rc=$rc"
    if [[ -f "$pd/probe-a.reading" ]]; then
      seen_a=$((seen_a + 1))
      [[ "$(cat "$pd/probe-a.reading")" == "$c_clean" ]] || bad+=" probe-a@$k/$n=[$(tr '\n' ' ' < "$pd/probe-a.reading")]"
    fi
    if [[ -f "$pd/probe-b.reading" ]]; then
      seen_b=$((seen_b + 1))
      [[ "$(cat "$pd/probe-b.reading")" == "$c_clean" ]] || bad+=" probe-b@$k/$n=[$(tr '\n' ' ' < "$pd/probe-b.reading")]"
    fi
  done
  if [[ -z "$bad" && "$seen_a" == "1" && "$seen_b" == "1" ]]; then
    pass "$label"
  else
    fail "$label — a probe read the group on a sharded leg, or a probe did not run exactly once across the legs (probe-a x$seen_a, probe-b x$seen_b):$bad"
  fi
}

# C1 — the demotion exists exactly once: the line the control removes is the line that
# fixes the leak, so a rename or a second copy must be a deliberate edit of this row.
C_ASSERTED=$((C_ASSERTED + 1))
if [[ "$(grep -c '^export -n TEST_GROUP$' "$TARGET")" == "1" ]]; then
  pass "C1 — the runner demotes TEST_GROUP's export attribute exactly once"
else
  fail "C1 — expected exactly one export-attribute demotion of TEST_GROUP in the runner"
fi
# C1b — static: nothing else in the runner or in the libs it sources assigns, env-prefixes or
# exports the group (the registration region, the tee path and the parallel launcher are outside
# what the probes execute).
C_ASSERTED=$((C_ASSERTED + 1))
c_bad=$(
  c_static "$TARGET" runner
  for c_lib in "$REPO_ROOT"/scripts/lib/*.sh "$REPO_ROOT"/plugins/soleur/scripts/lib/session-state.sh; do
    case "$c_lib" in *.test.sh) continue ;; esac
    c_static "$c_lib" lib
  done
)
if [[ -z "$c_bad" ]]; then
  pass "C1b — no assignment, env-prefix, eval or export of TEST_GROUP in the runner or its libs beyond the three reviewed runner lines"
else
  fail "C1b — a write of TEST_GROUP outside the reviewed lines (a read: quote it; prose: move it into a comment or heredoc; a legitimate runner write: extend REVIEWED in c_static.py):"; dump "$c_bad"
fi
# C1b-ctl — the detector fires on each spelling and stays quiet on prose, comments, reads and the
# reviewed lines, so an empty C1b result means something.
C_ASSERTED=$((C_ASSERTED + 1))
c1b_fire=('export TEST_GROUP' 'declare -x TEST_GROUP' 'declare -xg TEST_GROUP' 'typeset -x TEST_GROUP'
          'local -x TEST_GROUP' 'export TMPDIR TEST_GROUP' 'export "TEST_GROUP"' 'export -- TEST_GROUP'
          'set -a' 'set -o allexport' 'run_suite x env TEST_GROUP="${TEST_GROUP:-}" bash y'
          'TEST_GROUP=$TEST_GROUP run_suite x bash y' 'x | env TEST_GROUP=a bash y'
          'export -n TEST_GROUP; export TEST_GROUP' 'local TEST_GROUP="$TEST_GROUP"'
          'export "TEST_GROUP=scripts"' 'run_suite x env "TEST_GROUP=$TEST_GROUP" bash y'
          'eval "export TEST_GROUP"' 'set -e -a' 'echo "n #1"; export TEST_GROUP'
          'echo "see <<ZZZ notes"')
c1b_quiet=('# export TEST_GROUP' 'export -n TEST_GROUP' 'echo "refusing to export TEST_GROUP here"'
           ': "note: TEST_GROUP=scripts is rejected"' '[[ "$TEST_GROUP" == "all" ]] && echo ok'
           'env -u TEST_GROUP bash y' 'true  # historically: export TEST_GROUP'
           'TEST_GROUP="${TEST_GROUP:-${1:-all}}"')
c1b_fired=0; c1b_quiet_n=0
for c_shape in "${c1b_fire[@]}"; do
  printf '%s\n' "$c_shape" > "$TMP/c1b-sample.txt"
  [[ -n "$(c_static "$TMP/c1b-sample.txt" runner)" ]] && c1b_fired=$((c1b_fired + 1))
done
for c_shape in "${c1b_quiet[@]}"; do
  printf '%s\n' "$c_shape" > "$TMP/c1b-sample.txt"
  [[ -z "$(c_static "$TMP/c1b-sample.txt" runner)" ]] && c1b_quiet_n=$((c1b_quiet_n + 1))
done
# a heredoc body is prose (quiet); a write AFTER the heredoc closes is code (fires)
printf '%s\n' "cat <<'X'" 'TEST_GROUP=scripts is prose' 'X' > "$TMP/c1b-sample.txt"
[[ -z "$(c_static "$TMP/c1b-sample.txt" runner)" ]] && c1b_quiet_n=$((c1b_quiet_n + 1))
printf '%s\n' "cat <<'X'" 'prose' 'X' 'export TEST_GROUP' > "$TMP/c1b-sample.txt"
[[ -n "$(c_static "$TMP/c1b-sample.txt" runner)" ]] && c1b_fired=$((c1b_fired + 1))
# a backslash continuation does not hide the name on the next physical line
printf '%s\n' 'export \' 'TEST_GROUP' > "$TMP/c1b-sample.txt"
[[ -n "$(c_static "$TMP/c1b-sample.txt" runner)" ]] && c1b_fired=$((c1b_fired + 1))
# the reviewed lines are reviewed for the RUNNER only: the same line in a lib is an offender
printf '%s\n' 'export -n TEST_GROUP' > "$TMP/c1b-sample.txt"
[[ -n "$(c_static "$TMP/c1b-sample.txt" lib)" ]] && c1b_fired=$((c1b_fired + 1))
if [[ "$c1b_fired" == "$(( ${#c1b_fire[@]} + 3 ))" && "$c1b_quiet_n" == "$(( ${#c1b_quiet[@]} + 1 ))" ]]; then
  pass "C1b-ctl — the static detector fires on $c1b_fired spellings and stays quiet on $c1b_quiet_n prose, comment, read and reviewed lines"
else
  fail "C1b-ctl — detector self-check wrong (fired=$c1b_fired of $(( ${#c1b_fire[@]} + 3 )), quiet=$c1b_quiet_n of $(( ${#c1b_quiet[@]} + 1 )))"
fi
# C2 — the monitor's channel (step env): no spawned suite or grandchild observes it.
c_check "C2 — TEST_GROUP=scripts (the monitor's channel) is invisible to runner-spawned suites" \
  "$SB_REAL" "$c_clean" TEST_GROUP=scripts
# C3 — positive control: without the demotion the same probes DO see it.
c_check "C3 — control: with the demotion removed both probes read set" \
  "$SB_CTL" "$c_leak" TEST_GROUP=scripts
# C4/C5 — must-PASS non-canonical inputs: the positional channel (ci.yml's) and another
# permitted env value stay clean. These guard over-rejection only; they cannot see a
# missing demotion in the positional case, by construction.
c_check "C4 — the positional channel (ci.yml's) reads absent" \
  "$SB_REAL" "$c_clean" -- scripts
c_check "C5 — TEST_GROUP=scripts-heavy is invisible to runner-spawned suites" \
  "$SB_REAL" "$c_clean" TEST_GROUP=scripts-heavy
# C6 — the monitor sets the group on every leg, not only the scripts ones; `affected` is the
# deprecated alias, normalised to `all` after the resolution.
for c_group in webplat bun infra all affected; do
  c_check "C6 — TEST_GROUP=$c_group is invisible to runner-spawned suites" \
    "$SB_REAL" "$c_clean" TEST_GROUP=$c_group
done
# C7 — the monitor runs under CI=true; the sandbox otherwise blanks it.
c_check "C7 — TEST_GROUP=scripts under CI=true is invisible to runner-spawned suites" \
  "$SB_REAL" "$c_clean" CI=true TEST_GROUP=scripts
# C8 — a shard bound on a single leg (1/1): every other row runs unsharded.
c_check "C8 — TEST_GROUP=scripts with a shard bound (SCRIPTS_SHARD=1/1) is invisible to runner-spawned suites" \
  "$SB_REAL" "$c_clean" SCRIPTS_SHARD=1/1 TEST_GROUP=scripts
# C9 — the legs of a real split: shards 5/6/7 were the incident.
c_shard_check "C9 — TEST_GROUP=scripts is invisible on both legs of a 2-way shard split" "$SB_REAL" scripts 2
c_shard_check "C9 — TEST_GROUP=scripts is invisible on every leg of a 7-way shard split (the monitor's n)" "$SB_REAL" scripts 7

# Floor: rows that actually ran. Deleting the c_check calls above must not leave a green suite;
# it reports through printf+exit, never through the helpers it backstops.
C_ROWS_MIN=13
if [[ "$C_ROWS" -lt "$C_ROWS_MIN" ]]; then
  printf '[FATAL] anti-vacuity floor: Part C ran %s of %s probe rows\n' "$C_ROWS" "$C_ROWS_MIN" >&2
  exit 1
fi
# Conservation: every Part C assertion bumps C_ASSERTED independently of pass()/fail(), so a
# neutered verdict helper (which leaves the floor above satisfied) cannot hide a failure.
if [[ "$(( PASS - C_P0 + FAIL - C_F0 ))" -ne "$C_ASSERTED" ]]; then
  printf '[FATAL] conservation: Part C made %s assertions but the verdict counters moved by %s (a neutered pass()/fail(), or a Part C row added without bumping C_ASSERTED)\n' \
    "$C_ASSERTED" "$(( PASS - C_P0 + FAIL - C_F0 ))" >&2
  exit 1
fi

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" == "0" ]]
