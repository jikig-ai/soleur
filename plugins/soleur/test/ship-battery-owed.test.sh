#!/usr/bin/env bash
# Suite for plugins/soleur/skills/ship/scripts/battery-owed.sh (#8247).
#
# This gate decides whether a ~35-minute run happens, so it will be under
# standing pressure to be read generously. Both directions are pinned here, and
# every refusal has its own row: a gate with only must-skip rows passes when it
# is made unconditionally permissive, which is the one mutation that matters.
#
# Fixtures are SYNTHESIZED, never captured (cq-test-fixtures-synthesized-only):
# a throwaway bare repo plus a `gh` stub serving hand-written payloads.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$HERE/test-helpers.sh"

GATE="$HERE/../skills/ship/scripts/battery-owed.sh"
[[ -r "$GATE" ]] || { printf 'FATAL: gate not readable at %s\n' "$GATE" >&2; exit 1; }

OWED=0
SKIPPABLE=1
UNDECIDABLE=2

# --- instrument self-test ----------------------------------------------------
# Drive both dispatch helpers once each before any real row, and refuse to
# continue unless both counters moved. Without this, an edit that neuters
# assert_eq turns the whole suite into a silent pass.
_p0="$PASS"; _f0="$FAIL"
assert_eq "instrument" "instrument" "instrument self-test: the PASS arm records"
assert_eq "a" "b" "instrument self-test: the FAIL arm records (EXPECTED — subtracted below)"
if (( PASS <= _p0 || FAIL <= _f0 )); then
  printf 'FATAL: instrument self-test did not move both counters (PASS %s->%s, FAIL %s->%s).\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 1
fi
FAIL=$(( FAIL - 1 ))   # subtract the deliberate failure

# --- fixture builder ---------------------------------------------------------
# Builds: a bare "origin" with a main branch, a clone on a feature branch whose
# upstream is current. Returns the clone path on stdout.
# `git_fixture_env` EXPORTS into the calling shell and prints nothing; it is
# called directly, never in a command substitution. Each fixture-mutating block
# runs in its own subshell so those exports cannot leak into the gate run.
build_fixture() {
  local root="$1"
  local origin="$root/origin.git" work="$root/work"
  (
    git_fixture_env "$root" || exit 1
    git init --quiet --bare "$origin"
    git clone --quiet "$origin" "$work"
  ) >/dev/null 2>&1 || return 1
  (
    cd "$work" || exit 1
    git_fixture_env "$work" || exit 1
    mkdir -p plugins/soleur
    printf 'seed\n' > README.md
    git add -A
    git commit --quiet -m "seed"
    git branch -M main
    git push --quiet -u origin main
    git checkout --quiet -b feat-fixture
    printf 'change\n' > plugins/soleur/thing.md
    git add -A
    git commit --quiet -m "feature change"
    git push --quiet -u origin feat-fixture
  ) >/dev/null 2>&1 || return 1
  printf '%s\n' "$work"
}

# Run git mutations inside an already-built fixture.
in_fixture() {
  local work="$1"; shift
  ( cd "$work" || exit 1
    git_fixture_env "$work" || exit 1
    "$@" ) >/dev/null 2>&1
}

# --- gh stub -----------------------------------------------------------------
# $1 stub dir, $2 required-contexts JSON array, $3 check-runs JSON array,
# $4 ruleset exit code (default 0).
make_stub() {
  local dir="$1" required="$2" checks="$3" rules_rc="${4:-0}"
  mkdir -p "$dir"
  printf '%s' "$required" > "$dir/required.json"
  printf '%s' "$checks"   > "$dir/checks.json"
  printf '%s' "$rules_rc" > "$dir/rules_rc"
  cat > "$dir/gh" <<'STUB'
#!/usr/bin/env bash
DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
joined="$*"
case "$joined" in
  *rules/branches/main*)
    rc="$(cat "$DIR/rules_rc")"
    [[ "$rc" != "0" ]] && exit "$rc"
    cat "$DIR/required.json"; exit 0 ;;
  *check-runs*)
    # The gate asks for a per-object stream, then jq -s wraps it.
    jq -c '.[]' < "$DIR/checks.json"; exit 0 ;;
  *statuses*)
    exit 0 ;;   # no legacy statuses in these fixtures
esac
echo "gh stub: unhandled '$joined'" >&2
exit 1
STUB
  chmod +x "$dir/gh"
}

run_gate() {
  local work="$1" stub="$2"
  ( cd "$work" || exit 9
    git_fixture_env "$work" || exit 9
    PATH="$stub:$PATH" bash "$GATE" >/dev/null 2>&1 )
  printf '%s' "$?"
}

GREEN_CHECKS='[{"name":"test","status":"completed","conclusion":"success"},{"name":"adr-ordinals","status":"completed","conclusion":"success"}]'
TWO_REQUIRED='["test","adr-ordinals"]'

# =============================================================================
# T1 — the must-SKIP direction. All four conditions hold.
# =============================================================================
ROOT="$(mktemp -d -t battery-owed-XXXXXX)"
WORK="$(build_fixture "$ROOT")"
STUB="$ROOT/stub"; make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS"
assert_eq "$(run_gate "$WORK" "$STUB")" "$SKIPPABLE" \
  "T1 clean tree + pushed + all required green + no infra paths -> SKIPPABLE"

# =============================================================================
# T2 — dirty tree. "CI is green" then describes a different tree.
# =============================================================================
printf 'uncommitted\n' > "$WORK/dirty.txt"
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T2 dirty working tree -> OWED (CI verified a different tree)"
rm -f "$WORK/dirty.txt"

# =============================================================================
# T3 — unpushed commit. HEAD is ahead of what CI saw.
# =============================================================================
in_fixture "$WORK" bash -c 'printf "more\n" > extra.md && git add -A && git commit --quiet -m unpushed'
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T3 unpushed commit -> OWED (CI has not seen this tree)"
in_fixture "$WORK" git push --quiet
assert_eq "$(run_gate "$WORK" "$STUB")" "$SKIPPABLE" \
  "T3b after pushing that commit -> SKIPPABLE again (the refusal was the unpushed state, not the commit)"

# =============================================================================
# T4 — the infra shard. THE LOAD-BEARING REFUSAL.
#
# No required check runs apps/*/infra/** (#6480), so there the battery holds
# unique blocking authority and a skip would delete the only gate. This row is
# why "CI is green -> skip" cannot be the whole rule.
# =============================================================================
in_fixture "$WORK" bash -c 'mkdir -p apps/web-platform/infra && printf "x\n" > apps/web-platform/infra/deploy.sh && git add -A && git commit --quiet -m "infra change" && git push --quiet'
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T4 diff touches apps/*/infra/** -> OWED even with every required check green"

# =============================================================================
# T5 — a required context ABSENT. The non-vacuity row.
#
# Nothing is failing, yet a required context never ran. A failure-only scan
# reports a clean sweep having examined nothing.
# =============================================================================
ROOT2="$(mktemp -d -t battery-owed-XXXXXX)"
WORK2="$(build_fixture "$ROOT2")"
STUB2="$ROOT2/stub"
make_stub "$STUB2" '["test","adr-ordinals","never-ran"]' "$GREEN_CHECKS"
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$OWED" \
  "T5 a required context is ABSENT (nothing failing) -> OWED, not a vacuous skip"

# =============================================================================
# T6 — present but not green.
# =============================================================================
make_stub "$STUB2" "$TWO_REQUIRED" \
  '[{"name":"test","status":"completed","conclusion":"failure"},{"name":"adr-ordinals","status":"completed","conclusion":"success"}]'
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$OWED" \
  "T6 a required context concluded failure -> OWED"

make_stub "$STUB2" "$TWO_REQUIRED" \
  '[{"name":"test","status":"in_progress","conclusion":null},{"name":"adr-ordinals","status":"completed","conclusion":"success"}]'
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$OWED" \
  "T6b a required context still in_progress -> OWED (not-yet-green is not green)"

# =============================================================================
# T7 — the ruleset cannot be read. UNDECIDABLE, never a skip.
# =============================================================================
make_stub "$STUB2" "$TWO_REQUIRED" "$GREEN_CHECKS" 1
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$UNDECIDABLE" \
  "T7 ruleset unreadable -> UNDECIDABLE (caller treats as OWED), never SKIPPABLE"

# =============================================================================
# T8 — an EMPTY required set. Refusing to skip on a vacuous requirement list.
#
# Without this, a ruleset that returns [] would satisfy "every required context
# is green" trivially and hand back SKIPPABLE having verified nothing.
# =============================================================================
make_stub "$STUB2" '[]' "$GREEN_CHECKS"
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$UNDECIDABLE" \
  "T8 zero required contexts -> UNDECIDABLE, never a trivially-satisfied skip"

# =============================================================================
# T9 — no upstream ref at all.
# =============================================================================
ROOT3="$(mktemp -d -t battery-owed-XXXXXX)"
WORK3="$(build_fixture "$ROOT3")"
STUB3="$ROOT3/stub"; make_stub "$STUB3" "$TWO_REQUIRED" "$GREEN_CHECKS"
in_fixture "$WORK3" git checkout --quiet -b never-pushed
assert_eq "$(run_gate "$WORK3" "$STUB3")" "$OWED" \
  "T9 branch has no origin tracking ref -> OWED (nothing pushed for CI to verify)"

# =============================================================================
# T10 — the Grok arm. Redundant with the push-time gate, independent of CI.
#
# Both directions, because the detection has two operands and a one-sided row
# passes when either is made unconditional.
# =============================================================================
ROOT4="$(mktemp -d -t battery-owed-XXXXXX)"
WORK4="$(build_fixture "$ROOT4")"
STUB4="$ROOT4/stub"
# Ruleset deliberately UNREADABLE: proves the Grok skip does not depend on CI.
make_stub "$STUB4" "$TWO_REQUIRED" "$GREEN_CHECKS" 1

run_gate_grok() {
  local work="$1" stub="$2" gate_present="$3"
  ( cd "$work" || exit 9
    git_fixture_env "$work" || exit 9
    if [[ "$gate_present" == "yes" ]]; then
      mkdir -p plugins/soleur/scripts
      printf '#!/usr/bin/env bash\nexit 0\n' > plugins/soleur/scripts/grok-pre-push-gate.sh
    else
      rm -f plugins/soleur/scripts/grok-pre-push-gate.sh
    fi
    GROK_HOME=/fake/grok PATH="$stub:$PATH" bash "$GATE" >/dev/null 2>&1 )
  printf '%s' "$?"
}

assert_eq "$(run_gate_grok "$WORK4" "$STUB4" yes)" "$SKIPPABLE" \
  "T10 Grok harness + pre-push gate present -> SKIPPABLE without consulting CI at all"
assert_eq "$(run_gate_grok "$WORK4" "$STUB4" no)" "$UNDECIDABLE" \
  "T10b Grok harness but NO pre-push gate -> does not fire; falls through to the CI path (here UNDECIDABLE)"

rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4"

# The floor counts the instrument self-test's two rows plus the twelve above.
print_results 14
