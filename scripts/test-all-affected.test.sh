#!/usr/bin/env bash
# Regression suite for TEST_GROUP=affected — the runner's mechanical diff-scoped mode.
#
# WHY THIS EXISTS. A full local battery holds the repo-global advisory lock for ~45
# minutes uncontended, so concurrent sessions serialize into each other even when their
# diffs reach disjoint coverage. The skills told agents to "run the suites your diff
# touches", but the mapping was hand-derived prose — exactly the agent-discretion gap
# this runner exists to close. `affected` makes the runner itself the selector: every
# registration still passes the chokepoint, declines are COUNTED in the denominator,
# and a scoped run can never render as a full battery.
#
# WHAT THIS SUITE PROVES.
#
#   Part A  the structural contract — group validation, want_* widening, the run_suite
#           branch position, the counted-decline accounting, the exemption list, both
#           refusal conjuncts, the untracked-files append. Each assertion is proven to
#           RED by the mutation arms in Part C.
#   Part B  the predicate and the RUNNER — a fixture git repo drives real `git diff`
#           state through a spliced sandbox, asserting which fixture suites run, which
#           are declined, the terminal denominator, the timing-log rows, the exit
#           contract, and the fail-open arms (CI / FORCE_ALL / undeterminable diff).
#
# WHAT IT DOES NOT CLAIM. The selection heuristic is a fail-SAFE over-selector, not a
# proof of minimal coverage: anything it cannot tie to the diff runs. These tests pin
# the CONTRACTS (counting, markers, exemptions, fail-open), not the precision of any
# single signal beyond the fixture cases each was built to cover.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the suite can be pointed at a mutated copy and PROVED to red against it.
# A guard that has never been shown to fail is not evidence; this is how that gets shown.
TARGET="${TESTALL_TARGET_OVERRIDE:-$REPO_ROOT/scripts/test-all.sh}"
PASS=0; FAIL=0

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-all.sh TEST_GROUP=affected suite ==="
echo ""
echo "--- Part A: the structural contract ---"

# A1 — the group is accepted by validation, and the usage text names it. Both halves:
# accepting the token without documenting it would be the discoverability defect this
# mode exists to fix (agents must be able to FIND the substitute the refusals prescribe).
if grep -q 'all|webplat|bun|scripts|infra|affected)' "$TARGET"; then
  pass "A1 — validation case accepts affected"
else
  fail "A1 — validation case does not list affected"
fi
if grep -q 'must be one of: all, webplat, bun, scripts, infra, affected' "$TARGET"; then
  pass "A1 — usage error text names affected"
else
  fail "A1 — usage error text omits affected"
fi

# A2 — every want_* widens to affected. Selection happens per-registration at the
# run_suite chokepoint; a want_* that excluded affected would silently remove that
# group's suites from the denominator — the invisible-coverage defect ADR-181 recorded.
for fn in want_scripts want_bun want_webplat want_infra; do
  if grep -E "^${fn}\(\)" "$TARGET" | grep -q '"affected"'; then
    pass "A2 — $fn registers under affected"
  else
    fail "A2 — $fn does not include affected"
  fi
done

# A3 — the affected check sits INSIDE run_suite, after _shard_selects (shard ordinals
# must be consumed identically in every mode) and before the enumerate/exec diverge.
_affect_line=$(grep -n '! _suite_affected "$label"' "$TARGET" | head -1 | cut -d: -f1)
_shard_line=$(grep -n '_shard_selects || return 0' "$TARGET" | head -1 | cut -d: -f1)
if [[ -n "$_affect_line" && -n "$_shard_line" && "$_affect_line" -gt "$_shard_line" ]]; then
  pass "A3 — _suite_affected is consulted after _shard_selects inside run_suite"
else
  fail "A3 — affected check missing or precedes _shard_selects (affect=$_affect_line shard=$_shard_line)"
fi
# Counted decline: the branch must increment suites AND skipped AND its own counter —
# a decline that increments nothing vanishes from the denominator.
if sed -n "${_affect_line},+15p" "$TARGET" | grep -q 'suites=$((suites + 1))' \
   && sed -n "${_affect_line},+15p" "$TARGET" | grep -q 'skipped=$((skipped + 1))' \
   && sed -n "${_affect_line},+15p" "$TARGET" | grep -q '_affected_declined=$((_affected_declined + 1))'; then
  pass "A3 — the affected decline is counted (suites, skipped, _affected_declined)"
else
  fail "A3 — affected decline is not fully counted"
fi
# Timing row carries the reason label — consumers grep skip=<reason> as a LABELLED
# trailing field; an unlabelled append would be positionally ambiguous.
if sed -n "${_affect_line},+20p" "$TARGET" | grep -q 'skip=%s.*"affected"'; then
  pass "A3 — declined suites write a skip=affected timing-log row"
else
  fail "A3 — no skip=affected timing-log row in the decline branch"
fi
# Enumerate mode must emit a DECLINED record, not omit the line — the shard-totality
# reference is built from enumerate output, so an omission silently forks the count.
if sed -n "${_affect_line},+10p" "$TARGET" | grep -q '_shard_enumerate_declined_dispatch'; then
  pass "A3 — enumerate mode emits a declined record for affected skips"
else
  fail "A3 — enumerate mode does not record affected declines"
fi

# A4 — the exemption list: curated-gate and repo-wide labels bypass the generic
# predicate. Each name here corresponds to a call-site _diff_touches/_infra_in_diff
# gate (strictly better-informed) or a never-gated repo-wide registration.
# The check reads the case STATEMENT, not the design comment — the comment names the
# same labels, so a grep over the comment block would pass with the case deleted.
_exempt_block=$(sed -n '/^  case "\$label" in/,/^  esac/p' "$TARGET")
for lbl in 'registry-gate-mutation-battery' 'apps/web-platform [unit]' \
           'repo-wide+component' 'cf-tunnel-liveness-gate-mutations' \
           'c4-from-components' 'run-all.sh' 'run-registered-suites.sh'; do
  if grep -qF "$lbl" <<<"$_exempt_block"; then
    pass "A4 — exempt label present: $lbl"
  else
    fail "A4 — exempt label missing: $lbl"
  fi
done

# A5 — fail-open arms inside the predicate: FORCE_ALL, CI, undeterminable diff.
if grep -A25 '^_suite_affected() {' "$TARGET" | grep -q 'SOLEUR_TEST_FORCE_ALL' \
   && grep -A25 '^_suite_affected() {' "$TARGET" | grep -q '"${CI:-}"' \
   && grep -A25 '^_suite_affected() {' "$TARGET" | grep -q '_diff_detect_ok'; then
  pass "A5 — predicate fails open on FORCE_ALL, CI and undeterminable diff"
else
  fail "A5 — a fail-open arm is missing from _suite_affected"
fi

# A6 — both rc-4 refusals exempt affected, and BOTH name it as the substitute. A
# refusal that prescribes prose-only selection would reintroduce the hand-derived
# command list this mode replaces.
_sub_refusal_line=$(grep -n 'SOLEUR_SUBAGENT:-}' "$TARGET" | head -1 | cut -d: -f1)
if sed -n "${_sub_refusal_line},+25p" "$TARGET" | grep -q 'TEST_GROUP=affected bash scripts/test-all.sh' \
   && grep -E 'SOLEUR_SUBAGENT.*!= .affected' "$TARGET" >/dev/null; then
  pass "A6 — subagent refusal exempts affected and names it as the substitute"
else
  fail "A6 — subagent refusal does not exempt/name affected"
fi
_sib_refusal_line=$(grep -n '^if \[\[ "${TC_SIBLING_RUN_COUNT:-0}"' "$TARGET" | head -1 | cut -d: -f1)
if [[ -n "$_sib_refusal_line" ]] \
   && sed -n "${_sib_refusal_line},+6p" "$TARGET" | grep -q '"$TEST_GROUP" != "affected"' \
   && sed -n "${_sib_refusal_line},+30p" "$TARGET" | grep -q 'TEST_GROUP=affected bash scripts/test-all.sh'; then
  pass "A6 — sibling refusal exempts affected and names it as the substitute"
else
  fail "A6 — sibling refusal does not exempt/name affected"
fi

# A7 — the untracked-files append is gated to affected mode (the base set covers only
# the curated relevance prefixes; a new untracked SUT anywhere else must select its
# suites, but the append must not widen every other gate's diff view).
if grep -A3 'if \[\[ "$TEST_GROUP" == "affected" \]\]' "$TARGET" | grep -qF 'ls-files --others --exclude-standard'; then
  pass "A7 — affected mode appends the whole-tree untracked listing"
else
  fail "A7 — whole-tree untracked append missing or ungated"
fi

# A8 — the epilogue names the scope: a scoped run must never render indistinguishable
# from the battery it replaced.
if grep -q 'NOTE: TEST_GROUP=affected' "$TARGET"; then
  pass "A8 — epilogue announces the affected scope"
else
  fail "A8 — epilogue does not announce the affected scope"
fi

echo ""
echo "--- Part B: the predicate and the RUNNER against a real git diff ---"

# The fixture repo. Base commit pins origin/main; a second commit forms the range
# diff; a dirty edit forms the HEAD diff; one file stays untracked — three distinct
# provenances, because _diff_names is assembled from all three and a suite covering
# only one would leave the others unmeasured.
FX="$TMP/fixture-repo"
mkdir -p "$FX/scripts" "$FX/plugins/x" "$FX/delta" "$FX/tests/scripts"
(
  cd "$FX" || exit 1
  git init -q
  git config user.email fixture@test && git config user.name fixture
  git config commit.gpgsign false

  # Suites (tracked in the BASE commit so the suite files themselves are not the diff).
  printf 'exit 0\n'                                        > scripts/alpha.test.sh
  printf 'exit 0\n'                                        > scripts/beta.test.sh
  printf '# exercises scripts/gamma-check.sh\nexit 0\n'     > scripts/gamma.test.sh
  printf 'git ls-files >/dev/null\nexit 0\n'               > scripts/census.test.sh
  printf 'exit 0\n'                                        > scripts/epsilon.test.sh
  printf 'exit 0\n'                                        > scripts/exempt-fixture.sh
  printf '# drives plugins/x/new-untracked.sh\nexit 0\n'   > plugins/x/untracked.test.sh
  printf '# scans scripts/alpha.sh\nexit 0\n'              > delta/inner.test.sh
  printf 'exit 0\n'                                        > scripts/alpha.sh
  printf 'exit 0\n'                                        > scripts/gamma-check.sh
  git add -A && git commit -qm base
  git update-ref refs/remotes/origin/main HEAD

  # Range-diff change: committed after the origin/main ref.
  printf 'exit 0 # v2\n' > scripts/gamma-check.sh
  git add scripts/gamma-check.sh && git commit -qm gamma-change

  # HEAD-diff change: dirty, never committed.
  printf 'exit 0 # dirty\n' > scripts/alpha.sh

  # Untracked: never staged — enters _diff_names only via the ls-files --others arm.
  printf 'exit 0\n' > plugins/x/new-untracked.sh
)

# Build a sandbox copy of the runner with fixture registrations spliced between the
# lock and the epilogue — the same anchors test-all-killed-classification.test.sh
# uses, asserted unique so a rename fails LOUDLY here instead of no-op'ing.
build_sandbox() {
  local out="$1" mutation="${2:-none}"
  cp "$TARGET" "$out" || return 1
  mkdir -p "$(dirname "$out")/lib" || return 1
  cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$(dirname "$out")/lib/" || return 1
  cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$(dirname "$out")/lib/" || return 1
  python3 - "$out" "$mutation" <<'PY'
import sys, re
path, mutation = sys.argv[1], sys.argv[2]
s = open(path).read()

def sub_once(hay, old, new, what):
    assert hay.count(old) == 1, f"expected exactly one {what}, found {hay.count(old)}"
    return hay.replace(old, new)

start_anchor = 'tc_acquire "test-all"'
end_anchor = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(start_anchor) == 1, "start anchor not unique"
assert s.count(end_anchor) == 1, "end anchor not unique"
i = s.index(start_anchor) + len(start_anchor)
j = s.index(end_anchor)

# Eight fixture registrations — one per signal or override the predicate implements.
# Labels are fixture-scoped EXCEPT the exempt one, which must byte-match the curated
# label the exemption list names.
calls = """\
run_suite "alpha-stem" bash scripts/alpha.test.sh
run_suite "beta-declined" bash scripts/beta.test.sh
run_suite "gamma-content" bash scripts/gamma.test.sh
run_suite "census-backstop" bash scripts/census.test.sh
run_suite "epsilon-declined" bash scripts/epsilon.test.sh
run_suite "tests/scripts/registry-gate-mutation-battery" bash scripts/exempt-fixture.sh
run_suite "undecidable-argv" echo hello
run_suite "untracked-sut" bash plugins/x/untracked.test.sh
run_suite "delta-dir-corpus" bash -c 'exit 0' delta/
"""
s = s[:i] + "\n" + calls + s[j:]

# Neuter the advisory lock and the contention preamble — parallel worktrees are this
# repo's documented workflow, so a sandbox arm taking the REAL lock would block on
# whatever else is running.
s = sub_once(s, 'tc_acquire "test-all"', 'true "test-all"  # sandbox: lock neutered', 'tc_acquire call')
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)

# The sibling refusal requires TC_SIBLING_RUN_COUNT_PID == $$ — a value tc_preamble
# stamps in production, neutered above. Re-stamp it from the sandbox's OWN pid so the
# refusal path remains exercisable by exporting TC_SIBLING_RUN_COUNT alone.
s = sub_once(s, 'if [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0',
             'TC_SIBLING_RUN_COUNT_PID=$$\nif [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0',
             'sibling refusal opener')

# Mutations — each neuters exactly ONE guard so the arm that reds identifies it.
if mutation == "always_decline":
    m = re.search(r'^_suite_affected\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate _suite_affected"
    s = s[:m.start()] + "_suite_affected() { return 1; }" + s[m.end():]
elif mutation == "always_affected":
    m = re.search(r'^_suite_affected\(\) \{.*?^\}', s, re.S | re.M)
    assert m, "could not locate _suite_affected"
    s = s[:m.start()] + "_suite_affected() { return 0; }" + s[m.end():]
elif mutation == "no_exempt":
    m = re.search(r'  case "\$label" in\n    "tests/scripts/registry-gate-mutation-battery".*?\)\n      return 0 ;;\n  esac\n', s, re.S)
    assert m, "could not locate the exempt-label case"
    s = s[:m.start()] + s[m.end():]
elif mutation == "no_failopen":
    s = sub_once(s,
        'if [[ "$_diff_detect_ok" == 0 || "$_diff_head_ok" == 0 ]]; then return 0; fi\n\n  local a t stem',
        '\n  local a t stem', 'predicate fail-open arm')
elif mutation != "none":
    raise AssertionError(f"unknown mutation {mutation}")

open(path, 'w').write(s)
print("sandbox built")
PY
}

# Run one arm inside the fixture repo. The runner reads `git diff` from cwd, so cwd IS
# the test input here — not incidental environment.
run_arm() {
  local name="$1" mutation="${2:-none}" extra_env="${3:-}" timing="${4:-}"
  local sb="$TMP/runner-${name}-${mutation}.sh"
  ARM_OUT=""; ARM_RC=-1
  build_sandbox "$sb" "$mutation" >/dev/null || { fail "sandbox build failed: $name/$mutation"; return 1; }
  ARM_OUT=$(cd "$FX" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
            SOLEUR_TEST_FORCE_ALL= $extra_env \
            TEST_TIMING_LOG="$timing" TEST_GROUP=affected timeout 120 bash "$sb" 2>&1)
  ARM_RC=$?
  return 0
}

dump() { sed 's/^/    /' <<<"$1"; }

# --- B1: the happy path -----------------------------------------------------------
TIMING="$TMP/timing-b1.tsv"; : > "$TIMING"
run_arm b1 none "" "$TIMING" || true
B1_OUT="$ARM_OUT"; B1_RC="$ARM_RC"

for lbl in alpha-stem gamma-content census-backstop undecidable-argv untracked-sut \
           delta-dir-corpus "tests/scripts/registry-gate-mutation-battery"; do
  if grep -qE "^\[ok\] ${lbl} " <<<"$B1_OUT"; then
    pass "B1 — $lbl ran"
  else
    fail "B1 — $lbl did not run"; dump "$B1_OUT"
  fi
done
for lbl in beta-declined epsilon-declined; do
  if grep -qE "^\[skip\] ${lbl} \(affected\)" <<<"$B1_OUT"; then
    pass "B1 — $lbl declined as counted affected skip"
  else
    fail "B1 — $lbl was not declined as affected"; dump "$B1_OUT"
  fi
done

if grep -qE '^=== 7/9 suites passed ===$' <<<"$B1_OUT"; then
  pass "B1 — terminal marker keeps declined suites in the denominator (7/9)"
else
  fail "B1 — terminal marker wrong or missing"; dump "$B1_OUT"
fi
if [[ "$B1_RC" == "0" ]]; then
  pass "B1 — scoped run with all-selected suites passing exits 0"
else
  fail "B1 — exited $B1_RC, expected 0"; dump "$B1_OUT"
fi
if grep -qE 'NOTE: TEST_GROUP=affected' <<<"$B1_OUT"; then
  pass "B1 — epilogue announces the scoped run"
else
  fail "B1 — epilogue scope note missing"; dump "$B1_OUT"
fi
for lbl in beta-declined epsilon-declined; do
  # printf-built pattern: grep -E '\t' matches a literal 't', not a tab.
  if grep -qF "$(printf '%s\t0\tskip=affected' "$lbl")" "$TIMING"; then
    pass "B1 — timing log records $lbl as skip=affected"
  else
    fail "B1 — timing log has no skip=affected row for $lbl"; dump "$(cat "$TIMING")"
  fi
done

# --- B2: enumerate stays truthful --------------------------------------------------
ENUM_OUT=$(cd "$FX" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
           TEST_GROUP=affected timeout 120 bash "$TMP/runner-b1-none.sh" --enumerate-commands 2>&1)
if grep -qE $'^SUITE_COMMAND_DECLINED\tbeta-declined\t' <<<"$ENUM_OUT" \
   && grep -qE $'^SUITE_COMMAND\talpha-stem\tbash\tscripts/alpha.test.sh' <<<"$ENUM_OUT"; then
  pass "B2 — enumerate-commands records declines and selections truthfully"
else
  fail "B2 — enumerate output is untruthful"; dump "$ENUM_OUT"
fi

# --- B3: fail-open arms -------------------------------------------------------------
run_arm b3-ci none "CI=1" || true
if ! grep -q '(affected)' <<<"$ARM_OUT" && grep -qE '^=== 9/9 suites passed ===$' <<<"$ARM_OUT"; then
  pass "B3 — CI runs the full set (fail-open)"
else
  fail "B3 — CI did not run everything"; dump "$ARM_OUT"
fi

run_arm b3-force none "SOLEUR_TEST_FORCE_ALL=1" || true
if ! grep -q '(affected)' <<<"$ARM_OUT" && grep -qE '^=== 9/9 suites passed ===' <<<"$ARM_OUT"; then
  pass "B3 — SOLEUR_TEST_FORCE_ALL runs the full set"
else
  fail "B3 — FORCE_ALL did not run everything"; dump "$ARM_OUT"
fi

# Undeterminable diff: run from a directory that is NOT a git repo (the runner unsets
# GIT_DIR et al. at startup — lefthook leaks them — so env-poisoning cannot simulate
# this). Fixture paths resolve through symlinks, so this arm measures the fail-open
# verdict rather than a pile of file-not-found suite failures.
NONGIT_DIR="$TMP/not-a-repo"; mkdir -p "$NONGIT_DIR"
ln -s "$FX/scripts" "$NONGIT_DIR/scripts"
ln -s "$FX/plugins" "$NONGIT_DIR/plugins"
ln -s "$FX/delta"   "$NONGIT_DIR/delta"
NONGIT_OUT=$(cd "$NONGIT_DIR" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
             TEST_GROUP=affected timeout 120 bash "$TMP/runner-b1-none.sh" 2>&1)
if ! grep -q '(affected)' <<<"$NONGIT_OUT" && grep -qE '^=== 9/9 suites passed ===' <<<"$NONGIT_OUT"; then
  pass "B3 — undeterminable diff fails open (all suites run)"
else
  fail "B3 — undeterminable diff did not fail open"; dump "$NONGIT_OUT"
fi

# --- B4: refusal exemptions ----------------------------------------------------------
SUBG_OUT=$(cd "$FX" && env SOLEUR_SUBAGENT=1 SOLEUR_ALLOW_FULL_GATE= CI= \
           TEST_GROUP=affected timeout 120 bash "$TMP/runner-b1-none.sh" 2>&1)
SUBG_RC=$?
if [[ "$SUBG_RC" == "0" ]] && grep -qE '^=== 7/9 suites passed ===' <<<"$SUBG_OUT"; then
  pass "B4 — SOLEUR_SUBAGENT=1 does not refuse an affected run"
else
  fail "B4 — subagent refused or mis-ran affected mode (rc=$SUBG_RC)"; dump "$SUBG_OUT"
fi

SUBG_ALL_OUT=$(cd "$FX" && env SOLEUR_SUBAGENT=1 SOLEUR_ALLOW_FULL_GATE= CI= \
               TEST_GROUP=all timeout 120 bash "$TMP/runner-b1-none.sh" 2>&1)
SUBG_ALL_RC=$?
if [[ "$SUBG_ALL_RC" == "4" ]]; then
  pass "B4 — SOLEUR_SUBAGENT=1 still refuses a full-gate run (rc 4)"
else
  fail "B4 — subagent full-gate refusal broken (rc=$SUBG_ALL_RC)"; dump "$SUBG_ALL_OUT"
fi

SIB_OUT=$(cd "$FX" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
          TC_SIBLING_RUN_COUNT=2 TC_SIBLING_RUN_COUNT_PID=$$ \
          TEST_GROUP=affected timeout 120 bash "$TMP/runner-b1-none.sh" 2>&1)
SIB_RC=$?
if [[ "$SIB_RC" == "0" ]] && grep -qE '^=== 7/9' <<<"$SIB_OUT"; then
  pass "B4 — a sibling full-gate run does not refuse an affected run"
else
  fail "B4 — sibling refusal still fires under affected (rc=$SIB_RC)"; dump "$SIB_OUT"
fi

SIB_ALL_OUT=$(cd "$FX" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
              TC_SIBLING_RUN_COUNT=2 TC_SIBLING_RUN_COUNT_PID=$$ \
              TEST_GROUP=all timeout 120 bash "$TMP/runner-b1-none.sh" 2>&1)
SIB_ALL_RC=$?
if [[ "$SIB_ALL_RC" == "4" ]]; then
  pass "B4 — sibling refusal still refuses TEST_GROUP=all (rc 4)"
else
  fail "B4 — sibling full-gate refusal broken (rc=$SIB_ALL_RC)"; dump "$SIB_ALL_OUT"
fi

# --- B5: group validation --------------------------------------------------------------
BADG_OUT=$(cd "$FX" && TEST_GROUP=bogus bash "$TMP/runner-b1-none.sh" 2>&1); BADG_RC=$?
if [[ "$BADG_RC" == "2" ]] && grep -q 'affected' <<<"$BADG_OUT"; then
  pass "B5 — an unknown TEST_GROUP exits 2 and names affected in usage"
else
  fail "B5 — bad TEST_GROUP gave rc=$BADG_RC or stale usage"; dump "$BADG_OUT"
fi

# --- B6: mutation arms — each MUST red, or the assertion covering it is decorative ------
run_arm m-decl always_decline || true
if ! grep -qE '^=== 7/9 suites passed ===$' <<<"$ARM_OUT"; then
  pass "B6 — always-decline mutant reds (marker cannot read 7/9)"
else
  fail "B6 — always-decline mutant still reported 7/9"
fi
run_arm m-aff always_affected || true
# The mutant must EXHIBIT the defect — everything runs, nothing declines — because the
# B1 assertions that catch it are the [skip]-line and 7/9-marker checks.
if ! grep -q '(affected)' <<<"$ARM_OUT" && grep -qE '^=== 9/9' <<<"$ARM_OUT"; then
  pass "B6 — always-affected mutant runs everything (B1's decline assertions would red)"
else
  fail "B6 — always-affected mutant did not exhibit all-run behaviour"; dump "$ARM_OUT"
fi
run_arm m-exempt no_exempt || true
if grep -qE '^\[skip\] tests/scripts/registry-gate-mutation-battery \(affected\)' <<<"$ARM_OUT"; then
  pass "B6 — removing the exemption list declines the curated label (detected)"
else
  fail "B6 — no_exempt mutant did not decline the curated label"; dump "$ARM_OUT"
fi
run_arm m-fo no_failopen || true
MFO_NONGIT=$(cd "$NONGIT_DIR" && env SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= CI= \
             TEST_GROUP=affected timeout 120 bash "$TMP/runner-m-fo-no_failopen.sh" 2>&1)
if grep -q '(affected)' <<<"$MFO_NONGIT"; then
  pass "B6 — removing the diff fail-open declines suites on an undeterminable diff (detected)"
else
  fail "B6 — no_failopen mutant still failed open"; dump "$MFO_NONGIT"
fi

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" == "0" ]]
