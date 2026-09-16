#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/cloud-mode-postmerge-evidence-8159.sh.
#
# Registered EXPLICITLY in scripts/test-all.sh: scripts/followthroughs/ matches
# no SUITE_GLOBS entry, so an unregistered .test.sh is an orphan that never
# gates (the #5417 class).
#
# WHAT THIS PINS. The probe is notify-only: exit 5 = ACTION REQUIRED, 2 = NOT
# YET, 3 = CANNOT ESTABLISH, and 0/1 must NEVER be produced (0 is the sweeper's
# close verb on a feature issue whose close is an operator judgement; 1 is the
# FAIL/reopen verb). followthrough-convention.md: "an exit-code contract
# nothing drives is a comment" — this suite is what drives it.
#
# FIXTURE SHAPE. The probe derives REPO_ROOT from its own location and reads
# $REPO_ROOT/knowledge-base/project/specs/feat-devin-cloud-session-parity/
# cloud-probe.md, so each arm copies the SUT into a synthetic tree's
# scripts/followthroughs/ and writes only the probed file.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/cloud-mode-postmerge-evidence-8159.sh"
PROBE_REL="knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Instrument self-test: both counters must move before any verdict is trusted.
_p0=$total; pass "instrument" >/dev/null; _f0=$fails
fail "instrument" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

WORK="$(mktemp -d -t cmpm-8159.XXXXXXXX)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# Build a fixture tree: SUT at scripts/followthroughs/, probe file written by
# the caller under $PROBE_REL. Echoes the fixture root for the caller to use.
new_tree() {
  local t="$WORK/$1"
  mkdir -p "$t/scripts/followthroughs" "$t/$(dirname "$PROBE_REL")"
  cp "$SUT" "$t/scripts/followthroughs/"
  printf '%s\n' "$t"
}

# run_probe <fixture-root> — executes the copied SUT, captures rc.
run_probe() {
  bash "$1/scripts/followthroughs/cloud-mode-postmerge-evidence-8159.sh" >/dev/null 2>&1
  echo $?
}

# assert_rc <name> <expected> <actual>
assert_rc() {
  if [[ "$3" == "$2" ]]; then pass "$1 (rc=$3)"; else fail "$1 (expected rc=$2, got $3)"; fi
}

# assert_never_close_verbs <name> <rc> — 0 and 1 are the sweeper's close/fail
# verbs; this probe must never produce either, on ANY arm.
assert_never_close_verbs() {
  case "$2" in
    0|1) fail "$1 produced forbidden exit $2 (close/fail verb)" ;;
    *)   pass "$1 avoided close/fail verbs (rc=$2)" ;;
  esac
}

# --- Arm 1: full evidence -> 5 --------------------------------------------
T1=$(new_tree t1)
cat > "$T1/$PROBE_REL" <<'EOF'
## Deferral record
- post-merge SC1/SC3/SC4 verification session.

## Post-merge verification (2026-09-20, session xyz)

- SC1: VERIFIED — banner emitted, sequential fallback disclosed.
- SC3: VERIFIED — ack gate stalled unanswered.
- SC4: VERIFIED — skills loaded via requiredPlugins.
EOF
rc=$(run_probe "$T1"); assert_rc "full evidence -> ACTION REQUIRED" 5 "$rc"
assert_never_close_verbs "arm1" "$rc"

# --- Arm 2: partial evidence (missing SC4) -> 2 ----------------------------
T2=$(new_tree t2)
cat > "$T2/$PROBE_REL" <<'EOF'
## Post-merge verification (2026-09-20)

- SC1: VERIFIED
- SC3: VERIFIED
EOF
rc=$(run_probe "$T2"); assert_rc "partial evidence -> NOT YET" 2 "$rc"
assert_never_close_verbs "arm2" "$rc"

# --- Arm 3: deferral prose names the SCs but no heading -> 2 ---------------
# The false-positive guard: a whole-file grep would fire 5 on this content.
T3=$(new_tree t3)
cat > "$T3/$PROBE_REL" <<'EOF'
## Deferral record
- post-merge SC1/SC3/SC4 verification session.
EOF
rc=$(run_probe "$T3"); assert_rc "deferral prose only -> NOT YET" 2 "$rc"
assert_never_close_verbs "arm3" "$rc"

# --- Arm 4: fenced fake evidence block -> 2 --------------------------------
# A fenced TEMPLATE naming the tokens is documentation, not a verdict. The
# awk fence-toggle is what keeps this from firing ACTION REQUIRED.
T4=$(new_tree t4)
cat > "$T4/$PROBE_REL" <<'OUTER'
## Checklist

```markdown
## Post-merge verification
- SC1: VERIFIED
- SC3: VERIFIED
- SC4: VERIFIED
```
OUTER
rc=$(run_probe "$T4"); assert_rc "fenced template -> NOT YET" 2 "$rc"
assert_never_close_verbs "arm4" "$rc"

# --- Arm 5: missing file -> 3 ----------------------------------------------
T5=$(new_tree t5)
rc=$(run_probe "$T5"); assert_rc "missing file -> CANNOT ESTABLISH" 3 "$rc"
assert_never_close_verbs "arm5" "$rc"

# --- Arm 6: directory at probe path -> 3 ------------------------------------
# `-f` is the contract: a non-regular file must not reach the awk read (a FIFO
# would block the whole sequential sweep).
T6=$(new_tree t6)
mkdir "$T6/$PROBE_REL"
rc=$(run_probe "$T6"); assert_rc "directory at probe path -> CANNOT ESTABLISH" 3 "$rc"
assert_never_close_verbs "arm6" "$rc"

# --- Arm 7: symlink to a FIFO -> 3 ------------------------------------------
T7=$(new_tree t7)
mkfifo "$WORK/fifo7" && ln -s "$WORK/fifo7" "$T7/$PROBE_REL"
rc=$(run_probe "$T7"); assert_rc "symlink-to-FIFO -> CANNOT ESTABLISH" 3 "$rc"
assert_never_close_verbs "arm7" "$rc"

# --- Arm 8: unexpected argv -> 64 -------------------------------------------
"$SUT" --bogus >/dev/null 2>&1; rc=$?
assert_rc "argv -> usage" 64 "$rc"
assert_never_close_verbs "arm8" "$rc"

# --- Arm 9: toolchain absent -> 3 -------------------------------------------
# Restricted PATH: dirname fails too, but every route lands on CANNOT
# ESTABLISH — never NOT YET — for a measurement that could not run.
T9=$(new_tree t9)
cat > "$T9/$PROBE_REL" <<'EOF'
## Post-merge verification
- SC1: VERIFIED
- SC3: VERIFIED
- SC4: VERIFIED
EOF
mkdir -p "$WORK/emptybin"
rc=$(env -i PATH="$WORK/emptybin" "$(command -v bash)" "$T9/scripts/followthroughs/cloud-mode-postmerge-evidence-8159.sh" >/dev/null 2>&1; echo $?)
assert_rc "no toolchain -> CANNOT ESTABLISH" 3 "$rc"
assert_never_close_verbs "arm9" "$rc"

# ---------------------------------------------------------------------------
printf '\ncloud-mode-postmerge-evidence-8159.test.sh: %d checks, %d failed\n' "$total" "$fails"
[[ "$fails" -eq 0 ]] || exit 1

# Anti-vacuity floor: the suite is worthless if the arms silently dropped.
# Literal bound kept adjacent so guard-vacuity-floor's mutation machinery can
# construct the mutant (printf+exit 1, never fail()).
CMPM_MIN_ASSERTIONS=16
if (( total < CMPM_MIN_ASSERTIONS )); then
  printf '[FATAL] anti-vacuity floor: only %d assertions ran (floor %d)\n' "$total" "$CMPM_MIN_ASSERTIONS" >&2
  exit 1
fi
echo "cloud-mode-postmerge-evidence-8159.test.sh: all checks passed"
exit 0
