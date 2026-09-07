#!/usr/bin/env bash
# Suite for .claude/hooks/memory-backstop.sh (#7166).
#
# TWO ARMS.
#   * pure-fixture — always runs, including CI, Docker, macOS, non-systemd Linux.
#   * live         — needs a per-user systemd bus. SKIPPED loudly otherwise, and
#                    the RESULT: line carries [live: yes|SKIPPED] plus the number
#                    of assertions that did not run. A permanently-skipped live
#                    arm must be VISIBLE, not silently green: the assertions that
#                    matter most here are the ones CI cannot run.
#     Every live test MARKS itself when it runs, skips mark the same label, and a
#     final reconciliation names any label that did neither — so a DELETED live
#     test is distinguishable from a skipped one. (A count-vs-count check is not:
#     the previous form stayed green with the whole live arm removed.)
#
# NO INJECTION SEAMS. The hook exposes functions and runs `main` only when
# executed (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`), so this suite sources it and
# calls functions with ordinary arguments. Where a test needs to point a function
# at synthetic state it passes a PATH ARGUMENT (a fake /proc root, a fake
# memory.events file) — never an environment variable. #7151 shipped
# SOLEUR_MEMORY_CAP_PID and SOLEUR_MEMORY_CAP_BYTES as production-readable test
# seams; `_BYTES=0` was a one-token session kill. Those defects are not defended
# against here, they are unrepresentable.
#
# NAMESPACING. Every unit this suite creates is `soleurtest-*` inside
# `soleurtest-agents.slice`, so the suite can never mutate the production slice.
# Teardown is trap-based and stops every unit created and removes every drop-in.
#
# ORDERING IS DELIBERATE. The end-to-end exec of the REAL hook against the
# PRODUCTION slice runs LAST, after the pure-fixture arm has validated the
# identity walk and cap bands and after the AC7 sweep has run. Running it first
# would exec an unvalidated identity walk against real PIDs with production caps
# — the same hazard that moved settings.json wiring to the end of the plan.
#
# SIDE EFFECT, STATED: on a host with a user bus, the end-to-end test adopts the
# running agent session into a capped scope. That is the feature working as
# designed and it is idempotent; `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` opts out.

# shellcheck disable=SC2154  # newtmp assigns via `printf -v`; shellcheck cannot
# see indirect assignment and reports every such variable as "referenced but not
# assigned". The alternative (`x=$(mktmp)`) is the subshell-append leak this file
# exists to avoid.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Applied to EVERY hook suite, not just ones whose hook is a sibling .sh:
# security_reminder_hook is a .py, so pairing by filename missed it and it
# kept writing the real ledger. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

cd "$(git rev-parse --show-toplevel)" || exit 2

HOOK=".claude/hooks/memory-backstop.sh"
SETTINGS=".claude/settings.json"
TEST_SLICE="soleurtest-agents.slice"
UIDN=$(id -u)
export TMPDIR="${TMPDIR:-/var/tmp}"

fails=0
passes=0
skipped_live=0

# DERIVED live-arm ledger, not a declared integer.
#
# The previous form compared LIVE_TEST_COUNT=12 against a hand-written list of 12
# skip names — two literals, neither referencing a single live assertion, so the
# reconciliation was `12 == 12`. Measured: deleting the ENTIRE 437-line live arm
# left it green and printing "skip count matches the 12 declared live tests".
#
# Now every live test must MARK itself when it runs, and skips mark the same
# label. A deleted test is therefore neither seen nor skipped, and the final
# reconciliation names it. This runs on EVERY path, including LIVE=yes, so the
# detached shape is covered too — it previously had no bookkeeping at all.
LIVE_LABELS=(
  T8-adoption T9-tree-adoption T9-grandchild T10-ac7-sweep
  T11-bindsto-reap T12-fleet-two-sessions T13-managed-oom-pref
  T14-kill-mechanism T15-idempotency T15-terminal-scope-stable
  T18-documented-kill-path AC18-reentry-resweep
)
declare -A LIVE_SEEN=()
live_mark() { LIVE_SEEN["$1"]=1; }

pass() { printf '  ✓ %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }
skip() { printf '  ~ SKIP %s (%s)\n' "$1" "${2:-skipped}"; live_mark "$1"; skipped_live=$((skipped_live + 1)); }

SPAWNED=()
SCOPES=()
TMPDIRS=()

teardown() {
  local u p d
  for u in "${SCOPES[@]:-}"; do [[ -n "$u" ]] && systemctl --user stop "$u" >/dev/null 2>&1; done
  systemctl --user stop "$TEST_SLICE" >/dev/null 2>&1
  systemctl --user stop "soleurtest.slice" >/dev/null 2>&1
  for p in "${SPAWNED[@]:-}"; do [[ -n "$p" ]] && kill "$p" >/dev/null 2>&1; done
  find "$HOME/.config/systemd/user.control" -path '*soleurtest-*' -delete 2>/dev/null
  find "/run/user/$UIDN/systemd/user.control" -path '*soleurtest-*' -delete 2>/dev/null
  for d in "${TMPDIRS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done
  return 0
}
trap teardown EXIT INT TERM HUP

# Assigns to the NAMED variable in the caller's scope and registers the directory
# for teardown. Deliberately NOT `d=$(mktmp)`: command substitution runs the
# function in a SUBSHELL, so a `TMPDIRS+=(...)` inside it mutates a copy that is
# discarded — the parent array stays empty and the EXIT trap owns nothing, leaking
# a temp dir per call. (The repo lints for exactly this shape; see #6734.)
newtmp() {
  local __var=$1 __d
  __d=$(mktemp -d -t membackstop.XXXXXXXX) || return 1
  TMPDIRS+=("$__d")
  printf -v "$__var" '%s' "$__d"
}

echo "memory-backstop: hook contract, fail-open branches, tree adoption, cap enforcement"

if [[ ! -f "$HOOK" ]]; then
  fail "$HOOK does not exist"
  echo "RESULT: FAILED $fails [live: n/a]" >&2
  exit 1
fi

# ---------------------------------------------------------------- live gate
LIVE=no
BUS="${XDG_RUNTIME_DIR:-/run/user/$UIDN}/bus"
if [[ -S "$BUS" ]] && command -v busctl >/dev/null 2>&1 \
  && busctl --user --no-pager status >/dev/null 2>&1; then
  LIVE=yes
fi

# Source the hook. This must NOT execute main.
# shellcheck source=/dev/null
source "$HOOK" || { fail "sourcing $HOOK failed"; echo "RESULT: FAILED $fails [live: $LIVE]" >&2; exit 1; }

# =====================================================================
# T3 — no production-reachable injection path (AC6)
# =====================================================================
if declare -F main >/dev/null 2>&1 && declare -F validate_caps >/dev/null 2>&1; then
  pass "T3 sourcing exposes functions without executing main"
else
  fail "T3 sourcing $HOOK did not expose main/validate_caps as functions"
fi

# The only SOLEUR_* variable the hook may read is the documented kill switch.
soleur_vars=$(grep -oE 'SOLEUR_[A-Z0-9_]+' "$HOOK" | sort -u)
unexpected=$(printf '%s\n' "$soleur_vars" | grep -vx 'SOLEUR_DISABLE_MEMORY_BACKSTOP' || true)
if [[ -z "$unexpected" ]]; then
  pass "T3 SOLEUR_DISABLE_MEMORY_BACKSTOP is the only SOLEUR_* variable read"
else
  fail "T3 hook reads unexpected SOLEUR_* variable(s): $(printf '%s' "$unexpected" | tr '\n' ' ')"
fi

# The #7151 seam shapes, by name-shape rather than by exact name.
if grep -qE '(TARGET_PID|_CAP_PID|_CAP_BYTES|_TEST_MODE|_INJECT)' "$HOOK"; then
  fail "T3 hook contains a test-injection seam shape (TARGET_PID/_CAP_PID/_CAP_BYTES/_TEST_MODE/_INJECT)"
else
  pass "T3 no test-injection seam shapes present"
fi

# =====================================================================
# T2 — two-sided cap validation (AC6)
# =====================================================================
# validate_caps <scope_high> <scope_max> <fleet_high> <fleet_max>
GiB() { echo $(( $1 * 1024 * 1024 * 1024 )); }
OK_SH=$(GiB 6); OK_SM=$(GiB 7); OK_FH=$(GiB 16); OK_FM=$(GiB 20)

if validate_caps "$OK_SH" "$OK_SM" "$OK_FH" "$OK_FM" >/dev/null 2>&1; then
  pass "T2 shipped cap set accepted"
else
  fail "T2 shipped cap set REJECTED by validate_caps — the hook would refuse on every run"
fi

t2_reject() { # <label> <sh> <sm> <fh> <fm>
  local label=$1; shift
  if validate_caps "$@" >/dev/null 2>&1; then
    fail "T2 accepted out-of-range case: $label"
  else
    pass "T2 rejected $label"
  fi
}
t2_reject "scope_max below 3GiB floor"        "$OK_SH" "$(GiB 2)" "$OK_FH" "$OK_FM"
t2_reject "scope_max above 8GiB ceiling"      "$OK_SH" "$(GiB 9)" "$OK_FH" "$OK_FM"
t2_reject "scope_high below 5GiB floor"       "$(GiB 4)" "$OK_SM" "$OK_FH" "$OK_FM"
t2_reject "scope_high >= scope_max"           "$OK_SM" "$OK_SM" "$OK_FH" "$OK_FM"
t2_reject "fleet_max below 10GiB floor"       "$OK_SH" "$OK_SM" "$OK_FH" "$(GiB 9)"
t2_reject "fleet_max above 24GiB ceiling"     "$OK_SH" "$OK_SM" "$OK_FH" "$(GiB 25)"
t2_reject "fleet_high below 14GiB floor"      "$OK_SH" "$OK_SM" "$(GiB 13)" "$OK_FM"
t2_reject "fleet_high >= fleet_max"           "$OK_SH" "$OK_SM" "$OK_FM" "$OK_FM"
t2_reject "zero scope_max (the _BYTES=0 kill)" "$OK_SH" "0" "$OK_FH" "$OK_FM"
t2_reject "non-numeric scope_max"             "$OK_SH" "abc" "$OK_FH" "$OK_FM"

# The band must not admit the values D1 explicitly rejected as too tight.
if validate_caps "$(GiB 4)" "$(GiB 6)" "$(GiB 12)" "$OK_FM" >/dev/null 2>&1; then
  fail "T2 band admits the 4GiB scope-high / 12GiB fleet-high values D1 rejected as below routine load"
else
  pass "T2 band excludes the plan-rejected 4GiB/12GiB values"
fi

# =====================================================================
# T4 — PPid walk survives a comm containing a space (D8/R4)
# =====================================================================
newtmp fx || exit 2
mkdir -p "$fx/proc/100" "$fx/proc/200" "$fx/proc/300"
# A comm with a space is the exact shape `awk '{print $4}'` over stat breaks on.
printf 'Name:\tmy app name\nPid:\t200\nPPid:\t100\n'  > "$fx/proc/200/status"
printf 'Name:\tclaude\nPid:\t300\nPPid:\t200\n'       > "$fx/proc/300/status"
printf 'Name:\tinit\nPid:\t100\nPPid:\t0\n'           > "$fx/proc/100/status"
# stat field 22 (starttime) with a parenthesised comm containing spaces AND a ')'
printf '200 (my app (weird) name) S 100 200 200 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 987654 0 0\n' > "$fx/proc/200/stat"

got=$(read_ppid 200 "$fx/proc")
if [[ "$got" == "100" ]]; then
  pass "T4 read_ppid parses a comm containing a space"
else
  fail "T4 read_ppid returned '$got', expected '100' (comm-with-space fixture)"
fi

got=$(read_starttime 200 "$fx/proc")
if [[ "$got" == "987654" ]]; then
  pass "T4 read_starttime splits on the LAST ')' (comm containing spaces and a paren)"
else
  fail "T4 read_starttime returned '$got', expected '987654'"
fi

# The rejected form must fail this same fixture — proves the fixture discriminates.
naive=$(awk '{print $4}' "$fx/proc/200/stat")
if [[ "$naive" != "100" ]]; then
  pass "T4 fixture discriminates: awk '{print \$4}' yields '$naive', not the real PPid"
else
  fail "T4 fixture does NOT discriminate — the naive form also passes, so T4 proves nothing"
fi

# =====================================================================
# T5 — identity guards (D8)
# =====================================================================
# POSITIVE cases first. Without these, T5 asserts only that the walk refuses —
# and a hook whose three positive identity branches were all deleted (i.e. one
# that can never adopt anything, ever) passes this suite on every CI, Docker,
# macOS and detached run. Measured: that exact mutation was green at 34/34.
mkdir -p "$fx/proc/400" "$fx/proc/500" "$fx/exe/claude/versions/2.1.220"
printf 'claude\n' > "$fx/proc/400/comm"
printf 'Name:\tclaude\nPid:\t400\nPPid:\t100\n' > "$fx/proc/400/status"
ln -sf "$fx/exe/claude/versions/2.1.220" "$fx/proc/500/exe"
printf 'Name:\tnode\nPid:\t500\nPPid:\t100\n' > "$fx/proc/500/status"

got=$(discover_claude_pid 400 "$fx/proc" 2>/dev/null || true)
if [[ "$got" == "400 comm" ]]; then
  pass "T5 positive: comm==claude is accepted and the matching signal is reported"
else
  fail "T5 positive comm branch returned '$got', expected '400 comm'"
fi

got=$(discover_claude_pid 500 "$fx/proc" 2>/dev/null || true)
if [[ "$got" == "500 exe" ]]; then
  pass "T5 positive: exe under */claude/versions/* is accepted and reported"
else
  fail "T5 positive exe branch returned '$got', expected '500 exe'"
fi

# A /proc with no claude anywhere in the ancestry must adopt NOTHING.
if out=$(discover_claude_pid 300 "$fx/proc" 2>/dev/null); then
  fail "T5 discover_claude_pid succeeded on a fixture with no verifiable claude exe (returned '$out') — must adopt nothing on no positive match"
else
  pass "T5 no positive identity match ⇒ adopt nothing (not 'keep walking')"
fi

for bad in 0 1; do
  if discover_claude_pid "$bad" "$fx/proc" >/dev/null 2>&1; then
    fail "T5 discover_claude_pid accepted PID $bad"
  else
    pass "T5 PID $bad rejected"
  fi
done

# =====================================================================
# T5b — the traversal limit and the execpath predicate, SYNTHETICALLY (#7854)
# =====================================================================
# The end-to-end arm no longer pins MAX_WALK_HOPS, and cannot: it asks the hook
# for its own verdict instead of re-deriving one, and the real ancestry depth of
# a test run is not a reproducible number anyway (measured on this box: claude at
# hop 3 from the suite standalone, at hop 8 under five nested shells, at hop 9
# under `lefthook run pre-commit` -> `test-all.sh`). So the boundary is pinned
# HERE, against a synthetic /proc, where it is the same number on every machine
# and in CI.
newtmp hopfx || exit 2
mkdir -p "$hopfx/proc/100"
printf 'Name:\tinit\nPid:\t100\nPPid:\t0\n' > "$hopfx/proc/100/status"
# A TEN-process chain, 901 (leaf) .. 910, rooted at a pid-100 "init". Ten, not
# eight or nine: the two interesting hops are 8 (the last the walk may examine)
# and 9 (the first it must not), and a chain that ENDS at hop 9 cannot tell
# "the walk stopped at its limit" from "the walk ran out of ancestors".
for _i in $(seq 1 10); do
  _pid=$((900 + _i)); _ppid=$((900 + _i + 1)); (( _i == 10 )) && _ppid=100
  mkdir -p "$hopfx/proc/$_pid"
  printf 'Name:\tsh\nPid:\t%s\nPPid:\t%s\n' "$_pid" "$_ppid" > "$hopfx/proc/$_pid/status"
  printf 'sh\n' > "$hopfx/proc/$_pid/comm"
done
# Fixture-depth floor. A builder that emitted a SHORTER chain would make both
# assertions below agree with a walk of any limit >= the chain length — the
# guard's own dispatch, and the one mutation a delete-only battery cannot see.
_chain_n=$(find "$hopfx/proc" -mindepth 1 -maxdepth 1 -type d -name '9??' | grep -c . || true)
if [[ "$_chain_n" == "10" ]]; then
  pass "T5b fixture chain is 10 processes — two deeper than MAX_WALK_HOPS=$MAX_WALK_HOPS, so hop 9 is genuinely beyond the limit"
else
  fail "T5b fixture chain is $_chain_n process(es), expected 10 — the hop-9 case would not be beyond the limit and would prove nothing"
fi

printf 'claude\n' > "$hopfx/proc/909/comm"   # hop 9 counting the leaf as hop 1
if _out=$(discover_claude_pid 901 "$hopfx/proc" 2>/dev/null); then
  fail "T5b claude at hop 9 was ADOPTED (returned '$_out') — the walk ran past MAX_WALK_HOPS=$MAX_WALK_HOPS"
else
  pass "T5b claude at hop 9 is NOT reached — MAX_WALK_HOPS=$MAX_WALK_HOPS is a boundary, not a suggestion"
fi
printf 'sh\n' > "$hopfx/proc/909/comm"
printf 'claude\n' > "$hopfx/proc/908/comm"   # hop 8 — the last hop the walk may examine
got=$(discover_claude_pid 901 "$hopfx/proc" 2>/dev/null || true)
if [[ "$got" == "908 comm" ]]; then
  pass "T5b claude at hop 8 IS reached (returned '$got') — the walk uses its whole budget"
else
  fail "T5b claude at hop 8 returned '$got', expected '908 comm' — the walk stops short of its own limit"
fi
printf 'sh\n' > "$hopfx/proc/908/comm"

# The CLAUDE_CODE_EXECPATH predicate. No other fixture covers it, and it is the
# reason the end-to-end arm invokes the hook with that variable UNSET.
#
# MEASURED, and it contradicts the premise this case was written from: the
# predicate is plain string equality against the ancestor's /proc/<pid>/exe. It
# does not inspect the path at all, so it cannot "refuse a generic interpreter".
# Under an npm-global install whose execpath resolves to `.../bin/node`, a bare
# `node` ancestor MATCHES and is adopted with signal `execpath`. That is the
# hazard — and what removes it is unsetting the variable, which is what the
# end-to-end invocation does. Both directions are pinned so neither half can rot.
mkdir -p "$hopfx/bin"
cp /bin/true "$hopfx/bin/node" 2>/dev/null || printf '#!/bin/sh\nexit 0\n' > "$hopfx/bin/node"
ln -sf "$hopfx/bin/node" "$hopfx/proc/903/exe"
got=$( export CLAUDE_CODE_EXECPATH="$hopfx/bin/node"; discover_claude_pid 901 "$hopfx/proc" 2>/dev/null || true )
if [[ "$got" == "903 execpath" ]]; then
  pass "T5b execpath predicate: a generic-interpreter CLAUDE_CODE_EXECPATH DOES adopt a plain node ancestor (returned '$got') — the hazard, reproduced"
else
  fail "T5b execpath predicate returned '$got', expected '903 execpath' — the predicate the e2e arm's unset defends against has changed shape"
fi
if ( unset CLAUDE_CODE_EXECPATH; discover_claude_pid 901 "$hopfx/proc" >/dev/null 2>&1 ); then
  fail "T5b NEGATIVE: with CLAUDE_CODE_EXECPATH unset the node ancestor was STILL adopted — unsetting it in the e2e invocation buys nothing"
else
  pass "T5b NEGATIVE: with CLAUDE_CODE_EXECPATH unset the same node ancestor is not adopted"
fi

# =====================================================================
# T5c — this suite asks the HOOK for the end-to-end precondition (#7854)
# =====================================================================
# Source-level, so CI runs it. The live arm these checks pin is skipped anywhere
# there is no user bus, and a guard that only runs on the operator's box is not
# a guard.
_self="${BASH_SOURCE[0]}"
_walk_hits=$(grep -nE 'for +_hop +in' "$_self" || true)
_ppid_hits=$(grep -n '"/pro[c]/' "$_self" | grep -F 'PPid' || true)
if [[ -z "$_walk_hits$_ppid_hits" ]]; then
  pass "T5c no second /proc ancestry walk in this suite — the e2e gate reads the hook's own logged outcome"
else
  fail "T5c an independent ancestry walk has reappeared in this suite (#7854 — it starts one process shallower than the hook's own and the two disagree at depth):
$_walk_hits$_ppid_hits"
fi
# The patterns below are REGEXES, not fixed strings, and each is written so that
# it does not match its OWN source line — `CHIL[D]`, `\$` for a literal dollar.
# A self-matching pattern is a guard that can never red: measured, the
# fixed-string form of these stayed green under a mutant that deleted the
# `-u CLAUDE_CODE_EXECPATH` and another that moved the log read back to CWD.
if grep -qE 'the hook runs as a CHIL[D] of this suite' "$_self"; then
  pass "T5c the measured rationale for having no second walk is still recorded above the e2e arm"
else
  fail "T5c the rationale comment explaining why there is no second walk is gone — deleted silently, the next reader restores the walk"
fi
if grep -qE 'env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="\$e2edir"' "$_self"; then
  pass "T5c the real hook is invoked with CLAUDE_PROJECT_DIR at scratch and CLAUDE_CODE_EXECPATH unset"
else
  fail "T5c the e2e invocation no longer redirects CLAUDE_PROJECT_DIR to scratch and unsets CLAUDE_CODE_EXECPATH"
fi
# Not "an $E2E_LOG read exists somewhere" — three of them do, so deleting one
# leaves that form green (measured). What must hold is that NO read of the
# ledger is CWD-relative: `_repo_root()` derives the log file from
# CLAUDE_PROJECT_DIR, so a read against the checkout parses a STALE line the
# real session's last SessionStart wrote, and the gate then reports an outcome
# no run in this suite produced.
_cwd_reads=$(grep -nE 'tail -[0-9]+ "\.claude/\.memory-backstop' "$_self" || true)
if [[ -z "$_cwd_reads" ]]; then
  pass "T5c no CWD-relative read of the backstop ledger — every read follows the hook to the scratch dir it was pointed at"
else
  fail "T5c the e2e gate reads the ledger relative to CWD, not from the scratch dir the hook was pointed at — it would parse a stale line from the real checkout's previous run:
$_cwd_reads"
fi
# Order is load-bearing and invisible to a delete-only mutation: a read hoisted
# ABOVE the invocation reports the PREVIOUS run's outcome and the gate silently
# decides on stale data.
_inv_line=$(grep -nE '^ +run_real_hook "\$hookout' "$_self" | head -1 | cut -d: -f1)
_read_line=$(grep -nE '^ +logline=\$\(tail -1 "\$E2E_LOG"' "$_self" | head -1 | cut -d: -f1)
if [[ -n "$_inv_line" && -n "$_read_line" ]] && (( _read_line > _inv_line )); then
  pass "T5c the e2e gate reads its log line (line $_read_line) AFTER invoking the hook (line $_inv_line)"
else
  fail "T5c e2e gate ordering: hook invocation at line '${_inv_line:-<not found>}', log read at line '${_read_line:-<not found>}' — the read must follow the invocation, or the gate decides on the previous run's outcome"
fi

# =====================================================================
# T6 — fail-open branches (AC9): exit 0, one skipped line, distinct reasons
# =====================================================================
run_hook_isolated() { # <logdir> [env assignments...] -> writes log, echoes exit code
  local ld=$1; shift
  local rc
  # `-u SOLEUR_DISABLE_MEMORY_BACKSTOP` clears the AMBIENT kill switch. It is the
  # hook's FIRST gate, so an operator (or a mutation-battery arm) with it
  # exported in their shell made every branch below log reason=disabled and the
  # no_bus case failed on an environment fact rather than a defect — the same
  # class as #7854, one file over. The `-u` is applied before the caller's own
  # assignments, so the case that DOES test the kill switch still sets it.
  ( cd "$PWD" && env -u SOLEUR_DISABLE_MEMORY_BACKSTOP "$@" CLAUDE_PROJECT_DIR="$ld" \
      "$PWD/$HOOK" </dev/null >"$ld/stdout" 2>"$ld/stderr" )
  rc=$?
  echo "$rc"
}

newtmp ld || exit 2
mkdir -p "$ld/.claude/hooks"
rc=$(run_hook_isolated "$ld" SOLEUR_DISABLE_MEMORY_BACKSTOP=1)
logline=$(tail -1 "$ld/.claude/.memory-backstop.jsonl" 2>/dev/null || true)
if [[ "$rc" == "0" ]]; then
  pass "T6 disabled kill switch exits 0"
else
  fail "T6 disabled kill switch exited $rc, must be 0"
fi
if [[ -n "$logline" ]] && printf '%s' "$logline" | jq -e 'select(.outcome=="skipped" and .reason=="disabled")' >/dev/null 2>&1; then
  pass "T6 kill switch logs outcome=skipped reason=disabled"
else
  fail "T6 kill switch did not log outcome=skipped reason=disabled (got: ${logline:-<no line>})"
fi
if [[ ! -s "$ld/stdout" ]]; then
  pass "T6 fail-open branch emits zero bytes on stdout (T19 non-message path)"
else
  fail "T6 fail-open branch wrote to stdout: $(head -c 200 "$ld/stdout")"
fi

# No bus: point XDG_RUNTIME_DIR at a directory with no bus socket.
newtmp ld2 || exit 2
mkdir -p "$ld2/.claude/hooks" "$ld2/runtime"
rc=$(run_hook_isolated "$ld2" XDG_RUNTIME_DIR="$ld2/runtime")
logline=$(tail -1 "$ld2/.claude/.memory-backstop.jsonl" 2>/dev/null || true)
if [[ "$rc" == "0" ]] && printf '%s' "$logline" | jq -e 'select(.outcome=="skipped" and .reason=="no_bus")' >/dev/null 2>&1; then
  pass "T6 absent bus socket ⇒ exit 0, outcome=skipped reason=no_bus"
else
  fail "T6 absent bus socket: rc=$rc line=${logline:-<none>} (expected skipped/no_bus)"
fi

# Distinct reason enums must exist in the source for every documented branch.
missing=""
for r in disabled no_busctl no_bus claude_pid_not_found no_terminal_scope cap_out_of_range; do
  grep -qF "\"$r\"" "$HOOK" || grep -qF "reason=$r" "$HOOK" || grep -qF "$r" "$HOOK" || missing="$missing $r"
done
if [[ -z "$missing" ]]; then
  pass "T6 all documented fail-open reason enums present"
else
  fail "T6 missing fail-open reason enum(s):$missing"
fi

# =====================================================================
# T16b / T17 — attribution: path argument, fires on INCREASE not non-zero
# =====================================================================
newtmp ev || exit 2
printf 'low 0\nhigh 12\nmax 4\noom 2\noom_kill 3\noom_group_kill 0\n' > "$ev/memory.events"
printf '0\n' > "$ev/memory.peak"

msg=$(attribution_message "$ev/memory.events" "$ev/memory.peak" 0 0 2>/dev/null || true)
if [[ -n "$msg" ]]; then
  pass "T16b attribution fires when oom_kill increased 0→3 (memory.events read from a PATH ARGUMENT)"
else
  fail "T16b attribution did not fire on an oom_kill increase"
fi

msg2=$(attribution_message "$ev/memory.events" "$ev/memory.peak" 3 12 2>/dev/null || true)
if [[ -z "$msg2" ]]; then
  pass "T17 attribution stays silent when counters are UNCHANGED (monotonic counters must not re-emit forever)"
else
  fail "T17 attribution re-fired on an unchanged counter — it would re-emit the same post-mortem every SessionStart"
fi

msg3=$(attribution_message "$ev/memory.events" "$ev/memory.peak" 3 5 2>/dev/null || true)
if [[ -n "$msg3" ]] && ! grep -qiE 'killed|stopped' <<< "$msg3"; then
  pass "T17 near-miss message fires on a 'high' increase without an oom_kill increase"
elif [[ -n "$msg3" ]]; then
  pass "T17 near-miss path produced a message on a high-only increase"
else
  fail "T17 no near-miss message on a 'high' increase (5→12) with oom_kill unchanged"
fi

# The attribution message must not claim causation (bystander case, R3).
if [[ -n "$msg" ]] && grep -qiE '\byou (caused|did)\b|your (command )?caused' <<< "$msg"; then
  fail "T16b attribution message claims causation — a slice-level kill can hit a bystander session"
else
  pass "T16b attribution message does not claim causation"
fi

# T19 — a message, when emitted, must be well-formed systemMessage JSON.
if declare -F emit_message >/dev/null 2>&1; then
  jout=$(emit_message "hello world" 2>/dev/null || true)
  if printf '%s' "$jout" | jq -e '.systemMessage' >/dev/null 2>&1; then
    pass "T19 emit_message produces well-formed {systemMessage: ...} JSON"
  else
    fail "T19 emit_message output is not valid systemMessage JSON: $(printf '%s' "$jout" | head -c 120)"
  fi
else
  fail "T19 emit_message function not exposed"
fi

# =====================================================================
# AC2 — invoke through the command string RECONSTRUCTED FROM settings.json
# =====================================================================
# Guards the TEST, not the kernel: `bash <hook>` ignores the mode bit, and that
# fallback is exactly how #7151's 26 green assertions sat on a hook that could
# not run.
cmd=$(jq -r '.hooks.SessionStart[]?.hooks[]?.command' "$SETTINGS" 2>/dev/null | grep -F 'memory-backstop.sh' | head -1 || true)
if [[ -n "$cmd" ]]; then
  resolved=${cmd//\"\$CLAUDE_PROJECT_DIR\"/$PWD}
  resolved=${resolved//\$CLAUDE_PROJECT_DIR/$PWD}
  newtmp ld3 || exit 2
  mkdir -p "$ld3/.claude/hooks" "$ld3/runtime"
  if env CLAUDE_PROJECT_DIR="$ld3" XDG_RUNTIME_DIR="$ld3/runtime" "$resolved" </dev/null >/dev/null 2>&1; then
    pass "AC2 hook runs via the settings.json command string (direct exec, no interpreter)"
  else
    fail "AC2 direct exec of the settings.json command string failed: $resolved"
  fi
  scratch="$ld3/copy.sh"
  cp "$HOOK" "$scratch" && chmod 644 "$scratch"
  if env CLAUDE_PROJECT_DIR="$ld3" XDG_RUNTIME_DIR="$ld3/runtime" "$scratch" </dev/null >/dev/null 2>&1; then
    fail "AC2 a 0644 copy still executed — the harness is falling back to an interpreter, which would swallow the #7151 defect"
  else
    pass "AC2 a 0644 copy fails to exec (harness honours the mode bit)"
  fi
else
  # Registration shipped, so reaching here means the hook was REMOVED from
  # settings.json. That must be a hard failure: silently degrading to a weaker
  # assertion and passing with "not yet registered" reads as intentional.
  fail "AC2 $HOOK is not registered in $SETTINGS — the runtime would never invoke it (this is the #7151 shape)"
  newtmp ld3 || exit 2
  mkdir -p "$ld3/.claude/hooks" "$ld3/runtime"
  if env CLAUDE_PROJECT_DIR="$ld3" XDG_RUNTIME_DIR="$ld3/runtime" "$PWD/$HOOK" </dev/null >/dev/null 2>&1; then
    pass "AC2 hook is directly executable (not yet registered in settings.json)"
  else
    fail "AC2 direct exec of $HOOK failed"
  fi
  scratch="$ld3/copy.sh"
  cp "$HOOK" "$scratch" && chmod 644 "$scratch"
  if env CLAUDE_PROJECT_DIR="$ld3" XDG_RUNTIME_DIR="$ld3/runtime" "$scratch" </dev/null >/dev/null 2>&1; then
    fail "AC2 a 0644 copy still executed — harness is not honouring the mode bit"
  else
    pass "AC2 a 0644 copy fails to exec (harness honours the mode bit)"
  fi
fi

# =====================================================================
# LIVE ARM
# =====================================================================
sysd_prop() { systemctl --user show "$1" -p "$2" --value 2>/dev/null; }
cg_of() { cut -d: -f3 < "/proc/$1/cgroup" 2>/dev/null; }
cg_path() { echo "/sys/fs/cgroup$(cg_of "$1")"; }

# MemoryHigh is set EQUAL to MemoryMax here, deliberately. With a `high` band
# below `max` AND MemorySwapMax=0, an anon-heavy allocator is throttled into
# synchronous reclaim that can never free anything (no swap, no file pages to
# drop) and it crawls instead of reaching `max` — measured: a 512 MB allocator
# under high=200 MB / max=256 MB never OOMed and never finished, hanging the
# suite. That is D2's documented degeneration reproduced, and it is precisely why
# MemoryMax rather than MemoryHigh is the real backstop; but it makes a
# kill-mechanism test unrunnable, so the band is closed to zero width here.
start_test_scope() { # <scope> <slice> <pid...>
  local scope=$1 slice=$2; shift 2
  local n=$#
  local args=()
  args+=("PIDs" "au" "$n")
  local p
  for p in "$@"; do args+=("$p"); done
  SCOPES+=("$scope")
  busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager StartTransientUnit "ssa(sv)a(sa(sv))" \
    "$scope" "fail" 7 \
    "${args[@]}" \
    "Slice" "s" "$slice" \
    "MemoryHigh" "t" 268435456 \
    "MemoryMax" "t" 268435456 \
    "MemorySwapMax" "t" 0 \
    "OOMPolicy" "s" "continue" \
    "Delegate" "b" true \
    0 >/dev/null 2>&1
}

# Poll to convergence rather than reading once: StartTransientUnit returns when
# the job is enqueued. A single partial migration was observed once during
# plan-time probing and could not be reproduced in 22 subsequent trials, so this
# bounded poll converts an unexplained straggler into a slower pass instead of a
# flaky red. It cannot mask a real failure — the bound is short and a genuine
# non-migration still fails.
wait_in_scope() { # <scope-suffix> <pid...>
  local scope=$1; shift
  local i p ok
  for i in $(seq 1 40); do
    ok=1
    for p in "$@"; do [[ "$(cg_of "$p")" == *"$scope" ]] || ok=0; done
    [[ "$ok" == "1" ]] && return 0
    sleep 0.05
  done
  return 1
}

if [[ "$LIVE" != "yes" ]]; then
  for t in "${LIVE_LABELS[@]}"; do
    skip "$t" "no user systemd bus"
  done
else
  live_mark T14-kill-mechanism
  # ---- T14: kill mechanism at 256 MB, with a sentinel standing in for claude.
  # Never at the real cap: proving a memory cap kills does not require allocating
  # the cap. The sentinel is required — with the allocator alone the scope empties
  # on its death and self-cleans, so memory.events is gone before it can be read.
  sleep 300 & SENTINEL=$!; SPAWNED+=("$SENTINEL")
  KSCOPE="soleurtest-kill-$$.scope"
  newtmp kdir || exit 2
  if start_test_scope "$KSCOPE" "$TEST_SLICE" "$SENTINEL" && wait_in_scope "$KSCOPE" "$SENTINEL"; then
    kcg=$(cg_path "$SENTINEL")
    # The allocator must not allocate a single byte until it is CONFIRMED inside
    # the capped cgroup. Spawn-then-attach races the attach against the
    # allocation loop, and losing that race means allocating uncapped on a box
    # whose free memory and swap are exactly what this feature exists to
    # protect. So it blocks on a go-file that is touched only after membership
    # is verified, and its ceiling is 512 MB — twice the 256 MB cap, enough to
    # prove the kill, small enough to be survivable if it ever did escape.
    python3 -c "
import os, sys, time
go = sys.argv[1]
deadline = time.time() + 30
while not os.path.exists(go):
    if time.time() > deadline: sys.exit(3)
    time.sleep(0.02)
b = []
try:
    while len(b) < 512:
        b.append(bytearray(1024 * 1024))
except MemoryError:
    sys.exit(4)
sys.exit(0)
" "$kdir/go" 2>/dev/null & ALLOC=$!
    SPAWNED+=("$ALLOC")
    busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
      org.freedesktop.systemd1.Manager AttachProcessesToUnit "ssau" "$KSCOPE" "/" 1 "$ALLOC" >/dev/null 2>&1
    if wait_in_scope "$KSCOPE" "$ALLOC"; then
      touch "$kdir/go"
    else
      fail "T14 allocator never joined the capped scope — refusing to release it uncapped"
    fi
    # `wait`, not a `kill -0` poll: a dead child stays a ZOMBIE until reaped, and
    # `kill -0` succeeds on a zombie — so the poll would report the allocator
    # alive forever and the assertion would fail for a bookkeeping reason rather
    # than a real one. `wait` reaps it and yields the signal that killed it.
    # Safe to wait unbounded here: the allocator is capped, gated, and bounded at
    # 512 MB.
    # Watchdog: a cap that fails to kill must fail the TEST, never hang the
    # suite. It marks the timeout on disk so a watchdog SIGKILL cannot be
    # mistaken for the cgroup OOM kill this test exists to observe.
    ( sleep 90; touch "$kdir/timedout"; kill -9 "$ALLOC" 2>/dev/null ) >/dev/null 2>&1 &
    WATCHDOG=$!
    wait "$ALLOC" 2>/dev/null; alloc_rc=$?
    kill "$WATCHDOG" 2>/dev/null
    alloc_dead=0
    # 137 = 128+SIGKILL, which is what a cgroup OOM kill delivers.
    if [[ -f "$kdir/timedout" ]]; then
      alloc_dead=0
      fail "T14 allocator neither OOM-killed nor finished within 90s — the cap did not terminate it"
    elif [[ "$alloc_rc" == "137" ]]; then
      alloc_dead=1
    fi
    sentinel_alive=0; kill -0 "$SENTINEL" 2>/dev/null && sentinel_alive=1
    oomk=$(awk '/^oom_kill /{print $2}' "$kcg/memory.events" 2>/dev/null || echo 0)
    if [[ "$alloc_dead" == "1" && "$sentinel_alive" == "1" && "${oomk:-0}" -ge 1 ]]; then
      pass "T14 cap kills the allocator, sentinel survives, oom_kill=$oomk read from the still-live cgroup"
    else
      fail "T14 kill triple failed: alloc_dead=$alloc_dead sentinel_alive=$sentinel_alive oom_kill=${oomk:-unset}"
    fi
    systemctl --user stop "$KSCOPE" >/dev/null 2>&1
  else
    fail "T14 could not create the 256MB test scope"
  fi

  live_mark T11-bindsto-reap
  # ---- T11: BindsTo reap — behavioural, not just the property readback.
  sleep 300 & PARENT=$!; SPAWNED+=("$PARENT")
  sleep 300 & CHILD=$!;  SPAWNED+=("$CHILD")
  PSCOPE="soleurtest-parent-$$.scope"
  CSCOPE="soleurtest-child-$$.scope"
  if start_test_scope "$PSCOPE" "$TEST_SLICE" "$PARENT"; then
    SCOPES+=("$CSCOPE")
    busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
      org.freedesktop.systemd1.Manager StartTransientUnit "ssa(sv)a(sa(sv))" \
      "$CSCOPE" "fail" 5 \
      "PIDs" "au" 1 "$CHILD" \
      "Slice" "s" "$TEST_SLICE" \
      "BindsTo" "as" 1 "$PSCOPE" \
      "After" "as" 1 "$PSCOPE" \
      "Delegate" "b" true \
      0 >/dev/null 2>&1
    bt=$(sysd_prop "$CSCOPE" BindsTo)
    systemctl --user stop "$PSCOPE" >/dev/null 2>&1
    for _ in $(seq 1 40); do kill -0 "$CHILD" 2>/dev/null || break; sleep 0.05; done
    child_dead=0; kill -0 "$CHILD" 2>/dev/null || child_dead=1
    unit_gone=1; systemctl --user list-units "$CSCOPE" --all --no-pager 2>/dev/null | grep -qF "$CSCOPE" && unit_gone=0
    if [[ "$bt" == *"$PSCOPE"* && "$child_dead" == "1" && "$unit_gone" == "1" ]]; then
      pass "T11 BindsTo: property=$PSCOPE, stopping the parent left the child PID dead and its unit absent"
    else
      fail "T11 BindsTo reap failed: BindsTo='$bt' child_dead=$child_dead unit_gone=$unit_gone"
    fi
  else
    fail "T11 could not create the parent scope"
  fi

  live_mark T12-fleet-two-sessions
  # ---- T12: fleet bound with MORE THAN ONE session (AC4b)
  ALLOC_MB=48
  # `>/dev/null 2>&1` on the BACKGROUND child is load-bearing, not tidiness:
  # this runs inside `$( )`, and a backgrounded child that inherits the command
  # substitution's stdout pipe keeps it open, so the substitution blocks until
  # the child exits — here, 300 seconds.
  # ATTACH FIRST, ALLOCATE SECOND. cgroup v2 does NOT migrate charge on move, so
  # memory a process allocates before it joins the scope stays billed to its old
  # cgroup forever — the slice then reads well under the nominal sum and the
  # assertion fails for an accounting reason rather than a real one (measured:
  # ~67 MiB of a nominal 96 MiB). Each allocator therefore blocks on a go-file
  # until membership is confirmed, then signals a ready-file when its pages are
  # actually resident, so the reading is taken at a defined point rather than an
  # arbitrary one on a rising curve.
  newtmp T12D || exit 2
  spawn_alloc() { python3 -c "
import os, sys, time
go, ready = sys.argv[1], sys.argv[2]
dl = time.time() + 30
while not os.path.exists(go):
    if time.time() > dl: sys.exit(3)
    time.sleep(0.02)
b = bytearray(${ALLOC_MB}*1024*1024)
for i in range(0, len(b), 4096): b[i] = 1
open(ready, 'w').write('ok')
time.sleep(300)
" "$1" "$2" >/dev/null 2>&1 & echo $!; }
  A1=$(spawn_alloc "$T12D/go" "$T12D/r1"); SPAWNED+=("$A1")
  A2=$(spawn_alloc "$T12D/go" "$T12D/r2"); SPAWNED+=("$A2")
  S1="soleurtest-sess1-$$.scope"; S2="soleurtest-sess2-$$.scope"
  busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
    "$TEST_SLICE" true 3 \
    "MemoryHigh" "t" 1073741824 "MemoryMax" "t" 2147483648 "MemorySwapMax" "t" 0 >/dev/null 2>&1
  start_test_scope "$S1" "$TEST_SLICE" "$A1" >/dev/null 2>&1
  start_test_scope "$S2" "$TEST_SLICE" "$A2" >/dev/null 2>&1
  slice_cg="/sys/fs/cgroup/user.slice/user-$UIDN.slice/user@$UIDN.service/soleurtest.slice/$TEST_SLICE"
  if wait_in_scope "$S1" "$A1" && wait_in_scope "$S2" "$A2"; then
    touch "$T12D/go"
  else
    fail "T12 allocators never joined their scopes; the charge measurement below would be meaningless"
  fi
  for _ in $(seq 1 150); do
    [[ -f "$T12D/r1" && -f "$T12D/r2" ]] && break
    sleep 0.1
  done
  need=$(( ALLOC_MB * 3 / 2 * 1024 * 1024 ))
  nominal=$(( ALLOC_MB * 2 * 1024 * 1024 ))
  cur=$(cat "$slice_cg/memory.current" 2>/dev/null || echo 0)
  smax=$(cat "$slice_cg/memory.max" 2>/dev/null || echo 0)
  if [[ "$cur" -ge "$need" && "$smax" == "2147483648" ]]; then
    pass "T12 two concurrent scopes charge one shared slice (current=$cur >= $need, nominal $nominal) and its caps are unchanged by the second adoption"
  else
    fail "T12 fleet bound: slice memory.current=$cur (need >= $need), memory.max=$smax (need 2147483648)"
  fi

  live_mark T13-managed-oom-pref
  # ---- T13: ManagedOOMPreference on the slice
  busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
    "$TEST_SLICE" true 1 "ManagedOOMPreference" "s" "avoid" >/dev/null 2>&1
  mop=$(sysd_prop "$TEST_SLICE" ManagedOOMPreference)
  if [[ "$mop" == "avoid" ]]; then
    pass "T13 ManagedOOMPreference reads back 'avoid' on the slice"
  else
    fail "T13 ManagedOOMPreference='$mop', expected 'avoid'"
  fi

  live_mark T18-documented-kill-path
  # ---- T18: the documented kill path actually reaps
  if systemctl --user stop "$TEST_SLICE" >/dev/null 2>&1; then
    for _ in $(seq 1 40); do kill -0 "$A1" 2>/dev/null || break; sleep 0.05; done
    d1=0; kill -0 "$A1" 2>/dev/null || d1=1
    d2=0; kill -0 "$A2" 2>/dev/null || d2=1
    left=$(systemctl --user list-units 'soleurtest-*' --all --no-pager 2>/dev/null | grep -cF '.scope' || true)
    if [[ "$d1" == "1" && "$d2" == "1" ]]; then
      pass "T18 stopping the slice reaped every scope beneath it (PIDs dead, ${left} scope unit(s) left)"
    else
      fail "T18 slice stop did not reap: A1_dead=$d1 A2_dead=$d2"
    fi
  else
    fail "T18 could not stop $TEST_SLICE"
  fi

  # ---- End-to-end arm. The REAL hook runs UNCONDITIONALLY; only the ADOPTION
  # assertions are gated, and the gate is THE HOOK'S OWN LOGGED VERDICT.
  #
  # WHY THERE IS NO SECOND ANCESTRY WALK HERE — DO NOT RESTORE ONE (#7854).
  # This block used to derive "are we inside a Claude Code session?" by walking
  # /proc itself, 8 hops, argued as deliberate independence so that the gate
  # "cannot be satisfied by the same code it is gating". That argument is sound
  # for a CORRECTNESS gate. This is an ENVIRONMENT PRECONDITION, and the two are
  # not the same thing: the operative fact is not "is a claude process reachable
  # from somewhere?" but "will the hook, run from where this suite runs it,
  # apply?" — and only the hook can answer that, because the answer depends on
  # the hook's own starting depth.
  #
  # MEASURED: the hook runs as a CHILD of this suite, so an independent walk
  # starts one process SHALLOWER than the hook's own and the two can always
  # disagree by exactly one hop. Under `git commit` -> lefthook -> `sh` ->
  # `test-all.sh` -> this suite, they did: the suite's walk reached `claude` at
  # hop 8 and set its gate to yes, the hook's walk — one deeper — needed hop 9,
  # exceeded MAX_WALK_HOPS and correctly logged
  # `outcome=skipped reason=claude_pid_not_found`, and the suite then asserted an
  # adoption that correctly never happened, failing the pre-commit gate on an
  # environment fact. Matching the hook's traversal LIMIT does not fix this: the
  # walks would still start one process apart, so their ORIGINS stay different.
  #
  # The depth boundary itself is still pinned — synthetically, in T5b, where it
  # is reproducible. Here we snapshot, invoke, snapshot, and read the hook's own
  # log line.
  live_mark T10-ac7-sweep
  newtmp before || exit 2
  UROOT="/sys/fs/cgroup/user.slice/user-$UIDN.slice/user@$UIDN.service"
  snapshot() { # <outfile>
    find "$UROOT" -type d 2>/dev/null | sort > "$1.dirs"
    : > "$1.mem"
    local d f
    while IFS= read -r d; do
      for f in memory.high memory.max memory.swap.max memory.low memory.min; do
        [[ -r "$d/$f" ]] && printf '%s\t%s\t%s\n' "$d" "$f" "$(cat "$d/$f" 2>/dev/null)" >> "$1.mem"
      done
    done < "$1.dirs"
    find "$HOME/.config/systemd/user.control" -type f 2>/dev/null | sort | xargs -r sha256sum 2>/dev/null | sha256sum > "$1.ctl"
  }
  snapshot "$before/snap"

  # Every invocation of the real hook in this arm goes through ONE helper, so the
  # project dir, the identity predicates and the log file stay identical across
  # the first run and the two re-entry runs below.
  #
  # CLAUDE_PROJECT_DIR at scratch: `_repo_root()` derives BOTH the log file and
  # the stamp file from it, so this keeps `_maybe_never_worked`'s one-shot nag
  # stamp — and the lock file — out of the real checkout. The consequence is that
  # the log line MUST be read back from this same directory; reading
  # `.claude/.memory-backstop.jsonl` relative to CWD would parse a STALE line
  # from the real checkout's previous run, i.e. a gate reading the wrong file,
  # which is exactly the class of defect this arm was rewritten to close.
  #
  # CLAUDE_CODE_EXECPATH unset: it is the one identity predicate that is plain
  # string equality against an ancestor's exe (T5b measures this). Under an
  # npm-global install resolving to `.../bin/node` it would let the hook adopt a
  # bare `node` ancestor, and with it up to MAX_TREE descendants, on any box with
  # a shallower tree than the author's.
  newtmp e2edir || exit 2
  mkdir -p "$e2edir/.claude"
  E2E_LOG="$e2edir/.claude/.memory-backstop.jsonl"
  run_real_hook() { # [stdout-file] [stderr-file]
    env -u CLAUDE_CODE_EXECPATH CLAUDE_PROJECT_DIR="$e2edir" \
      "$PWD/$HOOK" </dev/null >"${1:-/dev/null}" 2>"${2:-/dev/null}"
  }

  nagged_before=absent
  [[ -e ".claude/.memory-backstop.stamp.nagged" ]] && nagged_before=present

  newtmp hookout || exit 2
  run_real_hook "$hookout/stdout" "$hookout/stderr"
  hook_rc=$?

  newtmp after || exit 2
  snapshot "$after/snap"

  logline=$(tail -1 "$E2E_LOG" 2>/dev/null || true)
  outcome=$(printf '%s' "$logline" | jq -r '.outcome // ""' 2>/dev/null || true)
  reason=$(printf '%s' "$logline" | jq -r '.reason // ""' 2>/dev/null || true)
  scope_name=$(printf '%s' "$logline" | jq -r '.scope // ""' 2>/dev/null || true)

  # UNCONDITIONAL — both are legitimate claims on the DECLINE path as well as the
  # adoption path, and the old gate ran neither whenever its walk said "not in a
  # session". Asserting them here is a straight coverage gain.
  if [[ "$hook_rc" == "0" ]]; then
    pass "T8 real hook exits 0 (outcome=$outcome reason=$reason)"
  else
    fail "T8 real hook exited $hook_rc (outcome=$outcome reason=$reason)"
  fi

  # T7 — stdout hygiene: no busctl job object path leaked into session context.
  if grep -qE '^o "?/org/freedesktop/systemd1/job/' "$hookout/stdout" 2>/dev/null; then
    fail "T7 hook stdout leaked a busctl job object path into session context"
  else
    pass "T7 hook stdout carries no busctl job object path"
  fi

  # AC17 — the redirect actually held: nothing the hook writes lands in the real
  # checkout. Compared against a before-snapshot rather than asserted absent, so
  # a nag stamp a genuine SessionStart left earlier is not read as this suite's.
  nagged_after=absent
  [[ -e ".claude/.memory-backstop.stamp.nagged" ]] && nagged_after=present
  if [[ "$nagged_before" == "$nagged_after" ]]; then
    pass "T8/AC17 the real checkout's .memory-backstop.stamp.nagged is unchanged ($nagged_after) — CLAUDE_PROJECT_DIR redirect held"
  else
    fail "T8/AC17 the hook wrote a nag stamp into the REAL checkout ($nagged_before -> $nagged_after) — CLAUDE_PROJECT_DIR was not honoured"
  fi

  cpid=$(printf '%s' "$logline" | jq -r '.pid // ""' 2>/dev/null)
  # THE GATE: the hook's own outcome, not a single reason string. The hook has
  # ELEVEN decline reasons (disabled, no_busctl, no_jq, no_bus, cap_out_of_range,
  # claude_pid_not_found, no_terminal_scope, concurrent_apply,
  # adoption_unverified, scope_caps_unverified, fleet_caps_unverified). Keying on
  # `claude_pid_not_found` alone would still fail this suite for the DOCUMENTED
  # opt-out `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` and for `concurrent_apply`, which
  # is a race with a real SessionStart rather than a defect.
  if [[ "$outcome" == "applied" ]]; then
    live_mark T8-adoption; live_mark T9-tree-adoption; live_mark T9-grandchild
    live_mark T15-idempotency; live_mark T15-terminal-scope-stable
    live_mark AC18-reentry-resweep
    # The old gate folded these two into its condition, so an `applied` line with
    # no scope or no pid silently took the DECLINE branch. They are a defect, not
    # a precondition: assert them rather than routing around them. Keeping them
    # out of the gate is also what lets an `applied` line with no `reason` field
    # at all still exercise this arm.
    if [[ -n "$scope_name" && -n "$cpid" ]]; then
      pass "T8 applied line carries both a scope ($scope_name) and a pid ($cpid)"
    else
      fail "T8 hook logged outcome=applied but scope='$scope_name' pid='$cpid' — every readback below would silently read an empty path"
    fi
    # DERIVE the scope's cgroup path from the adopted process rather than
    # constructing it from the slice names: constructing it encodes an assumption
    # about the hierarchy that, if wrong, makes every readback below silently
    # read an empty string and report a mismatch that is really a bad path.
    scg="/sys/fs/cgroup$(cut -d: -f3 < "/proc/$cpid/cgroup" 2>/dev/null | head -1)"
    h=$(cat "$scg/memory.high" 2>/dev/null); m=$(cat "$scg/memory.max" 2>/dev/null)
    sw=$(cat "$scg/memory.swap.max" 2>/dev/null); og=$(cat "$scg/memory.oom.group" 2>/dev/null)
    op=$(sysd_prop "$scope_name" OOMPolicy)
    if [[ "$h" == "6442450944" && "$m" == "7516192768" && "$sw" == "0" && "$og" == "0" && "$op" == "continue" ]]; then
      pass "T8 scope kernel files: high=$h max=$m swap.max=$sw oom.group=$og OOMPolicy=$op"
    else
      fail "T8 scope readback: high=$h max=$m swap.max=$sw oom.group=$og OOMPolicy=$op"
    fi

    fslice="$UROOT/soleur.slice/soleur-agents.slice"
    fh=$(cat "$fslice/memory.high" 2>/dev/null); fm=$(cat "$fslice/memory.max" 2>/dev/null)
    fsw=$(cat "$fslice/memory.swap.max" 2>/dev/null)
    fmop=$(sysd_prop "soleur-agents.slice" ManagedOOMPreference)
    if [[ "$fh" == "17179869184" && "$fm" == "21474836480" && "$fsw" == "0" ]]; then
      pass "AC4a production slice kernel files: high=$fh max=$fm swap.max=$fsw"
    else
      fail "AC4a production slice: high=$fh max=$fm swap.max=$fsw"
    fi
    if [[ "$fmop" == "avoid" ]]; then
      pass "AC15 production slice ManagedOOMPreference=avoid"
    else
      fail "AC15 production slice ManagedOOMPreference='$fmop'"
    fi

    # T9 / AC11 — re-walk /proc INDEPENDENTLY; do not reuse the hook's collection.
    # An earlier draft asserted "every PID in the collected tree is in the scope",
    # where the collection and the assertion shared one source of truth — a mutant
    # collecting a smaller tree satisfies that trivially.
    #
    # Spawn a synthetic grandchild so tree size >= 3 BY CONSTRUCTION rather than
    # contingent on an MCP server happening to be running.
    bash -c 'sleep 90 & wait' >/dev/null 2>&1 & GKID=$!
    SPAWNED+=("$GKID")
    sleep 0.3

    # ORDER IS LOAD-BEARING: snapshot the tree BEFORE the sweep, then assert over
    # that snapshot. A live agent session spawns processes continuously, so a
    # snapshot taken AFTER the run contains PIDs that did not exist when the hook
    # swept — they were never candidates for adoption, and counting them produces
    # a failure with no defect behind it.
    # `sort` (lexicographic) on BOTH sides, never `sort -n`: comm compares byte
    # strings, so numerically-sorted input makes it emit "not in sorted order"
    # and produce a garbage diff that reads as a real failure.
    # `pp in keep`, never `keep[pp]`: referencing an awk array element AUTO-CREATES
    # it, so the truthiness form silently interns every PPid it ever tested and
    # the final `for (p in keep)` emits them all. Measured: that inflated a real
    # 8-process tree to 119 phantom PIDs and reported 109 of them "absent from the
    # scope" — a fabricated failure with no defect behind it.
    indep=$(ps -eo pid=,ppid= | awk -v root="$cpid" '
      { ppid[$1]=$2; pids[NR]=$1 }
      END {
        keep[root]=1
        for (pass=0; pass<12; pass++)
          for (i=1;i<=NR;i++) {
            pp = ppid[pids[i]]
            if ((pp in keep) && keep[pp] == 1) keep[pids[i]] = 1
          }
        for (p in keep) if (keep[p] == 1) print p
      }' | sort)
    # Processes this suite DELIBERATELY relocated into its own soleurtest-* units
    # (T11/T12/T14) are descendants of claude but are not meant to be in claude's
    # scope. Excluding them keeps the assertion about the hook rather than about
    # the harness.
    indep=$(while IFS= read -r p; do
              [[ -z "$p" ]] && continue
              c=$(cut -d: -f3 < "/proc/$p/cgroup" 2>/dev/null)
              [[ "$c" == *soleurtest* ]] && continue
              printf '%s\n' "$p"
            done <<< "$indep" | sort)

    # NOW sweep, with the snapshot already fixed. Through the same helper: a
    # bare invocation here would re-introduce CLAUDE_CODE_EXECPATH and could
    # adopt a DIFFERENT pid than the first run, and would write the real
    # checkout's log while the assertions below read the scratch one.
    run_real_hook

    # Only PIDs still alive after the sweep can be asserted on: one that exited
    # in between is absent from cgroup.procs for a reason that is not a defect.
    indep=$(while IFS= read -r p; do
              [[ -z "$p" ]] && continue
              [[ -r "/proc/$p/cgroup" ]] || continue
              printf '%s\n' "$p"
            done <<< "$indep" | sort)

    inscope=$(sort < "$scg/cgroup.procs" 2>/dev/null)
    missing_list=$(comm -23 <(printf '%s\n' "$indep") <(printf '%s\n' "$inscope"))
    missing_pids=$(printf '%s\n' "$missing_list" | grep -c . || true)
    tree_n=$(printf '%s\n' "$indep" | grep -c .)
    if [[ "$tree_n" -ge 3 && "$missing_pids" == "0" ]]; then
      pass "T9/AC11 independently re-derived tree (n=$tree_n, >=3 by construction) is fully inside the scope's cgroup.procs"
    else
      fail "T9/AC11 tree adoption: independently derived n=$tree_n (need >=3), $missing_pids PID(s) absent from the scope:
$(printf '%s\n' "$missing_list" | head -5 | while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    printf '      pid %s comm=%s cgroup=%s\n' "$m" "$(cat /proc/$m/comm 2>/dev/null)" "$(cut -d: -f3 < /proc/$m/cgroup 2>/dev/null)"
  done)"
    fi

    # AC18 — re-entry re-sweep adopts a process that is OUTSIDE the scope at the
    # time the hook re-runs. Parked in the terminal's own scope (not merely
    # spawned, which would inherit the cgroup and prove nothing).
    sleep 120 & LATE=$!; SPAWNED+=("$LATE")
    # Park it in a DELEGATED test scope. The terminal's own scope is not
    # delegated, so AttachProcessesToUnit refuses it ("Process migration not
    # available on non-delegated units") and the process would never leave
    # claude's scope — making the re-sweep look proven when nothing moved.
    PARK="soleurtest-park-$$.scope"
    parked=no
    if start_test_scope "$PARK" "$TEST_SLICE" "$LATE" && wait_in_scope "$PARK" "$LATE"; then
      late_cg=$(cut -d: -f3 < "/proc/$LATE/cgroup" 2>/dev/null)
      [[ "${late_cg##*/}" != "$scope_name" ]] && parked=yes
    fi

    bindsto_before=$(sysd_prop "$scope_name" BindsTo)
    ts_before=$(tail -1 "$E2E_LOG" 2>/dev/null | jq -r '.terminal_scope // ""' 2>/dev/null)
    run_real_hook
    bindsto_after=$(sysd_prop "$scope_name" BindsTo)
    ts_after=$(tail -1 "$E2E_LOG" 2>/dev/null | jq -r '.terminal_scope // ""' 2>/dev/null)

    if [[ "$parked" == "yes" ]]; then
      late_after=$(cut -d: -f3 < "/proc/$LATE/cgroup" 2>/dev/null)
      if [[ "${late_after##*/}" == "$scope_name" ]]; then
        pass "AC18 re-entry re-sweep pulled a process parked OUTSIDE the scope back in (Delegate=true + AttachProcessesToUnit wired)"
      else
        fail "AC18 re-entry re-sweep did not adopt the parked process: cgroup=${late_after##*/}, expected $scope_name"
      fi
    else
      fail "AC18 could not park a process outside the scope, so the re-sweep is untested (scope=$scope_name, parked cgroup=${late_cg:-<none>})"
    fi

    if [[ "$bindsto_before" == "$bindsto_after" ]]; then
      pass "T15/AC10 unit BindsTo unchanged across re-entry ('$bindsto_after')"
    else
      fail "T15/AC10 BindsTo changed across re-entry: '$bindsto_before' -> '$bindsto_after' (self-binding bug)"
    fi
    # The unit's BindsTo cannot change on re-entry (it is not a settable runtime
    # property), so it alone cannot detect a hook that RE-DERIVES the terminal
    # scope from its own cgroup — by then its own cgroup IS its scope. What
    # carries AC10's claim is that the value the hook RECORDS stays the terminal
    # scope rather than becoming its own. Mutation-verified: re-deriving on
    # re-entry flips this to soleur-agent-<pid>.scope.
    if [[ -n "$ts_before" && "$ts_before" == "$ts_after" ]]; then
      pass "T15/AC10 logged terminal_scope stable across re-entry ('$ts_after') — the hook preserves the binding instead of re-deriving it"
    else
      fail "T15/AC10 logged terminal_scope changed across re-entry: '$ts_before' -> '$ts_after' (self-binding bug)"
    fi
    nscopes=$(systemctl --user list-units 'soleur-agent-*' --all --no-pager 2>/dev/null | grep -cF "$scope_name" || true)
    if [[ "$nscopes" -le 1 ]]; then
      pass "T15/AC10 re-entry refreshed one scope rather than duplicating it"
    else
      fail "T15/AC10 re-entry produced $nscopes units for $scope_name"
    fi
  else
    for t in T8-adoption T9-tree-adoption T9-grandchild T15-idempotency \
             T15-terminal-scope-stable AC18-reentry-resweep; do
      skip "$t" "the hook itself declined: outcome='${outcome:-<no log line>}' reason='${reason:-}' — run this suite STANDALONE to exercise the adoption arm; the hook runs one process deeper than this suite, so at lefthook depth claude sits outside its ${MAX_WALK_HOPS}-hop limit"
    done
  fi

  # T10 / AC7 — before/after filesystem sweep.
  newdirs=$(comm -13 "$before/snap.dirs" "$after/snap.dirs" | grep -vE '/soleur\.slice([/[:space:]]|$)' | grep -c . || true)
  memdelta=$(diff "$before/snap.mem" "$after/snap.mem" 2>/dev/null | grep -E '^[<>]' \
    | grep -vE '/soleur\.slice([/[:space:]]|$)' | grep -c . || true)
  ctl_same=1; cmp -s "$before/snap.ctl" "$after/snap.ctl" || ctl_same=0
  if [[ "$newdirs" == "0" ]]; then
    pass "T10/AC7 no new cgroup directory outside the hook's own soleur.slice chain"
  else
    fail "T10/AC7 $newdirs new cgroup dir(s) appeared OUTSIDE soleur.slice:
$(comm -13 "$before/snap.dirs" "$after/snap.dirs" | grep -vE '/soleur\.slice([/[:space:]]|$)' | head -5)"
  fi
  if [[ "$memdelta" == "0" ]]; then
    pass "T10/AC7 memory.{high,max,swap.max,low,min} changed only inside the hook's own slice chain"
  else
    fail "T10/AC7 $memdelta memory-limit change(s) OUTSIDE the hook's chain:
$(diff "$before/snap.mem" "$after/snap.mem" | grep -E '^[<>]' | grep -vE '/soleur\.slice([/[:space:]]|$)' | head -5)"
  fi
  if [[ "$ctl_same" == "1" ]]; then
    pass "T10/AC7 ~/.config/systemd/user.control/ byte-identical (runtime=true, no persistent operator-config mutation)"
  else
    fail "T10/AC7 ~/.config/systemd/user.control/ CHANGED — a persistent drop-in was written (runtime=true was dropped)"
  fi
fi

# Reconcile the ledger on EVERY path. A label that was neither run nor skipped
# means the test was deleted (or its live_mark was), which is exactly the case
# the old count-vs-count check could not see.
_unaccounted=()
for _l in "${LIVE_LABELS[@]}"; do
  [[ -z "${LIVE_SEEN[$_l]:-}" ]] && _unaccounted+=("$_l")
done
if (( ${#_unaccounted[@]} > 0 )); then
  fail "live-arm ledger: ${#_unaccounted[@]} declared live test(s) neither ran nor were skipped — deleted, not skipped: ${_unaccounted[*]}"
else
  pass "live-arm ledger: all ${#LIVE_LABELS[@]} declared live tests accounted for (ran or explicitly skipped)"
fi

echo
_skipnote=""
if [[ "$LIVE" != "yes" ]]; then
  _skipnote="SKIP: no user systemd bus — $skipped_live live assertion(s) not run"
elif [[ "$skipped_live" -gt 0 ]]; then
  _skipnote="SKIP: the hook declined to adopt (see the per-test reason above) — $skipped_live end-to-end adoption assertion(s) not run"
fi
_livetag=$([[ "$LIVE" == yes ]] && { [[ "$skipped_live" -gt 0 ]] && echo "yes, e2e SKIPPED" || echo "yes"; } || echo "SKIPPED")

if (( fails == 0 )); then
  echo "RESULT: PASSED $passes [live: $_livetag]"
  [[ -n "$_skipnote" ]] && echo "$_skipnote"
  exit 0
fi
echo "RESULT: FAILED $fails (passed $passes) [live: $_livetag]" >&2
[[ -n "$_skipnote" ]] && echo "$_skipnote" >&2
exit 1
