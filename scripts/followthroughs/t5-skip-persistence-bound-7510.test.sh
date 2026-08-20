#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 9 for #7574 — drive the T5 skip-persistence probe against fixture logs.
#
# WHY THE PROBE NEEDED A TEST BEFORE IT NEEDED A FIX. The probe reports PASS on
# a zero count. A zero is also what it reports when it can no longer see the
# thing it counts — so the reassuring answer and the broken instrument are the
# same output. Nothing drove it, so the difference was unobservable.
#
# Measured 2026-08-19 against 20 real logs, every one of which contained the
# suite's terminal line: the probe reported `observed=0` and exited 2. The cause
# is on ONE line — `printf '%s' "$log" | grep -qF "$SUITE_TERMINAL" || continue`
# under `set -o pipefail`. `grep -q` exits on its FIRST match and closes the
# pipe; `printf` then takes SIGPIPE (141); pipefail promotes that to the
# pipeline's status; and `|| continue` fires *because the match succeeded*.
# Twenty broken pipes, `observed` never incremented, and a probe that cannot
# reach any verdict but TRANSIENT.
#
# RED BY DESIGN at the commit that introduces it: (a), (b) and (c) all exit 2
# today. The closer is the next commit.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER, ported from git-data-runcmd-rehearsal.test.sh, whose header
# documents exactly this defect. A verdict computed as `[ "$fails" -eq 0 ]` shares its counter
# with the thing it guards, so ONE token silences the suite: rewrite `fail()` to increment
# `passes` and a real regression reports a full green run at exit 0 (measured). The exit status
# reads a ledger that can only be silenced by DELETING evidence, not by moving a number.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PROBE="$REPO_ROOT/scripts/followthroughs/t5-skip-persistence-bound-7510.sh"
[ -r "$PROBE" ] || { printf 'FAIL: probe not readable at %s\n' "$PROBE" >&2; exit 2; }

SANDBOX=$(mktemp -d -t t5probe.XXXXXXXX) || {
  printf 'FAIL: could not create sandbox\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

TERMINAL_LINE='git-data-runcmd-rehearsal: 44 passed, 0 failed, Skipped: 2 (46 assertions)'

# Builds a fixture CWD with a fake `gh` on PATH.
#   $1 = case name
#   $2 = number of successful runs to report (0 => empty sample)
#   $3 = "missing" to omit gh entirely
#   stdin = the log body every run returns
# THE FIXTURE MUST BE BIGGER THAN THE PIPE BUFFER OR IT CANNOT SEE THE BUG.
# The defect is a SIGPIPE race: `grep -q` exits on its first match and closes
# the pipe, and the producer only notices if it still has data to write. A
# three-line fixture fits entirely inside the 64 KiB pipe buffer, so `printf`
# completes before `grep` ever exits, no SIGPIPE is raised, and the probe passes
# — against an unfixed probe. Measured: the first draft of this harness reported
# 6/7 green with the primary defect fully intact.
#
# Real post-merge logs are megabytes. Every fixture is padded past the buffer so
# the race is genuinely reachable, and the marker lines are placed EARLY so the
# match happens while the producer still has most of its output pending.
PIPE_PAD_LINES=6000
mkcase() {
  local nruns="$2" mode="${3:-present}" root="$SANDBOX/$1"
  mkdir -p "$root/bin"
  cat > "$root/log.head"
  {
    cat "$root/log.head"
    # Padding AFTER the markers: the producer must still be writing when grep
    # exits, which is the whole condition.
    awk -v n="$PIPE_PAD_LINES" 'BEGIN{for(i=0;i<n;i++) print "2026-08-19T00:00:00Z filler log line to push this fixture past the 64KiB pipe buffer " i}'
  } > "$root/log.txt"
  if [ "$mode" != "missing" ]; then
    {
      printf '#!/usr/bin/env bash\n'
      printf 'case "$1" in\n'
      printf '  run)\n'
      printf '    case "$2" in\n'
      printf '      list)\n'
      # Emit $nruns successful entries.
      printf '        printf "["\n'
      printf '        for i in $(seq 1 %s); do\n' "$nruns"
      printf '          [ "$i" -gt 1 ] && printf ","\n'
      printf '          printf "{\\"databaseId\\":%%s,\\"conclusion\\":\\"success\\"}" "$i"\n'
      printf '        done\n'
      printf '        printf "]"\n'
      printf '        ;;\n'
      printf '      view) cat %s ;;\n' "$root/log.txt"
      printf '      *) exit 1 ;;\n'
      printf '    esac ;;\n'
      printf '  *) exit 1 ;;\n'
      printf 'esac\n'
    } > "$root/bin/gh"
    chmod +x "$root/bin/gh"
  fi
  printf '%s' "$root"
}

# PER-CASE STATE, or the cases contaminate each other. The probe now keeps a
# consecutive-TRANSIENT streak in a file; with one shared path, (e), (f) and (g)
# each incremented the SAME counter and (g) escalated to exit 1 on a streak it
# did not earn. That is the probe behaving correctly and the harness measuring
# the wrong thing -- exactly the class this suite exists to catch, one level up.
run_probe() {  # $1 = case root; sets RC and OUT
  OUT="$SANDBOX/out.$RANDOM"
  ( PATH="$1/bin:$PATH" GH_TOKEN=fake T5_PROBE_STATE="$1/streak" bash "$PROBE" ) >"$OUT" 2>&1
  RC=$?
}

expect() {  # $1=case label $2=expected rc $3=why
  if [ "$RC" -eq "$2" ]; then
    pass
  else
    fail "$1: exit $RC, expected $2 — $3. Output: $(head -c 400 "$OUT" | tr '\n' ' ')"
  fi
}

# ── (a) a loud T5 skip must be a FAIL ────────────────────────────────────────
_r=$(mkcase a 20 <<EOF
some preamble
SKIP (loud): T5 MUTATION did not run: the driver never reached the download block
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(a) T5 skip present" 1 "a loud T5 skip is the condition the probe exists to report; today the EPIPE on the terminal-line check drops every log and this returns TRANSIENT instead"

# ── (b) a loud S1 skip must ALSO be a FAIL ───────────────────────────────────
# S1 becomes skip-eligible in #7572, so a probe hard-coded to `T5 MUTATION`
# would go quiet on it. The marker is an enumerated SET, not one literal.
_r=$(mkcase b 20 <<EOF
SKIP (loud): S1 MUTATION did not run: the container never reached the stage
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(b) S1 skip present" 1 "the marker set must cover S1 as well as T5, or the probe goes silent on the arm #7572 makes skip-eligible"

# ── (c) terminal line, no skip => PASS ───────────────────────────────────────
_r=$(mkcase c 20 <<EOF
everything healthy here
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(c) clean window" 0 "20 logs each carrying the suite terminal line and no skip is the healthy case; this is the measured 2026-08-19 sample that returned exit 2 with observed=0"

# ── (d) an UNRELATED loud skip must not fire the alarm ───────────────────────
# infra-config-apply.test.sh emits `SKIP (loud): not root…`. A bare
# `SKIP (loud): ` prefix match would read that as a rehearsal skip and alarm
# forever on a healthy repo.
_r=$(mkcase d 20 <<EOF
SKIP (loud): not root — infra-config-apply.test.sh needs root to bind-mount
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(d) unrelated skip" 0 "a loud SKIP from a different suite must not be counted; the discriminator is the arm name, not the SKIP prefix"

# ── (e) no terminal line => TRANSIENT ────────────────────────────────────────
_r=$(mkcase e 20 <<'EOF'
the rehearsal suite did not run in this window
EOF
)
run_probe "$_r"
expect "(e) suite absent" 2 "without the terminal line the sample is unreadable; a zero count here would be an un-run instrument reporting a clean bill of health"

# ── (f) gh unavailable => TRANSIENT ──────────────────────────────────────────
_r=$(mkcase f 20 missing <<'EOF'
irrelevant
EOF
)
run_probe "$_r"
expect "(f) gh unavailable" 2 "an unreachable gh is not evidence about the skip rate"

# ── (g) zero successful runs => TRANSIENT ────────────────────────────────────
_r=$(mkcase g 0 <<'EOF'
irrelevant
EOF
)
run_probe "$_r"
expect "(g) empty sample" 2 "an empty sample is an un-run instrument, not a clean bill of health"

# ── (h) N consecutive TRANSIENTs must ESCALATE to a FAIL ─────────────────────
# A permanently broken gh auth and a healthy quiet window both exit 2 forever,
# and 2 is the code the carrier reads as "nothing to see". A probe that can
# never reach a verdict must eventually say so, or it is an un-run instrument
# reporting a clean bill of health -- the same defect one level up.
_r=$(mkcase h 0 <<'EOF'
irrelevant
EOF
)
_esc_state="$_r/streak"
_esc_rc=0
for _i in 1 2 3; do
  OUT="$SANDBOX/out.esc.$_i"
  ( PATH="$_r/bin:$PATH" GH_TOKEN=fake T5_PROBE_STATE="$_esc_state" T5_TRANSIENT_ESCALATE_AFTER=3 bash "$PROBE" ) >"$OUT" 2>&1
  _esc_rc=$?
done
if [ "$_esc_rc" -eq 1 ]; then
  pass
else
  fail "(h) transient escalation: the 3rd consecutive TRANSIENT exited $_esc_rc, expected 1 — a probe that cannot reach a verdict must stop being indistinguishable from one that keeps reaching a clean one. Output: $(head -c 300 "$OUT" | tr '\n' ' ')"
fi

# (h.ii) a real verdict must CLEAR the streak, or one bad window poisons the
# counter forever and the next genuine TRANSIENT escalates immediately.
_r2=$(mkcase h2 20 <<EOF
everything healthy here
$TERMINAL_LINE
EOF
)
printf '2' > "$_r2/streak"
( PATH="$_r2/bin:$PATH" GH_TOKEN=fake T5_PROBE_STATE="$_r2/streak" bash "$PROBE" ) >"$SANDBOX/out.h2" 2>&1
if [ ! -s "$_r2/streak" ]; then
  pass
else
  fail "(h.ii) streak not cleared: a PASS left the transient streak at '$(cat "$_r2/streak")'; the next genuine transient would escalate on a streak it did not earn"
fi

# ── Assertion floor (not routed through fail(), deliberately) ────────────────
_total=$((passes + fails))
_FLOOR=9
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d ran, floor %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  exit 1
fi

printf 't5-skip-persistence-bound-7510: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
exit $(( ${#FAILURES[@]} > 0 ))
