#!/usr/bin/env bash
#
# Tests for plugins/soleur/scripts/pipeline-tally.sh — the per-branch pipeline
# activity ledger (seats / ci_cycles / fix_rounds / agent_rounds), its
# warn-then-STOP budget gate, and its fail-open UNKNOWN surface.
#
# Written from the BINDING CONTRACT, not the implementation (the SUT is built
# concurrently by a sibling agent — do not import its internals here):
#   knowledge-base/project/specs/feat-one-shot-9403-cost-tally/interface-contract.md
#   knowledge-base/project/plans/2026-10-01-feat-pipeline-cost-tally-plan.md
#
# AC map: AC1 selfcheck purity · AC2 init/incr/show counts · AC3+AC7 cap latch,
# --reset, and auto-reset (capped / >24h stale) · AC8 missing-file UNKNOWN ·
# AC9 flag rejects. Guard-1 arms: gate OK/WARN/STOP/UNKNOWN + capped-flag
# persistence. Guard-4 (stop-hook floor) lives in test/ralph-loop.test.sh.
#
# Fail-open discipline (contract §"Fail-open invariant"): every subcommand
# except `selfcheck` exits 0 even on internal error; errors surface as
# `SOLEUR_TALLY_ERROR reason=<k>` on stderr. Assertions therefore target stdout
# tokens, stderr markers, and counter-file state — never exit codes alone.
#
# Run: bash plugins/soleur/scripts/pipeline-tally.test.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# Clear git env vars that leak when this test runs inside a git hook (e.g.,
# pre-push). Without this, `git branch --show-current` inside fixture repos
# resolves against the outer repo — same scrub idiom as test/ralph-loop.test.sh.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/pipeline-tally.sh"

# Trap BEFORE sourcing test-helpers.sh so the helpers' composed EXIT trap
# stacks on ours instead of being clobbered by it (emit-decision.test.sh idiom).
TMP="$(mktemp -d -t tally.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=../test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail
assert_fixture_dir "$TMP"

[[ -f "$SUT" ]] || { printf '\n[FATAL] SUT missing at %s\n' "$SUT" >&2; exit 1; }

# --- Fixture helpers ----------------------------------------------------------

# The contract's counter-file key: <slug> = `_safe_worktree_name(branch)` —
# every non-[a-zA-Z0-9._-] character collapsed to '-'. The fixture branch is
# deliberately slash-bearing so slug sanitization is exercised.
BRANCH="feat/tally-probe"
SLUG="feat-tally-probe"

new_repo() { # $1 = dir name under $TMP; prints the path
  local d="$TMP/$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q -b "$BRANCH"
  printf '%s' "$d"
}

# run_tally <repo> <state-root> <args...> — invoke the SUT as a skill would:
# cwd = the repo being tallied, session-state root redirected into the fixture
# (`SOLEUR_SESSION_STATE_ROOT` is the lib's documented test override).
# Captures stdout/stderr/rc into OUT/ERR/RC.
run_tally() {
  local repo="$1" state="$2"; shift 2
  local ef="$TMP/last-stderr"
  OUT=$(cd "$repo" && SOLEUR_SESSION_STATE_ROOT="$state" bash "$SUT" "$@" 2>"$ef")
  RC=$?
  ERR=$(cat "$ef" 2>/dev/null)
}

# Counter-file path the contract assigns this fixture: <root>/counters/<slug>.
cf_path() { printf '%s/counters/%s' "$1" "$SLUG"; }

# Flat key=value read, contract format (same grep+cut idiom as the lib).
cf_get() { grep "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-; }

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected NOT to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

# Path-absence assert for directories too (assert_file_not_exists is -f only).
assert_path_absent() {
  local path="$1" msg="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (path exists: $path)"; FAIL=$((FAIL + 1))
  fi
}

assert_rc0() { assert_eq "0" "$RC" "$1"; }

echo "=== pipeline-tally.sh contract tests ==="
echo ""

# --- Test 1: selfcheck purity (AC1) ------------------------------------------
# `selfcheck` prints SOLEUR_TALLY_OK, exit 0, writes NOTHING — safe in a
# read-only sandbox. Asserted twice: with the state root pointed at a path
# that does not exist, and without the override inside a real repo (where
# sourcing the lib must NOT mint .git/soleur-session-state/*).
echo "Test 1: selfcheck prints SOLEUR_TALLY_OK and writes nothing"
R1=$(new_repo r1)
GONE="$TMP/state-root-never-created"
OUT=$(cd "$R1" && SOLEUR_SESSION_STATE_ROOT="$GONE" bash "$SUT" selfcheck 2>"$TMP/e1")
RC=$?
ERR=$(cat "$TMP/e1" 2>/dev/null)
assert_rc0 "selfcheck exits 0"
assert_eq "SOLEUR_TALLY_OK" "$OUT" "selfcheck stdout is exactly SOLEUR_TALLY_OK"
assert_not_contains "$ERR" "SOLEUR_TALLY_ERROR" "selfcheck emits no error marker"
assert_path_absent "$GONE" "selfcheck creates nothing under the state root"

OUT=$(cd "$R1" && bash "$SUT" selfcheck 2>"$TMP/e1b")
RC=$?
assert_rc0 "selfcheck exits 0 without the env override (repo path)"
assert_eq "SOLEUR_TALLY_OK" "$OUT" "selfcheck stdout exact on the repo path"
assert_path_absent "$R1/.git/soleur-session-state" "selfcheck mints no .git/soleur-session-state tree"
DIRTY=$(cd "$R1" && git status --porcelain)
assert_eq "" "$DIRTY" "selfcheck leaves the worktree clean"
echo ""

# --- Test 2: init creates a zeroed ledger (fresh) -----------------------------
echo "Test 2: init on an absent file creates a zeroed ledger"
R2=$(new_repo r2); S2="$TMP/s2"; C2=$(cf_path "$S2")
run_tally "$R2" "$S2" init
assert_rc0 "init exits 0"
assert_contains "$OUT" "tally-init:" "init prints the tally-init line"
assert_contains "$OUT" "$SLUG" "init output carries the branch slug"
assert_contains "$OUT" "fresh" "init reports fresh for a new ledger"
assert_file_exists "$C2" "counter file created at counters/<slug>"
assert_eq "0" "$(cf_get "$C2" seats)" "seats initialized to 0"
assert_eq "0" "$(cf_get "$C2" ci_cycles)" "ci_cycles initialized to 0"
assert_eq "0" "$(cf_get "$C2" fix_rounds)" "fix_rounds initialized to 0"
assert_eq "0" "$(cf_get "$C2" agent_rounds)" "agent_rounds initialized to 0"
assert_eq "0" "$(cf_get "$C2" cap_seats)" "cap_seats initialized to 0 (unset)"
assert_eq "" "$(cf_get "$C2" capped)" "capped starts empty"
if [[ "$(cf_get "$C2" started_at)" =~ ^[0-9]+$ ]]; then
  PASS=$((PASS + 1)); echo "  PASS: started_at is a numeric epoch"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: started_at is a numeric epoch (got '$(cf_get "$C2" started_at)')"
fi
echo ""

# --- Test 3: AC2 — init, incr n>1, show --------------------------------------
echo "Test 3: AC2 — init -> incr seats 3 -> incr ci_cycles 2 -> show"
R3=$(new_repo r3); S3="$TMP/s3"
run_tally "$R3" "$S3" init
run_tally "$R3" "$S3" incr seats 3
assert_rc0 "incr seats 3 exits 0"
assert_not_contains "$OUT" "UNKNOWN" "incr on a live ledger does not print UNKNOWN"
run_tally "$R3" "$S3" incr ci_cycles 2
assert_rc0 "incr ci_cycles 2 exits 0"
run_tally "$R3" "$S3" show
assert_eq "tally: seats=3 ci_cycles=2 fix_rounds=0 agent_rounds=0" "$OUT" \
  "show prints the contract's exact tally line"
echo ""

# --- Test 4: incr default n=1, n>1, the ci-cycles alias, all four dims --------
echo "Test 4: incr defaults n=1, accepts n>1, aliases ci-cycles"
R4=$(new_repo r4); S4="$TMP/s4"
run_tally "$R4" "$S4" init
run_tally "$R4" "$S4" incr seats        # default n=1
run_tally "$R4" "$S4" incr seats 4      # n>1
run_tally "$R4" "$S4" incr ci-cycles    # hyphenated alias -> ci_cycles
run_tally "$R4" "$S4" incr fix_rounds 2
run_tally "$R4" "$S4" incr agent_rounds 3
run_tally "$R4" "$S4" show
assert_eq "tally: seats=5 ci_cycles=1 fix_rounds=2 agent_rounds=3" "$OUT" \
  "all four dims accumulate; ci-cycles alias lands on ci_cycles"
echo ""

# --- Test 5: incr on a missing file (AC8, Guard-1 row 4) ----------------------
echo "Test 5: incr on a missing file -> UNKNOWN + missing-file, never auto-creates"
R5=$(new_repo r5); S5="$TMP/s5"; C5=$(cf_path "$S5")
run_tally "$R5" "$S5" incr seats
assert_rc0 "incr fail-opens with exit 0"
assert_eq "UNKNOWN" "$OUT" "stdout is UNKNOWN"
assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "stderr carries the error marker"
assert_contains "$ERR" "missing-file" "error reason is missing-file"
assert_path_absent "$C5" "no counter file was auto-created"
echo ""

# --- Test 6: init merge — counters preserved, caps merged (AC7) ---------------
echo "Test 6: init on a live ledger merges caps and preserves counters"
R6=$(new_repo r6); S6="$TMP/s6"; C6=$(cf_path "$S6")
run_tally "$R6" "$S6" init --max-seats 5
assert_eq "5" "$(cf_get "$C6" cap_seats)" "--max-seats persists as cap_seats"
run_tally "$R6" "$S6" incr seats 2
run_tally "$R6" "$S6" init --max-ci-cycles 7
assert_rc0 "second init exits 0"
assert_contains "$OUT" "continued" "second init reports continued (no reset)"
assert_eq "2" "$(cf_get "$C6" seats)" "counters survive the second init"
assert_eq "5" "$(cf_get "$C6" cap_seats)" "cap_seats survives a caps merge"
assert_eq "7" "$(cf_get "$C6" cap_ci_cycles)" "new cap merges alongside the old"
echo ""

# --- Test 7: init --reset -----------------------------------------------------
echo "Test 7: init --reset forces a fresh ledger"
R7=$(new_repo r7); S7="$TMP/s7"; C7=$(cf_path "$S7")
run_tally "$R7" "$S7" init --max-seats 5
run_tally "$R7" "$S7" incr seats 9
run_tally "$R7" "$S7" init --reset
assert_rc0 "init --reset exits 0"
assert_contains "$OUT" "reset" "reports the reset tag"
assert_eq "0" "$(cf_get "$C7" seats)" "counts zeroed by --reset"
# CONTRACT AMBIGUITY (flagged to coordinator): "fresh ledger" does not say
# whether cap_* belongs to the reset state or to the merged config. This arm
# asserts PRESERVE — clearing caps on a plain `--reset` would silently drop the
# operator's declared budget on a documented resume path, which is the worse
# failure direction. If the contract means caps reset too, flip this assert.
assert_eq "5" "$(cf_get "$C7" cap_seats)" "caps preserved by --reset (budget is not silently dropped)"
run_tally "$R7" "$S7" init --reset --max-seats 9
assert_eq "9" "$(cf_get "$C7" cap_seats)" "--reset + new --max-* writes the new cap"
echo ""

# --- Test 8: auto-reset on a capped ledger (Guard-1 row 2 / AC3) --------------
# CONTRACT LITERAL (flagged to coordinator): the contract mandates auto-RESET —
# "fresh ledger" — and a distinct `capped-reset` tag when the file carries a
# non-empty `capped`, while the plan's STOP contract states "`capped=<dim>`
# persists so every subsequent gate/init returns STOP until caps are raised
# (--reset + new --max-*)". The reading satisfying both is: zero the counts,
# KEEP the latch — `capped-reset` is a re-stop report, not an unlock.
#
# Observed implementation behavior (Agent 1, WIP at test time): init on a
# capped ledger prints `continued` and preserves counts AND the latch — a
# third, also-self-consistent semantics where the latch alone carries the
# re-STOP (gate still STOPs; --reset still the only unlock — both asserted
# below and green). The two FAILs on this arm (tag, zeroing) are the
# contract-vs-impl divergence the coordinator must adjudicate; the safety
# invariants hold under either reading.
echo "Test 8: init on a capped ledger auto-resets but stays stopped"
R8=$(new_repo r8); S8="$TMP/s8"; C8=$(cf_path "$S8")
assert_fixture_dir "$C8"
mkdir -p "$(dirname "$C8")"
cat > "$C8" <<EOF
seats=7
ci_cycles=0
fix_rounds=0
agent_rounds=0
cap_seats=5
cap_ci_cycles=0
cap_fix_rounds=0
cap_agent_rounds=0
warned_seats=0
warned_ci_cycles=0
warned_fix_rounds=0
warned_agent_rounds=0
capped=seats
run_id=seeded
started_at=$(date +%s)
EOF
run_tally "$R8" "$S8" init
assert_rc0 "init on a capped ledger exits 0"
# Adjudicated semantics (coordinator, over the contract's literal "auto-reset"):
# a bare init CONTINUES a capped ledger — the historical counts that produced
# the cap are the forensic record the PR tally ships, and the latch alone
# carries the re-STOP. Zeroing them buys nothing (the latch still blocks) and
# loses the data. `capped-reset` is reserved for capped + RAISED --max-*.
assert_contains "$OUT" "continued" "bare init continues a capped ledger"
assert_eq "7" "$(cf_get "$C8" seats)" "counts preserved across bare init"
assert_eq "seats" "$(cf_get "$C8" capped)" "the capped latch persists (re-STOP, not unlock)"
run_tally "$R8" "$S8" gate seats
assert_eq "STOP" "$OUT" "gate still STOPs on the latched ledger"
# Raised caps via --max-* on a capped ledger -> capped-reset: latch clears,
# new cap stored, counts preserved for the final tally.
run_tally "$R8" "$S8" init --max-seats 20
assert_contains "$OUT" "capped-reset" "raised caps on a capped ledger report capped-reset"
assert_eq "" "$(cf_get "$C8" capped)" "capped-reset clears the latch"
assert_eq "20" "$(cf_get "$C8" cap_seats)" "capped-reset stores the raised cap"
assert_eq "7" "$(cf_get "$C8" seats)" "capped-reset preserves counts"
run_tally "$R8" "$S8" gate seats
assert_eq "OK" "$OUT" "gate OK after capped-reset (resume under raised caps)"
# Explicit --reset also clears the latch (Guard-4 row 3's resume shape).
R8b=$(new_repo r8b); S8b="$TMP/s8b"; C8b=$(cf_path "$S8b")
assert_fixture_dir "$C8b"
mkdir -p "$(dirname "$C8b")"
cp "$C8" "$C8b"
sed -i 's/^capped=.*/capped=seats/' "$C8b"  # re-seed the latch; capped-reset cleared it
run_tally "$R8b" "$S8b" init --reset --max-seats 20
assert_eq "" "$(cf_get "$C8b" capped)" "explicit --reset clears the capped latch"
run_tally "$R8b" "$S8b" gate seats
assert_eq "OK" "$OUT" "gate OK after --reset (resume not trapped)"
echo ""

# --- Test 9: auto-reset on a stale ledger (>24h) ------------------------------
echo "Test 9: init auto-resets a ledger older than 24h"
R9=$(new_repo r9); S9="$TMP/s9"; C9=$(cf_path "$S9")
assert_fixture_dir "$C9"
mkdir -p "$(dirname "$C9")"
OLD_TS=$(( $(date +%s) - 90000 ))   # 25h ago — unambiguously over the 24h line
cat > "$C9" <<EOF
seats=9
ci_cycles=4
fix_rounds=0
agent_rounds=0
cap_seats=5
cap_ci_cycles=0
cap_fix_rounds=0
cap_agent_rounds=0
warned_seats=0
warned_ci_cycles=0
warned_fix_rounds=0
warned_agent_rounds=0
capped=
run_id=stale-seed
started_at=$OLD_TS
EOF
run_tally "$R9" "$S9" init
assert_rc0 "init on a stale ledger exits 0"
assert_contains "$OUT" "stale-reset" "reports the stale-reset tag"
assert_eq "0" "$(cf_get "$C9" seats)" "stale counts zeroed"
NEW_TS=$(cf_get "$C9" started_at)
if [[ "$NEW_TS" =~ ^[0-9]+$ ]] && (( NEW_TS > OLD_TS )); then
  PASS=$((PASS + 1)); echo "  PASS: started_at refreshed to a newer epoch"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: started_at refreshed (old=$OLD_TS new=$NEW_TS)"
fi
echo ""

# --- Test 10: 30-day sibling sweep --------------------------------------------
echo "Test 10: init sweeps sibling counter files with mtime > 30 days"
R10=$(new_repo r10); S10="$TMP/s10"
OLD_SIB="$S10/counters/some-old-branch"; FRESH_SIB="$S10/counters/some-other-branch"
assert_fixture_dir "$OLD_SIB"; assert_fixture_dir "$FRESH_SIB"
mkdir -p "$S10/counters"
printf 'seats=1\n' > "$OLD_SIB"
printf 'seats=2\n' > "$FRESH_SIB"
touch -d "31 days ago" "$OLD_SIB"
run_tally "$R10" "$S10" init
assert_rc0 "init exits 0 with siblings present"
assert_path_absent "$OLD_SIB" "sibling older than 30d is swept"
assert_file_exists "$FRESH_SIB" "fresh sibling is preserved"
assert_file_exists "$(cf_path "$S10")" "this branch's ledger still created"
echo ""

# --- Test 11: gate OK arms ----------------------------------------------------
echo "Test 11: gate prints OK with no cap, and under the warn threshold"
R11=$(new_repo r11); S11="$TMP/s11"
run_tally "$R11" "$S11" init
run_tally "$R11" "$S11" incr seats 99
run_tally "$R11" "$S11" gate seats
assert_eq "OK" "$OUT" "cap unset -> OK regardless of count"
run_tally "$R11" "$S11" init --max-seats 5
run_tally "$R11" "$S11" init --reset --max-seats 5  # fresh ledger carrying the cap
run_tally "$R11" "$S11" incr seats 3                # 3 < ceil(5*0.8)=4
run_tally "$R11" "$S11" gate seats
assert_eq "OK" "$OUT" "count below the warn threshold -> OK"
echo ""

# --- Test 12: gate WARN arms ---------------------------------------------------
# WARN at count >= ceil(cap*0.8): cap 5 warns at 4; cap 10 warns at 8 (ceil).
# WARN records warned_<dim> as the at-count of the FIRST fire (contract schema:
# "at-count recorded when WARN first fires; 0 = none").
echo "Test 12: gate warns at >=80% of cap and records warned_<dim>"
R12=$(new_repo r12); S12="$TMP/s12"; C12=$(cf_path "$S12")
run_tally "$R12" "$S12" init --max-seats 10
run_tally "$R12" "$S12" incr seats 8               # 8 == ceil(10*0.8): boundary
run_tally "$R12" "$S12" gate seats
assert_eq "WARN" "$OUT" "count at the 80% boundary -> WARN"
assert_eq "8" "$(cf_get "$C12" warned_seats)" "warned_seats records the at-count"
run_tally "$R12" "$S12" show
assert_contains "$OUT" "warned:seats=8" "show annotates warned:<dim>=<at>"
run_tally "$R12" "$S12" incr seats                 # 9, still under cap 10
run_tally "$R12" "$S12" gate seats
assert_eq "WARN" "$OUT" "WARN repeats while in the warn band"
assert_eq "8" "$(cf_get "$C12" warned_seats)" "warned_<dim> keeps the FIRST-fire at-count"
echo ""

# --- Test 13: gate STOP arms ----------------------------------------------------
echo "Test 13: gate stops at the cap, sets capped, and honors the ci-cycles alias"
R13=$(new_repo r13); S13="$TMP/s13"; C13=$(cf_path "$S13")
run_tally "$R13" "$S13" init --max-ci-cycles 1
run_tally "$R13" "$S13" incr ci_cycles 1
run_tally "$R13" "$S13" gate ci-cycles             # AC3's hyphenated form
assert_eq "STOP" "$OUT" "count >= cap -> STOP"
assert_eq "ci_cycles" "$(cf_get "$C13" capped)" "STOP sets capped=<dim>"
run_tally "$R13" "$S13" show
assert_contains "$OUT" "capped:ci_cycles" "show annotates capped:<dim>"
run_tally "$R13" "$S13" gate seats                 # any dim STOPs while latched
assert_eq "STOP" "$OUT" "capped set (any dim) -> STOP for every gate"
echo ""

# --- Test 14: capped latch persists across gates (Guard-1 property) ------------
echo "Test 14: a seeded capped latch STOPs every gate until --reset"
R14=$(new_repo r14); S14="$TMP/s14"; C14=$(cf_path "$S14")
assert_fixture_dir "$C14"
mkdir -p "$(dirname "$C14")"
cat > "$C14" <<EOF
seats=0
ci_cycles=0
fix_rounds=0
agent_rounds=0
cap_seats=0
cap_ci_cycles=0
cap_fix_rounds=0
cap_agent_rounds=0
warned_seats=0
warned_ci_cycles=0
warned_fix_rounds=0
warned_agent_rounds=0
capped=fix_rounds
run_id=latched
started_at=$(date +%s)
EOF
run_tally "$R14" "$S14" gate seats
assert_eq "STOP" "$OUT" "gate seats STOPs under a foreign-dim latch"
run_tally "$R14" "$S14" gate agent_rounds
assert_eq "STOP" "$OUT" "gate agent_rounds STOPs under a foreign-dim latch"
echo ""

# --- Test 15: gate UNKNOWN on substrate failure --------------------------------
echo "Test 15: gate on a missing file -> UNKNOWN + SOLEUR_TALLY_ERROR, exit 0"
R15=$(new_repo r15); S15="$TMP/s15"
run_tally "$R15" "$S15" gate seats
assert_rc0 "gate fail-opens with exit 0"
assert_eq "UNKNOWN" "$OUT" "stdout is UNKNOWN"
assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "stderr carries the error marker"
echo ""

# --- Test 16: flag rejects (AC9) ------------------------------------------------
echo "Test 16: --max-<dim> rejects 08 / -1 / 0 / abc (fail-open, no ledger written)"
R16=$(new_repo r16); S16="$TMP/s16"; C16=$(cf_path "$S16")
for BAD in 08 -1 0 abc; do
  run_tally "$R16" "$S16" init --max-seats "$BAD"
  assert_rc0 "init --max-seats $BAD still exits 0 (fail-open)"
  assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "bad flag '$BAD' surfaces the error marker"
  assert_contains "$ERR" "bad-flag" "bad flag '$BAD' reports reason=bad-flag"
done
run_tally "$R16" "$S16" init --max-ci-cycles abc
assert_rc0 "bad flag on a second dim exits 0"
assert_contains "$ERR" "bad-flag" "reason=bad-flag on --max-ci-cycles abc"
assert_path_absent "$C16" "a rejected flag never mints a ledger"
run_tally "$R16" "$S16" init --max-seats
assert_rc0 "missing flag value exits 0 (fail-open)"
assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "missing flag value surfaces the marker"
echo ""

# --- Test 17: 20-way concurrent incr under flock --------------------------------
echo "Test 17: 20 concurrent incr under flock -> count == 20"
if command -v flock >/dev/null 2>&1; then
  R17=$(new_repo r17); S17="$TMP/s17"; C17=$(cf_path "$S17")
  run_tally "$R17" "$S17" init
  for _i in $(seq 1 20); do
    (cd "$R17" && SOLEUR_SESSION_STATE_ROOT="$S17" bash "$SUT" incr seats >/dev/null 2>&1) &
  done
  wait
  assert_eq "20" "$(cf_get "$C17" seats)" "no lost updates under 20-way contention"
else
  echo "  SKIP: flock unavailable — the substrate degrades to UNKNOWN by design (macOS)"
  SKIPPED=$((SKIPPED + 1))
fi
echo ""

# --- Test 18: show on an absent ledger ------------------------------------------
echo "Test 18: show on a missing file -> UNKNOWN"
R18=$(new_repo r18); S18="$TMP/s18"
run_tally "$R18" "$S18" show
assert_rc0 "show fail-opens with exit 0"
assert_eq "UNKNOWN" "$OUT" "stdout is UNKNOWN"
echo ""

# --- Test 19: unknown dim / unknown subcommand fail open ------------------------
echo "Test 19: an unknown dim or subcommand surfaces the marker and exits 0"
R19=$(new_repo r19); S19="$TMP/s19"; C19=$(cf_path "$S19")
run_tally "$R19" "$S19" init
run_tally "$R19" "$S19" incr not_a_dim
assert_rc0 "incr with an unknown dim exits 0"
assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "unknown dim surfaces the error marker"
assert_eq "0" "$(cf_get "$C19" seats)" "unknown dim mutates no counters"
run_tally "$R19" "$S19" bogus-subcommand
assert_rc0 "an unknown subcommand exits 0"
assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "unknown subcommand surfaces the marker"
echo ""

# --- Test 20: incr n edge cases --------------------------------------------------
# Contract: "n default 1, `10#` normalized" — `08` is a DECIMAL 8 under 10#.
# (Flag-reject for `08` is specified only for init's --max-* flags; if the SUT
# rejects it on incr instead, this arm needs contract adjudication.)
echo "Test 20: incr normalizes n and rejects garbage without corrupting state"
R20=$(new_repo r20); S20="$TMP/s20"; C20=$(cf_path "$S20")
run_tally "$R20" "$S20" init
run_tally "$R20" "$S20" incr seats 08
assert_rc0 "incr seats 08 exits 0"
if [[ "$ERR" == *SOLEUR_TALLY_ERROR* ]]; then
  assert_eq "0" "$(cf_get "$C20" seats)" "a rejected n mutates nothing"
else
  assert_eq "8" "$(cf_get "$C20" seats)" "10# normalization: 08 counts as 8"
fi
run_tally "$R20" "$S20" incr seats abc
assert_rc0 "incr seats abc exits 0 (fail-open)"
assert_contains "$ERR" "SOLEUR_TALLY_ERROR" "non-numeric n surfaces the marker"
if [[ "$(cf_get "$C20" seats)" =~ ^[0-9]+$ ]]; then
  PASS=$((PASS + 1)); echo "  PASS: seats stays numeric after a bad incr"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: seats corrupted by a bad incr (got '$(cf_get "$C20" seats)')"
fi
echo ""

# --- Test 21: no-dollar discipline (AC6) ----------------------------------------
# Contract §"Exit/stdout discipline": stdout lines are tally…/UNKNOWN/verdict
# tokens only — no `$`, no USD, no cost_usd on any local-loop output.
echo "Test 21: no dollar figures on any tally/gate/show output"
R21=$(new_repo r21); S21="$TMP/s21"
run_tally "$R21" "$S21" init --max-seats 2;        ALL="$OUT"
run_tally "$R21" "$S21" incr seats 2;              ALL="$ALL
$OUT"
run_tally "$R21" "$S21" gate seats;                ALL="$ALL
$OUT"
run_tally "$R21" "$S21" show;                      ALL="$ALL
$OUT"
run_tally "$R21" "$S21" selfcheck;                 ALL="$ALL
$OUT"
assert_not_contains "$ALL" '$' "no \$ anywhere in stdout"
assert_not_contains "$ALL" "USD" "no USD in stdout"
assert_not_contains "$ALL" "cost_usd" "no cost_usd key in stdout"
echo ""

# --- Test 22: orphan-root fallback ---------------------------------------------
# When the state root resolves to the /tmp/soleur-session-state-orphan fallback
# (no git repo), the counters dir gains a -<repo-basename> suffix so repos don't
# collide. Skipped rather than red if the operator already has an orphan root —
# the arm must never disturb real state.
echo "Test 22: orphan fallback appends -<repo-basename> to the counters dir"
ORPHAN="/tmp/soleur-session-state-orphan"
if [[ -e "$ORPHAN" ]]; then
  echo "  SKIP: $ORPHAN already exists — refusing to touch real state"
  SKIPPED=$((SKIPPED + 1))
else
  NG="$TMP/notrepo"
  assert_fixture_dir "$NG"
  mkdir -p "$NG"
  OUT=$(cd "$NG" && unset SOLEUR_SESSION_STATE_ROOT && bash "$SUT" init 2>"$TMP/orphan-stderr")
  RC=$?
  assert_rc0 "init outside a repo exits 0"
  assert_contains "$OUT" "tally-init:" "orphan init still prints the init line"
  assert_contains "$OUT" "HEAD" "detached/non-repo ledger keys on HEAD"
  ORPHANED_LEDGER=$(compgen -G "$ORPHAN/counters-*/HEAD" || true)
  if [[ -n "$ORPHANED_LEDGER" && "$ORPHANED_LEDGER" == *notrepo* ]]; then
    PASS=$((PASS + 1)); echo "  PASS: ledger at counters-<basename>/HEAD ($ORPHANED_LEDGER)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: expected $ORPHAN/counters-*notrepo*/HEAD; got '${ORPHANED_LEDGER:-nothing}'"
    ls -la "$ORPHAN" 2>/dev/null | sed 's/^/    /'
  fi
  rm -rf "$ORPHAN"   # this arm created it — verified absent above
fi
echo ""

# --- Summary -------------------------------------------------------------------
# Anti-vacuity floor: ~106 assertions execute on a full run (flock and orphan
# arms may each skip ~4-5 on hosts lacking flock or with a live orphan root).
print_results 90
