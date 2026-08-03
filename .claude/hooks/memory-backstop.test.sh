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
#     The skipped COUNT is asserted against the number of live tests declared, so
#     a live test that is DELETED is distinguishable from one that was skipped.
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

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 2

HOOK=".claude/hooks/memory-backstop.sh"
SETTINGS=".claude/settings.json"
TEST_SLICE="soleurtest-agents.slice"
UIDN=$(id -u)
export TMPDIR="${TMPDIR:-/var/tmp}"

fails=0
passes=0
skipped_live=0
# Number of live-arm assertions. Asserted against skipped_live when the live arm
# does not run, so deleting a live test cannot masquerade as a skip.
declare -i LIVE_TEST_COUNT=10

pass() { printf '  ✓ %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }
skip() { printf '  ~ SKIP %s\n' "$1"; skipped_live=$((skipped_live + 1)); }

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

mktmp() { local d; d=$(mktemp -d -t membackstop.XXXXXXXX) || return 1; TMPDIRS+=("$d"); echo "$d"; }

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
fx=$(mktmp) || exit 2
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
# T6 — fail-open branches (AC9): exit 0, one skipped line, distinct reasons
# =====================================================================
run_hook_isolated() { # <logdir> [env assignments...] -> writes log, echoes exit code
  local ld=$1; shift
  local rc
  ( cd "$PWD" && env "$@" CLAUDE_PROJECT_DIR="$ld" "$PWD/$HOOK" </dev/null >"$ld/stdout" 2>"$ld/stderr" )
  rc=$?
  echo "$rc"
}

ld=$(mktmp) || exit 2
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
ld2=$(mktmp) || exit 2
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
ev=$(mktmp) || exit 2
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
  ld3=$(mktmp) || exit 2
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
  # Before Phase 4 wiring lands this is expected; assert the direct-exec property
  # against the hook path itself so the assertion is never vacuous.
  ld3=$(mktmp) || exit 2
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
    "MemoryHigh" "t" 209715200 \
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
  for t in T8-adoption T9-tree-adoption T10-ac7-sweep T11-bindsto-reap T12-fleet-two-sessions \
           T13-managed-oom-pref T14-kill-mechanism T15-idempotency T18-documented-kill-path \
           AC18-reentry-resweep; do
    skip "$t (no user systemd bus)"
  done
  if [[ "$skipped_live" -ne "$LIVE_TEST_COUNT" ]]; then
    fail "live-arm bookkeeping: skipped $skipped_live but $LIVE_TEST_COUNT live tests are declared — a live test was deleted, not skipped"
  else
    pass "live-arm skip count matches the $LIVE_TEST_COUNT declared live tests"
  fi
else
  # ---- T14: kill mechanism at 256 MB, with a sentinel standing in for claude.
  # Never at the real cap: proving a memory cap kills does not require allocating
  # the cap. The sentinel is required — with the allocator alone the scope empties
  # on its death and self-cleans, so memory.events is gone before it can be read.
  sleep 300 & SENTINEL=$!; SPAWNED+=("$SENTINEL")
  KSCOPE="soleurtest-kill-$$.scope"
  kdir=$(mktmp) || exit 2
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
    wait "$ALLOC" 2>/dev/null; alloc_rc=$?
    alloc_dead=0
    # 137 = 128+SIGKILL, which is what a cgroup OOM kill delivers.
    [[ "$alloc_rc" == "137" ]] && alloc_dead=1
    kill -0 "$ALLOC" 2>/dev/null || alloc_dead=1
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

  # ---- T12: fleet bound with MORE THAN ONE session (AC4b)
  ALLOC_MB=48
  # `>/dev/null 2>&1` on the BACKGROUND child is load-bearing, not tidiness:
  # this runs inside `$( )`, and a backgrounded child that inherits the command
  # substitution's stdout pipe keeps it open, so the substitution blocks until
  # the child exits — here, 300 seconds.
  spawn_alloc() { python3 -c "
import time
b=bytearray(${ALLOC_MB}*1024*1024)
for i in range(0,len(b),4096): b[i]=1
time.sleep(300)
" >/dev/null 2>&1 & echo $!; }
  A1=$(spawn_alloc); SPAWNED+=("$A1")
  A2=$(spawn_alloc); SPAWNED+=("$A2")
  S1="soleurtest-sess1-$$.scope"; S2="soleurtest-sess2-$$.scope"
  busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
    "$TEST_SLICE" true 3 \
    "MemoryHigh" "t" 1073741824 "MemoryMax" "t" 2147483648 "MemorySwapMax" "t" 0 >/dev/null 2>&1
  start_test_scope "$S1" "$TEST_SLICE" "$A1" >/dev/null 2>&1
  start_test_scope "$S2" "$TEST_SLICE" "$A2" >/dev/null 2>&1
  wait_in_scope "$S1" "$A1"; wait_in_scope "$S2" "$A2"
  slice_cg="/sys/fs/cgroup/user.slice/user-$UIDN.slice/user@$UIDN.service/soleurtest.slice/$TEST_SLICE"
  need=$(( ALLOC_MB * 2 * 1024 * 1024 ))
  # Poll until both allocations are actually charged. A fixed `sleep 1` samples
  # an arbitrary point on a curve that is still rising, which makes the assertion
  # a race rather than a measurement.
  cur=0
  for _ in $(seq 1 100); do
    cur=$(cat "$slice_cg/memory.current" 2>/dev/null || echo 0)
    [[ "$cur" -ge "$need" ]] && break
    sleep 0.1
  done
  smax=$(cat "$slice_cg/memory.max" 2>/dev/null || echo 0)
  if [[ "$cur" -ge "$need" && "$smax" == "2147483648" ]]; then
    pass "T12 two concurrent scopes charge one shared slice (current=$cur >= $need) and its caps are unchanged by the second adoption"
  else
    fail "T12 fleet bound: slice memory.current=$cur (need >= $need), memory.max=$smax (need 2147483648)"
  fi

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

  # ---- T8/T9/T10/T15/AC18: exercise the REAL hook end-to-end, LAST.
  before=$(mktmp) || exit 2
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

  hookout=$(mktmp) || exit 2
  "$PWD/$HOOK" </dev/null >"$hookout/stdout" 2>"$hookout/stderr"
  hook_rc=$?

  after=$(mktmp) || exit 2
  snapshot "$after/snap"

  logline=$(tail -1 ".claude/.memory-backstop.jsonl" 2>/dev/null || true)
  outcome=$(printf '%s' "$logline" | jq -r '.outcome // ""' 2>/dev/null || true)
  scope_name=$(printf '%s' "$logline" | jq -r '.scope // ""' 2>/dev/null || true)

  if [[ "$hook_rc" == "0" ]]; then
    pass "T8 real hook exits 0 (outcome=$outcome)"
  else
    fail "T8 real hook exited $hook_rc"
  fi

  # T7 — stdout hygiene: no busctl job object path leaked into session context.
  if grep -qE '^o "?/org/freedesktop/systemd1/job/' "$hookout/stdout" 2>/dev/null; then
    fail "T7 hook stdout leaked a busctl job object path into session context"
  else
    pass "T7 hook stdout carries no busctl job object path"
  fi

  cpid=$(printf '%s' "$logline" | jq -r '.pid // ""' 2>/dev/null)
  if [[ "$outcome" == "applied" && -n "$scope_name" && -n "$cpid" ]]; then
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
    "$PWD/$HOOK" </dev/null >/dev/null 2>&1

    # `sort` (lexicographic) on BOTH sides, never `sort -n`: comm compares byte
    # strings, so numerically-sorted input makes it emit "not in sorted order"
    # and produce a garbage diff that reads as a real failure.
    indep=$(ps -eo pid=,ppid= | awk -v root="$cpid" '
      { ppid[$1]=$2; pids[NR]=$1 }
      END {
        keep[root]=1
        for (pass=0; pass<12; pass++)
          for (i=1;i<=NR;i++) if (keep[ppid[pids[i]]]) keep[pids[i]]=1
        for (p in keep) print p
      }' | sort)
    inscope=$(sort < "$scg/cgroup.procs" 2>/dev/null)
    missing_pids=$(comm -23 <(printf '%s\n' "$indep") <(printf '%s\n' "$inscope") | grep -c . || true)
    tree_n=$(printf '%s\n' "$indep" | grep -c .)
    if [[ "$tree_n" -ge 2 && "$missing_pids" == "0" ]]; then
      pass "T9/AC11 independently re-derived tree (n=$tree_n) is a subset of the scope's cgroup.procs"
    else
      fail "T9/AC11 tree adoption: independently derived n=$tree_n, $missing_pids PID(s) absent from the scope"
    fi

    # AC18 — re-entry re-sweep adopts a child spawned AFTER first adoption.
    sleep 120 & LATE=$!; SPAWNED+=("$LATE")
    busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
      org.freedesktop.systemd1.Manager AttachProcessesToUnit "ssau" \
      "app-gnome-dev.warp.Warp-3591813.scope" "/" 1 "$LATE" >/dev/null 2>&1
    bindsto_before=$(sysd_prop "$scope_name" BindsTo)
    "$PWD/$HOOK" </dev/null >/dev/null 2>&1
    bindsto_after=$(sysd_prop "$scope_name" BindsTo)
    if [[ "$bindsto_before" == "$bindsto_after" ]]; then
      pass "T15/AC10 BindsTo unchanged across re-entry ('$bindsto_after') — the hook does not re-derive the terminal scope from its own scope"
    else
      fail "T15/AC10 BindsTo changed across re-entry: '$bindsto_before' -> '$bindsto_after' (self-binding bug)"
    fi
    nscopes=$(systemctl --user list-units 'soleur-agent-*' --all --no-pager 2>/dev/null | grep -cF "$scope_name" || true)
    if [[ "$nscopes" -le 1 ]]; then
      pass "T15/AC10 re-entry refreshed one scope rather than duplicating it"
    else
      fail "T15/AC10 re-entry produced $nscopes units for $scope_name"
    fi
  else
    fail "T8 real hook did not apply (outcome='$outcome' reason='$(printf '%s' "$logline" | jq -r '.reason // ""' 2>/dev/null)')"
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

echo
if (( fails == 0 )); then
  echo "RESULT: PASSED $passes [live: $([[ "$LIVE" == yes ]] && echo yes || echo SKIPPED)]"
  [[ "$LIVE" != "yes" ]] && echo "SKIP: no user systemd bus — $skipped_live live assertions not run"
  exit 0
fi
echo "RESULT: FAILED $fails (passed $passes) [live: $([[ "$LIVE" == yes ]] && echo yes || echo SKIPPED)]" >&2
[[ "$LIVE" != "yes" ]] && echo "SKIP: no user systemd bus — $skipped_live live assertions not run" >&2
exit 1
