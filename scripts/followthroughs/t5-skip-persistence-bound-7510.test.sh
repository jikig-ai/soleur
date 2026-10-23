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

# A FIXTURE, NOT A LIVE EXPECTATION — the probe itself matches only the bare
# `git-data-runcmd-rehearsal:` prefix, so this line's counts are never compared against a real
# run and a suite-count change cannot break these arms. It is refreshed anyway, because a
# fixture modelling an ARITHMETICALLY IMPOSSIBLE run is a trap for the next reader: the
# 44/46/2 triple this replaces was quoted as the live baseline by a later plan, which then
# reasoned from it. That suite hard-exits below 75 assertions, so a 46-assertion run cannot
# occur. Skipped stays NON-ZERO on purpose — this probe is about skip persistence, and a
# fixture with `Skipped: 0` would let the arms pass without exercising the property.
# Re-derived 2026-09-02 against the as-written suite: 75 assertions total (#7570 +3, #7544 +3).
TERMINAL_LINE='git-data-runcmd-rehearsal: 73 passed, 0 failed, Skipped: 2 (75 assertions)'

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
# The pr-quality-guards source fixture: the suite COMPLETION discriminators
# (`=== <basename> done ===`, emitted by run-all.sh after the suite returns)
# are DERIVED from the probe's own discriminator literals so a literal edit
# moves the fixture too. `sed -n '1p'`, not `| head -1`: grep -o into head is
# the SIGPIPE/pipefail shape this file's header exists to document.
BUMP_BANNER=$(grep -oF '=== test-bump-inngest-bootstrap-pin.sh done ===' "$PROBE" | sed -n '1p')
MINT_BANNER=$(grep -oF '=== test-mint-inngest-bootstrap-tag.sh done ===' "$PROBE" | sed -n '1p')
[ -n "$BUMP_BANNER" ] && [ -n "$MINT_BANNER" ] \
  || { printf 'FAIL: could not derive the guard-suite banner literals from %s\n' "$PROBE" >&2; exit 2; }
cat > "$SANDBOX/pg.default.head" <<EOF
guard-script-fixture-tests job output
$BUMP_BANNER
bump suite output
$MINT_BANNER
mint suite output
EOF

# mkcase <name> <iv-run-count> [mode] — stdin is the infra-validation log head.
# The pr-quality-guards source is served too: PG_HEAD_FILE supplies its log head
# (default: both suite banners, no markers) and "$root/pg.n" its run count
# (default 8 — write it after mkcase to change). gh stubs key on --workflow and
# the run-id prefix (9xxx infra-validation, 7xxx pr-quality-guards).
mkcase() {
  local nruns="$2" mode="${3:-present}" root="$SANDBOX/$1"
  mkdir -p "$root/bin"
  cat > "$root/log.iv.head"
  {
    cat "$root/log.iv.head"
    # Padding AFTER the markers: the producer must still be writing when grep
    # exits, which is the whole condition.
    awk -v n="$PIPE_PAD_LINES" 'BEGIN{for(i=0;i<n;i++) print "2026-08-19T00:00:00Z filler log line to push this fixture past the 64KiB pipe buffer " i}'
  } > "$root/log.iv.txt"
  {
    cat "${PG_HEAD_FILE:-$SANDBOX/pg.default.head}"
    awk -v n="$PIPE_PAD_LINES" 'BEGIN{for(i=0;i<n;i++) print "2026-08-19T00:00:00Z filler log line to push this fixture past the 64KiB pipe buffer " i}'
  } > "$root/log.pg.txt"
  printf '8\n' > "$root/pg.n"
  if [ "$mode" != "missing" ]; then
    {
      printf '#!/usr/bin/env bash\n'
      printf 'wf=""; pos=""; prev=""\n'
      printf 'for a in "$@"; do\n'
      printf '  case "$prev" in --workflow) wf="$a";; esac\n'
      printf '  case "$a" in [0-9]*) pos="$a";; esac\n'
      printf '  prev="$a"\n'
      printf 'done\n'
      printf 'case "$2" in\n'
      printf '  list)\n'
      printf '    case "$wf" in\n'
      printf '      *infra-validation*) base=9000; n=%s ;;\n' "$nruns"
      printf '      *pr-quality-guards*) base=7000; n=$(cat %s 2>/dev/null || echo 0) ;;\n' "$root/pg.n"
      printf '      *) n=0 ;;\n'
      printf '    esac\n'
      printf '    printf "["\n'
      printf '    for i in $(seq 1 "$n"); do\n'
      printf '      [ "$i" -gt 1 ] && printf ","\n'
      printf '      printf "{\\"databaseId\\":%%s,\\"conclusion\\":\\"success\\"}" "$((base+i))"\n'
      printf '    done\n'
      printf '    printf "]"\n'
      printf '    ;;\n'
      printf '  view) case "$pos" in 9*) cat %s ;; 7*) cat %s ;; *) exit 1 ;; esac ;;\n' "$root/log.iv.txt" "$root/log.pg.txt"
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
run_probe() {  # $1 = case root, $2 = optional probe file (default $PROBE); sets RC and OUT
  OUT="$SANDBOX/out.$RANDOM"
  ( PATH="$1/bin:$PATH" GH_TOKEN=fake T5_PROBE_STATE="$1/streak" bash "${2:-$PROBE}" ) >"$OUT" 2>&1
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

# ── (i) a loud T17 skip must ALSO be a FAIL ──────────────────────────────────
# Same reason as (b), one arm later. #7535 Phase 2 makes the T17 mutation arm
# skip-eligible by replacing the `|| true` that discarded its container rc, so a
# marker set covering only T5 and S1 would go silent on the arm that change
# creates -- and the suite's own roster guard (_PROBE_NAMED vs _SKIP_CALL_SITES)
# would still be satisfied by arithmetic, because it counts names rather than
# checking this file. This case is what actually holds the two in step.
_r=$(mkcase i 20 <<EOF
SKIP (loud): T17 MUTATION did not run: apt starved before the mutant executed
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(i) T17 skip present" 1 "the marker set must cover T17 as well as T5 and S1, or the probe goes silent on the arm #7535 Phase 2 makes skip-eligible"

# ── (j) the xtrace credential refusal must fire, and ONLY with a credential ──
# The probe binds GH_TOKEN, and `set -x` expands the `gh` invocations carrying it
# into a log that lands in a public Actions run. The guard must be conditional on
# the credential rather than a blanket xtrace ban, or it would break tracing as a
# debugging tool for every non-credentialed run.
( GH_TOKEN=fake bash -x "$PROBE" ) >"$SANDBOX/out.xtrace" 2>&1
_xt_rc=$?
if [ "$_xt_rc" -eq 78 ]; then pass; else
  fail "(j) xtrace refusal: traced with GH_TOKEN set exited $_xt_rc, expected 78 — the probe would have expanded its gh calls, token included, into a public run log"
fi
( env -u GH_TOKEN bash -x "$PROBE" ) >"$SANDBOX/out.xtrace.notok" 2>&1
_xt_rc2=$?
if [ "$_xt_rc2" -ne 78 ]; then pass; else
  fail "(j.ii) xtrace refusal is unconditional: traced WITHOUT a credential also exited 78; the guard must key on the credential, not on xtrace alone"
fi

# ── (k) END TO END: the REAL runner's stdout, fed to the probe (#10786) ──────
# The probe reads the Actions log of infra-validation.yml. Since #8763 the rehearsal suite runs inside
# apps/web-platform/infra/run-registered-suites.sh, which (since #7423) captures each suite's output
# into a per-suite file and prints only `PASS <path>`; the suite's `SKIP (loud):` lines and terminal
# summary never reached the log, and the probe was TRANSIENT from 2026-09-28 on. The runner now
# relays them as `SOLEUR| relay <basename>: <line>`. These rows run the REAL runner over a fixture
# infra dir and feed ITS stdout to the probe, so the three-way contract (suite text, runner relay,
# probe literal) cannot drift apart silently a second time.
#
# The fixture text is DERIVED from this probe's own literals, not hand-copied: a probe literal edit
# moves the fixture, and the (hard-coded) runner regex then no longer matches it, which reddens.
# That holds for the TERMINAL line only: the skip fixture is built from the probe's T5 marker, which
# always matches the runner's generic skip prefix, so the skip end of the pair is pinned separately,
# by value, against the real suite's own `arm_skip` echo (the "suite end (skip)" row below).
RUNNER="$REPO_ROOT/apps/web-platform/infra/run-registered-suites.sh"
SUITE_SRC="$REPO_ROOT/apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh"
[ -x "$RUNNER" ] || { printf 'FAIL: runner not executable at %s\n' "$RUNNER" >&2; exit 2; }

# $1 = probe file to read the literals from. Prints: SUITE_TERMINAL, then the T5 marker (the sed is
# keyed on that literal, not on array position).
probe_literals() {
  local f="$1" term mark
  term=$(sed -n "s/^SUITE_TERMINAL='\\(.*\\)'\$/\\1/p" "$f" | sed -n '1p')
  mark=$(sed -n "s/^  '\\(SKIP (loud): T5 \\)'\$/\\1/p" "$f" | sed -n '1p')
  [ -n "$term" ] && [ -n "$mark" ] || return 1
  printf '%s\n%s\n' "$term" "$mark"
}

# k_case <name> <variant> <probe file> <runner file>; sets RC/OUT via run_probe, RUNNER_LOG for the
# precondition. Variants: skip (skip line + terminal), terminal (terminal only), neither.
k_case() {
  local name="$1" variant="$2" pfile="$3" rfile="$4" fx="$SANDBOX/kfix.$1" lits term mark
  lits=$(probe_literals "$pfile") || { fail "(k) $name: could not read the probe literals from $pfile"; RC=99; return 0; }
  term=$(sed -n '1p' <<<"$lits"); mark=$(sed -n '2p' <<<"$lits")
  mkdir -p "$fx"
  {
    printf '#!/usr/bin/env bash\n'
    [ "$variant" = skip ] && printf 'echo %q >&2\n' "${mark}MUTATION fixture skip"
    [ "$variant" != neither ] && printf 'echo %q\n' "${term} 73 passed, 0 failed, Skipped: 2 (75 assertions)"
    printf 'exit 0\n'
  } > "$fx/git-data-runcmd-rehearsal.test.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fx/second.test.sh"
  chmod +x "$fx"/*.test.sh
  RUNNER_LOG="$SANDBOX/kout.$name"
  ( cd "$REPO_ROOT" && SOLEUR_INFRA_DIR="$fx" timeout 120 bash "$rfile" ) > "$RUNNER_LOG" 2>&1 || true
  local root; root=$(mkcase "k.$name" 20 < "$RUNNER_LOG")
  run_probe "$root" "$pfile"
}

k_case skip skip "$PROBE" "$RUNNER"
_k_relays=$(grep -cE '^SOLEUR\| relay git-data-runcmd-rehearsal\.test\.sh: SKIP \(loud\): T5 ' "$RUNNER_LOG" || true)
if [ "$_k_relays" -ge 1 ]; then pass; else
  fail "(k) precondition: the runner's own stdout carries ${_k_relays} relayed T5 skip line(s) — the probe is being fed a log the runner never produced evidence into"
fi
expect "(k) skip via the real runner" 1 "a loud skip the suite prints must survive the runner's per-suite capture and reach the probe; this is the exit-2 TRANSIENT of 2026-09-28 onwards"

k_case terminal terminal "$PROBE" "$RUNNER"
expect "(k) terminal line via the real runner" 0 "the suite's terminal line must survive the runner's capture, or the positive control reads every run as unreadable"

k_case neither neither "$PROBE" "$RUNNER"
expect "(k) neither line via the real runner" 2 "a suite that printed no evidence at all is an unreadable sample, never a clean bill of health"

# The pre-fix production shape, verbatim from main run 39612112094: the runner printed ONLY the
# PASS line for the rehearsal suite. The probe must keep refusing a verdict on it (exit 2).
_r=$(mkcase kpre 20 <<'EOF'
PASS apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
EOF
)
run_probe "$_r"
expect "(k) pre-fix log shape" 2 "a log carrying only the runner's PASS line has no evidence; the probe must stay TRANSIENT on it rather than report a skip count of zero"

# The suite end of the pin, by VALUE: expand the real suite's terminal `echo` with sample numbers
# and match it against the regex the RUNNER relays on. A wording or separator edit that keeps the
# statement but misses the regex reddens here, where a presence check would stay green.
_term_stmt=$(grep -E '^echo "git-data-runcmd-rehearsal: ' "$SUITE_SRC" || true)
_term_n=$(grep -c . <<<"$_term_stmt" || true)
_ere=$(sed -n "s/^EVIDENCE_TERMINAL_ERE='\\(.*\\)'\$/\\1/p" "$RUNNER" | sed -n '1p')
if [ "$_term_n" -eq 1 ] && [ -n "$_ere" ]; then
  _expanded=${_term_stmt#echo \"}; _expanded=${_expanded%\"}
  _expanded=${_expanded//'${passes}'/73}; _expanded=${_expanded//'${fails}'/0}
  _expanded=${_expanded//'${SKIPPED_ASSERTIONS}'/2}; _expanded=${_expanded//'${total}'/75}
  case "$_expanded" in
    *'$'*) fail "(k) suite end: the terminal echo still has an unexpanded variable after substituting the four known ones: $_expanded" ;;
    *) if grep -Eq -- "$_ere" <<<"$_expanded"; then pass; else
         fail "(k) suite end: the real suite's terminal line '$_expanded' no longer matches the runner's EVIDENCE_TERMINAL_ERE '$_ere' — the runner would stop relaying it and the probe would go TRANSIENT again"
       fi ;;
  esac
else
  fail "(k) suite end: found ${_term_n} terminal echo statement(s) in the rehearsal suite and regex '${_ere}' in the runner, expected exactly 1 and a non-empty regex"
fi

# The suite end of the SKIP contract, by VALUE: expand the real `arm_skip` emitter with a T5 name and
# require that the result (a) matches the runner's relay regex and (b) contains the probe's own T5
# marker. Without this the prefix text `SKIP (loud): ` is pinned only by hand-written fixtures, and a
# one-word edit to the real emitter zeroes the relay and the probe while the terminal-line positive
# control keeps reporting a healthy PASS.
_skip_stmt=$(grep -oF 'echo "SKIP (loud): $1" >&2' "$SUITE_SRC" || true)
_skip_n=$(grep -c . <<<"$_skip_stmt" || true)
_skip_ere=$(sed -n "s/^EVIDENCE_SKIP_ERE='\\(.*\\)'\$/\\1/p" "$RUNNER" | sed -n '1p')
_lits=$(probe_literals "$PROBE") || _lits=""
_t5=$(sed -n '2p' <<<"$_lits")
if [ "$_skip_n" -eq 1 ] && [ -n "$_skip_ere" ] && [ -n "$_t5" ]; then
  _sx=${_skip_stmt#*echo \"}; _sx=${_sx%%\" >&2*}
  _sx=${_sx//'$1'/"${_t5#SKIP (loud): }MUTATION sample"}
  case "$_sx" in
    *'$'*) fail "(k) suite end (skip): the arm_skip echo still has an unexpanded variable after substituting \$1: $_sx" ;;
    *) if grep -Eq -- "$_skip_ere" <<<"$_sx" && grep -qF -- "$_t5" <<<"$_sx"; then pass; else
         fail "(k) suite end (skip): the real arm_skip output '$_sx' no longer matches the runner's EVIDENCE_SKIP_ERE '$_skip_ere' and the probe's T5 marker '$_t5' — the relay and the probe would both go blind to every real skip"
       fi ;;
  esac
else
  fail "(k) suite end (skip): found ${_skip_n} arm_skip echo statement(s), regex '${_skip_ere}', marker '${_t5}' — expected exactly 1, and both non-empty"
fi

# Edit-the-pair harness: a mutation to ONE end of the pair must turn the terminal-only case from 0
# into something else. The runner suite's T9 mutates only the runner copy and greps its own output,
# so it cannot score an edit to the PROBE literal; this can.
for _mut in probe-literal runner-regex; do
  _mp="$SANDBOX/mut.$_mut.probe.sh"; _mr="$SANDBOX/mut.$_mut.runner.sh"
  cp "$PROBE" "$_mp"; cp "$RUNNER" "$_mr"; chmod +x "$_mr"
  case "$_mut" in
    probe-literal) sed -i "s/^SUITE_TERMINAL='git-data-runcmd-rehearsal:'/SUITE_TERMINAL='git-data-runcmd-rehearsal-moved:'/" "$_mp" ;;
    runner-regex)  sed -i "s/^EVIDENCE_TERMINAL_ERE='\\^git-data-runcmd-rehearsal:/EVIDENCE_TERMINAL_ERE='^git-data-runcmd-rehearsal-moved:/" "$_mr" ;;
  esac
  if cmp -s "$PROBE" "$_mp" && cmp -s "$RUNNER" "$_mr"; then
    fail "(k) harness[$_mut]: the mutation did not land — this row proves nothing"
    continue
  fi
  k_case "mut.$_mut" terminal "$_mp" "$_mr"
  if [ "$RC" -eq 2 ]; then pass; else
    fail "(k) harness[$_mut]: an edit to one end of the probe/runner pair left the terminal-only case at exit $RC, expected 2 (TRANSIENT: the positive control lost the evidence) — the pin does not hold"
  fi
done
# The unmutated control through the SAME copy path must read 0, or the rows above prove only that
# copying a file breaks it.
cp "$PROBE" "$SANDBOX/mut.control.probe.sh"; cp "$RUNNER" "$SANDBOX/mut.control.runner.sh"; chmod +x "$SANDBOX/mut.control.runner.sh"
k_case "mut.control" terminal "$SANDBOX/mut.control.probe.sh" "$SANDBOX/mut.control.runner.sh"
expect "(k) harness control" 0 "an unmutated copy of the pair through the harness's own copy path must read exit 0, or the mutation rows prove nothing"

# ── (l) a loud g1b. guard-suite skip must be a FAIL (#10921) ─────────────────
# The second run-source samples pr-quality-guards.yml by event; the bump
# suite's corrupt-walk rows emit `SKIP (loud): g1b.`/`g2b.` markers.
PG_HEAD_FILE="$SANDBOX/pg.g1b.head"
{
  printf '%s\n' "$BUMP_BANNER"
  printf 'SKIP (loud): g1b.B7 runner git does not exhibit the non-empty-stderr corrupt-walk contract\n'
  printf '%s\n' "$MINT_BANNER"
} > "$PG_HEAD_FILE"
_r=$(mkcase l 20 <<EOF
everything healthy here
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(l) g1b. guard skip present" 1 "a loud g1b. skip in pr-quality-guards logs is the condition the second source exists to report"

# ── (m) a loud fl. guard-suite skip must ALSO be a FAIL ──────────────────────
PG_HEAD_FILE="$SANDBOX/pg.fl.head"
{
  printf '%s\n' "$BUMP_BANNER"
  printf '%s\n' "$MINT_BANNER"
  printf 'SKIP (loud): fl.walk runner git does not exhibit the non-empty-stderr corrupt-walk contract\n'
} > "$PG_HEAD_FILE"
_r=$(mkcase m 20 <<EOF
everything healthy here
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(m) fl. guard skip present" 1 "a loud fl. skip in pr-quality-guards logs must fire — the marker set is not bump-only"

# ── (n) guard logs without the suite banners => TRANSIENT, never pooled ──────
# The clean infra-validation source must NOT pool into the unreadable
# pr-quality-guards source: per-source observed >= 1 is required independently.
PG_HEAD_FILE="$SANDBOX/pg.nobanners.head"
printf 'guard-script-fixture-tests job output with no suite banners\n' > "$PG_HEAD_FILE"
_r=$(mkcase n 20 <<EOF
everything healthy here
$TERMINAL_LINE
EOF
)
run_probe "$_r"
expect "(n) guard suites unobserved" 2 "a source whose discriminators are absent in every sampled log is unreadable; a clean other-source reading must not pool into a PASS"
unset PG_HEAD_FILE

# ── (o) a guard hit counts even when the OTHER source is unreadable ──────────
# FAIL dominates over TRANSIENT across sources.
PG_HEAD_FILE="$SANDBOX/pg.hit.head"
{
  printf '%s\n' "$BUMP_BANNER"
  printf 'SKIP (loud): g2b.I6 runner git does not exhibit the merge-base corrupt-walk contract\n'
  printf '%s\n' "$MINT_BANNER"
} > "$PG_HEAD_FILE"
_r=$(mkcase o 20 <<'EOF'
the rehearsal suite did not run in this window
EOF
)
run_probe "$_r"
expect "(o) guard hit + rehearsal unobserved" 1 "a marker in one observed source is a real verdict; the other source's unreadability cannot downgrade it"
unset PG_HEAD_FILE

# ── (p) roster parity: every enumerated guard prefix has a producer ──────────
# (AC8b) For each `SKIP (loud): <prefix>` the probe enumerates for the guard
# suites, at least one `corrupt_skip '<prefix>...' call site must exist in
# .github/scripts/test/ — a prefix with no producer is dead enumeration, and a
# producer with no prefix is invisible to the monitor (the suites' own
# roster-parity self-checks cover the other direction).
_guard_prefixes=$(grep -oE "SKIP \(loud\): [a-z0-9]+\." "$PROBE" | sed 's/SKIP (loud): //' | sort -u)
_p_missing=""
for _pfx in $_guard_prefixes; do
  # EXCLUDING captured-selftest producers: the suites' own selftest rows name
  # *.selftest-* and emit only into files — a prefix satisfied only by them
  # produces nothing the monitor can ever see (the suites' own roster checks
  # assert the same exclusion the other direction).
  grep -rE "corrupt_skip[[:space:]]+'${_pfx//./\\.}[^']*'" "$REPO_ROOT/.github/scripts/test/" \
    | grep -v 'selftest' | grep -q . \
    || _p_missing="$_p_missing $_pfx"
done
if [ -z "$_p_missing" ]; then pass; else
  fail "(p) roster parity: probe-enumerated prefix(es) with no non-selftest corrupt_skip producer in .github/scripts/test/:$_p_missing"
fi

# ── (q) the lib's emitted marker literal is pinned to the probe's literals ──
# The probe greps `SKIP (loud): g1b.`/`g2b.`/`fl.` from corrupt_skip's printf;
# NOTHING else pins that literal for the guard source — one printf edit in
# git-corrupt-graph.sh silently unobserves every guard-suite skip while the
# done-line discriminators keep the source "observed" → green unobservation.
CORRUPT_LIB="$REPO_ROOT/plugins/soleur/test/lib/git-corrupt-graph.sh"
if grep -qF "printf 'SKIP (loud): %s %s\\n'" "$CORRUPT_LIB"; then pass; else
  fail "(q) marker literal: git-corrupt-graph.sh no longer emits the exact 'SKIP (loud): %s %s\\n' the probe greps — an edit to the literal is a RED here, not silent unobservation"
fi

# ── Assertion floor (not routed through fail(), deliberately) ────────────────
# RAISED 9 -> 12 (#7535 Phase 2), ITEMISED: (i) the T17 marker registration, plus
# (j) and (j.ii), the two directions of the xtrace credential refusal.
# RAISED 12 -> 20 (#10786), ITEMISED: (k) has 8 assertions: the relay-line precondition, three real-runner
# cases (skip, terminal only, neither), the pre-fix log shape, the suite-end value pin, and the two
# edit-the-pair harness rows (probe literal, runner regex). Measured on the green run: 20.
# RAISED 20 -> 22 after review (#10786), ITEMISED: the skip-side value pin against the real `arm_skip`
# echo, and the unmutated control through the harness's own copy path. Measured: 22.
# RAISED 22 -> 27 (#10921), ITEMISED: (l) g1b. marker -> FAIL, (m) fl. marker -> FAIL, (n) guard
# discriminators absent -> TRANSIENT (per-source, never pooled), (o) guard hit + rehearsal
# unobserved -> FAIL dominates, (p) roster parity (every enumerated guard prefix has a producer).
# Measured on the green run: 27.
# RAISED 27 -> 28 (#10921 fix round), ITEMISED: (q) the lib's `SKIP (loud):`
# printf literal is pinned by value — an edit to it unobserves every guard-suite
# skip while banners keep the source "observed". Measured on the green run: 28.
_total=$((passes + fails))
_FLOOR=28
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d ran, floor %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  exit 1
fi

printf 't5-skip-persistence-bound-7510: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
exit $(( ${#FAILURES[@]} > 0 ))
