#!/usr/bin/env bash
# Mutation battery for .claude/hooks/memory-backstop.sh (#7166 Phase 5.2).
#
# NOT named *.test.sh deliberately: scripts/test-all.sh auto-globs
# .claude/hooks/*.test.sh, and this needs a live per-user systemd bus and takes
# ~2 minutes. Run it by hand after changing the hook:
#
#   bash .claude/hooks/memory-backstop-mutation-battery.sh "$PWD"
#
# Exits non-zero if ANY mutant survives.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO=$1
REAL_HOOK="$REPO/.claude/hooks/memory-backstop.sh"
UIDN=$(id -u)
UROOT="/sys/fs/cgroup/user.slice/user-$UIDN.slice/user@$UIDN.service"
CTL="$HOME/.config/systemd/user.control"

[[ -f "$REAL_HOOK" ]] || { echo "SETUP FAIL: no hook at $REAL_HOOK" >&2; exit 2; }

FC=$(mktemp -d -t fakeclaude.XXXXXXXX) || exit 2
mkdir -p "$FC/claude/versions" || exit 2
cp /bin/bash "$FC/claude/versions/2.1.220" || exit 2
FAKE="$FC/claude/versions/2.1.220"

killed=0; survived=0
declare -a WRAPPERS=()

cleanup() {
  local w
  # Read from the file, not an array: run_synthetic executes inside a process
  # substitution, so anything it appends to a shell array is lost with that
  # subshell and the trap would reap nothing.
  if [[ -f "$FC/.wrappers" ]]; then
    while IFS= read -r w; do [[ -n "$w" ]] && kill -9 "$w" 2>/dev/null; done < "$FC/.wrappers"
  fi
  # Undo any app.slice mutation M4 may have applied.
  busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
    "app.slice" true 3 \
    "MemoryHigh" "t" 18446744073709551615 \
    "MemoryMax" "t" 18446744073709551615 \
    "MemorySwapMax" "t" 18446744073709551615 >/dev/null 2>&1
  find "$CTL" -path '*soleur*' -delete 2>/dev/null
  rm -rf "$FC" 2>/dev/null
  return 0
}
trap cleanup EXIT INT TERM HUP

# Run one synthetic session against <hook-copy>. Echoes "<wrapper_pid> <scope>".
run_synthetic() {
  local hook=$1 pd
  pd=$(mktemp -d -t fakeproj.XXXXXXXX) || return 1
  mkdir -p "$pd/.claude" || return 1
  # The hook must be a DESCENDANT of the fake claude, so the fake spawns it.
  #
  # `sleep 300 & wait`, NOT a bare `sleep 300`: bash EXECS the last command of a
  # -c string, which replaces the wrapper's image with sleep's. Its /proc exe
  # then stops matching */claude/versions/* mid-run, the hook's identity walk
  # steps straight past it to the operator's REAL claude, and every mutant
  # silently re-reads the real session's already-correct scope and "survives".
  # `wait` is a builtin, so the wrapper stays the fake claude for its whole life.
  "$FAKE" -c "CLAUDE_PROJECT_DIR='$pd' '$hook' </dev/null >/dev/null 2>&1; sleep 300 & wait" \
    >/dev/null 2>&1 &
  local wrapper=$!
  echo "$wrapper" >> "$FC/.wrappers"
  # Wait for the wrapper's OWN scope, not merely for any soleur-agent-* cgroup:
  # this wrapper is a descendant of the operator's real (already adopted)
  # session, so it INHERITS soleur-agent-<real>.scope at birth. A substring test
  # matches that inherited value on the first iteration and returns before the
  # hook has created anything.
  local i cg want="soleur-agent-${wrapper}.scope"
  for i in $(seq 1 60); do
    cg=$(cut -d: -f3 < "/proc/$wrapper/cgroup" 2>/dev/null)
    [[ "${cg##*/}" == "$want" ]] && break
    sleep 0.1
  done
  echo "$wrapper|$pd|${cg##*/}"
}

teardown_synthetic() { # <wrapper>
  kill -9 "$1" 2>/dev/null
  sleep 0.3
}

scope_file() { # <wrapper> <file>
  local cg; cg=$(cut -d: -f3 < "/proc/$1/cgroup" 2>/dev/null)
  cat "/sys/fs/cgroup$cg/$2" 2>/dev/null
}

report() { # <name> <assertion> <expected> <actual>
  if [[ "$3" == "$4" ]]; then
    printf '  SURVIVED %-26s %s (expected %s, got %s)\n' "$1" "$2" "$3" "$4" >&2
    survived=$((survived+1))
  else
    printf '  KILLED   %-26s by %-34s (want %s, mutant gave %s)\n' "$1" "$2" "$3" "$4"
    killed=$((killed+1))
  fi
}

mk_mutant() { # <name> -> path to mutated copy
  local d; d=$(mktemp -d -t mut.XXXXXXXX) || return 1
  cp "$REAL_HOOK" "$d/memory-backstop.sh" || return 1
  chmod +x "$d/memory-backstop.sh" || return 1
  echo "$d/memory-backstop.sh"
}

# ---------------------------------------------------------------- BASELINE
echo "== baseline (unmutated): every property must read back correct =="
h=$(mk_mutant) || exit 2
IFS='|' read -r W PD SC < <(run_synthetic "$h")

# POSITIVE CONTROL. If the hook adopted the operator's real session instead of
# this synthetic one, every mutant below reads back the real scope's
# already-correct properties and reports SURVIVED — an instrument that returns
# the same answer on every arm. Measured: that is exactly what happened before
# the wrapper's exec bug was fixed, and all 10 mutants "survived" against a
# perfectly good hook.
if [[ "$SC" != "soleur-agent-$W.scope" ]]; then
  echo "SETUP FAIL: adopted '$SC' but the synthetic wrapper is pid $W" >&2
  echo "  the hook walked past the fake claude to a real session — the battery would measure nothing" >&2
  exit 2
fi
echo "  positive control OK: adopted the synthetic wrapper (pid $W), not the real session"

b_oom=$(systemctl --user show "$SC" -p OOMPolicy --value 2>/dev/null)
b_swap=$(scope_file "$W" memory.swap.max)
b_high=$(scope_file "$W" memory.high)
b_max=$(scope_file "$W" memory.max)
b_bt=$(systemctl --user show "$SC" -p BindsTo --value 2>/dev/null)
b_mop=$(systemctl --user show soleur-agents.slice -p ManagedOOMPreference --value 2>/dev/null)
printf '  scope=%s OOMPolicy=%s swap.max=%s high=%s max=%s BindsTo=%s slice.MOP=%s\n' \
  "$SC" "$b_oom" "$b_swap" "$b_high" "$b_max" "$b_bt" "$b_mop"
teardown_synthetic "$W"
if [[ "$b_oom" != "continue" || "$b_swap" != "0" || "$b_high" != "6442450944" \
   || "$b_max" != "7516192768" || -z "$b_bt" || "$b_mop" != "avoid" ]]; then
  echo "SETUP FAIL: baseline is already wrong — every RED below would be meaningless" >&2
  exit 2
fi
echo "  baseline OK"
echo

# ---------------------------------------------------------------- M2 (per property)
# VALUE mutations, not deletions. Deleting a property line forces a matching
# decrement of the D-Bus array count, and several property literals
# ("MemorySwapMax" "t" 0, "OOMPolicy", "MemoryHigh") appear in BOTH the slice
# call and the scope call — so a first-match regex edits one call while
# decrementing the other's count, producing a malformed request that fails for a
# reason unrelated to the property under test. A value mutation keeps the arity
# valid and isolates exactly the property being tested.
#
# Each mutation is asserted to have landed; a mutation that silently fails to
# apply reports SURVIVED against an unmutated hook.
echo "== M2: mis-set one declared property in a D-Bus array =="

mutated_or_die() { grep -qF "$2" "$1" || { echo "SETUP FAIL: mutation did not land: $2" >&2; exit 2; }; }

# M2a OOMPolicy=stop on the scope — systemd then stops the WHOLE scope on any
# OOM, killing claude itself. (Note: `continue` is the measured DEFAULT for a
# transient scope on systemd 259, so OMITTING the property is not observable;
# mis-setting it to the dangerous value is.)
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"OOMPolicy" "s" "continue"/"OOMPolicy" "s" "stop"/' "$h"
mutated_or_die "$h" '"OOMPolicy" "s" "stop"'
IFS='|' read -r W PD SC < <(run_synthetic "$h")
report "M2a-OOMPolicy-stop" "T8/AC8 OOMPolicy readback" "continue" "$(systemctl --user show "$SC" -p OOMPolicy --value 2>/dev/null)"
teardown_synthetic "$W"

# M2b scope MemorySwapMax unset — anchored on the following OOMPolicy line so it
# targets the SCOPE call, not the slice call (whose next line is ManagedOOMPreference).
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"MemorySwapMax" "t" 0 \\\n(\s*)"OOMPolicy"/"MemorySwapMax" "t" 18446744073709551615 \\\n$1"OOMPolicy"/' "$h"
mutated_or_die "$h" '"MemorySwapMax" "t" 18446744073709551615'
IFS='|' read -r W PD SC < <(run_synthetic "$h")
report "M2b-scope-swap-uncapped" "T8/AC5 memory.swap.max readback" "0" "$(scope_file "$W" memory.swap.max)"
teardown_synthetic "$W"

# M2c scope MemoryHigh mis-set
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"MemoryHigh" "t" "\$SCOPE_HIGH_BYTES"/"MemoryHigh" "t" 3221225472/' "$h"
mutated_or_die "$h" '"MemoryHigh" "t" 3221225472'
IFS='|' read -r W PD SC < <(run_synthetic "$h")
report "M2c-scope-high-wrong" "T8 memory.high readback" "6442450944" "$(scope_file "$W" memory.high)"
teardown_synthetic "$W"

# M2d scope MemoryMax mis-set — the cap that actually terminates a runaway
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"MemoryMax" "t" "\$SCOPE_MAX_BYTES"/"MemoryMax" "t" 3221225472/' "$h"
mutated_or_die "$h" '"MemoryMax" "t" 3221225472'
IFS='|' read -r W PD SC < <(run_synthetic "$h")
report "M2d-scope-max-wrong" "T8 memory.max readback" "7516192768" "$(scope_file "$W" memory.max)"
teardown_synthetic "$W"

# M2e slice ManagedOOMPreference — without `avoid`, oomd's candidate set makes
# the whole fleet one victim. ("auto" is NOT a valid value; the accepted set is
# none|avoid|omit, and passing an invalid one makes the whole call fail.)
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"ManagedOOMPreference" "s" "avoid"/"ManagedOOMPreference" "s" "none"/' "$h"
mutated_or_die "$h" '"ManagedOOMPreference" "s" "none"'
IFS='|' read -r W PD SC < <(run_synthetic "$h")
report "M2e-slice-MOP-none" "T13/AC15 slice ManagedOOMPreference" "avoid" "$(systemctl --user show soleur-agents.slice -p ManagedOOMPreference --value 2>/dev/null)"
teardown_synthetic "$W"
# restore the real preference for subsequent mutants
busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
  org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
  "soleur-agents.slice" true 1 "ManagedOOMPreference" "s" "avoid" >/dev/null 2>&1

echo

# ---------------------------------------------------------------- M3
echo "== M3: drop BindsTo/After — the terminal's kill switch =="
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"\$scope" "fail" 10/"\$scope" "fail" 8/;
             s/^\s*"BindsTo" "as" 1 "\$terminal_scope" \\\n//m;
             s/^\s*"After" "as" 1 "\$terminal_scope" \\\n//m' "$h"
IFS='|' read -r W PD SC < <(run_synthetic "$h")
got_bt=$(systemctl --user show "$SC" -p BindsTo --value 2>/dev/null)
if [[ -z "$got_bt" ]]; then
  printf '  KILLED   %-26s by %-34s (want a terminal scope, mutant gave none)\n' "M3-drop-BindsTo" "T11/AC3 BindsTo + behavioural reap"
  killed=$((killed+1))
else
  printf '  SURVIVED %-26s BindsTo=%s\n' "M3-drop-BindsTo" "$got_bt" >&2
  survived=$((survived+1))
fi
teardown_synthetic "$W"
echo

# ---------------------------------------------------------------- M4
echo "== M4: SetUnitProperties on the PARENT slice (the mutant that beat #7151) =="
before_app_high=$(cat "$UROOT/app.slice/memory.high" 2>/dev/null)
h=$(mk_mutant) || exit 2
perl -0pi -e 's/SetUnitProperties "sba\(sv\)" \\\n(\s*)"\$SLICE_NAME"/SetUnitProperties "sba(sv)" \\\n$1"app.slice"/' "$h"
grep -q '"app.slice"' "$h" || { echo "SETUP FAIL: M4 mutation did not land" >&2; exit 2; }
IFS='|' read -r W PD SC < <(run_synthetic "$h")
after_app_high=$(cat "$UROOT/app.slice/memory.high" 2>/dev/null)
report "M4-cap-parent-slice" "T10/AC7 subtree sweep" "$before_app_high" "$after_app_high"
teardown_synthetic "$W"
busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
  org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
  "app.slice" true 3 \
  "MemoryHigh" "t" 18446744073709551615 \
  "MemoryMax" "t" 18446744073709551615 \
  "MemorySwapMax" "t" 18446744073709551615 >/dev/null 2>&1
echo "  (app.slice limits restored to: high=$(cat "$UROOT/app.slice/memory.high" 2>/dev/null))"
echo

# ---------------------------------------------------------------- M5
echo "== M5: drop runtime=true — permanently mutates the operator's systemd config =="
ctl_before=$(find "$CTL" -type f 2>/dev/null | sort | sha256sum)
h=$(mk_mutant) || exit 2
perl -0pi -e 's/"\$SLICE_NAME" true 4/"\$SLICE_NAME" false 4/' "$h"
grep -q '"\$SLICE_NAME" false 4' "$h" || { echo "SETUP FAIL: M5 mutation did not land" >&2; exit 2; }
IFS='|' read -r W PD SC < <(run_synthetic "$h")
ctl_after=$(find "$CTL" -type f 2>/dev/null | sort | sha256sum)
report "M5-drop-runtime-true" "T10/AC7 user.control byte-identical" "$ctl_before" "$ctl_after"
teardown_synthetic "$W"
find "$CTL" -path '*soleur*' -delete 2>/dev/null
echo

# ---------------------------------------------------------------- M6
echo "== M6: adopt only claude's own PID (drop the tree) =="
h=$(mk_mutant) || exit 2
perl -0pi -e 's/^(\s*)for p in "\$\{tree\[@\]\}"; do$/$1for p in ; do/m' "$h"
grep -q 'for p in ; do' "$h" || { echo "SETUP FAIL: M6 mutation did not land" >&2; exit 2; }
IFS='|' read -r W PD SC < <(run_synthetic "$h")
# the fake claude has a `sleep 300` child; with the sweep gone it stays outside
kids=$(ps -eo pid=,ppid= | awk -v r="$W" '$2==r {print $1}')
inscope=0; outside=0
for k in $kids; do
  kc=$(cut -d: -f3 < "/proc/$k/cgroup" 2>/dev/null)
  if [[ "$kc" == *"$SC" ]]; then inscope=$((inscope+1)); else outside=$((outside+1)); fi
done
report "M6-no-tree-sweep" "T9/AC11 independent tree re-walk" "0" "$outside"
teardown_synthetic "$W"
echo

# ---------------------------------------------------------------- M7
echo "== M7: re-derive the terminal scope on re-entry (self-binding bug) =="
# Observed via the LOGGED terminal_scope, not the unit's BindsTo. BindsTo is not
# a settable runtime property, so the re-entry refresh never re-sends it and the
# unit's value cannot change — the assertion that actually carries AC10's claim
# ("the hook does not re-derive the terminal scope from its own scope") is that
# the SECOND run records the same terminal_scope as the first. Under the mutant
# the hook re-derives from its own cgroup, which is now its own scope.
#
# The wrapper runs the hook TWICE so the second invocation is a genuine re-entry
# by a descendant of the adopted process.
run_reentry() { # <hook> -> "<wrapper>|<projectdir>"
  local hook=$1 pd
  pd=$(mktemp -d -t fakeproj.XXXXXXXX) || return 1
  mkdir -p "$pd/.claude" || return 1
  "$FAKE" -c "CLAUDE_PROJECT_DIR='$pd' '$hook' </dev/null >/dev/null 2>&1; \
              sleep 1; \
              CLAUDE_PROJECT_DIR='$pd' '$hook' </dev/null >/dev/null 2>&1; \
              sleep 300 & wait" >/dev/null 2>&1 &
  local w=$!
  echo "$w" >> "$FC/.wrappers"
  local i
  for i in $(seq 1 80); do
    [[ "$(wc -l < "$pd/.claude/.memory-backstop.jsonl" 2>/dev/null || echo 0)" -ge 2 ]] && break
    sleep 0.1
  done
  echo "$w|$pd"
}

for arm in baseline mutant; do
  if [[ "$arm" == baseline ]]; then
    h=$(mk_mutant) || exit 2
  else
    h=$(mk_mutant) || exit 2
    perl -0pi -e 's/terminal_scope="\$\{existing_bt:-\$terminal_scope\}"/terminal_scope="\$(terminal_scope_for "\$claude_pid")"/' "$h"
    grep -q 'terminal_scope="\$(terminal_scope_for' "$h" || { echo "SETUP FAIL: M7 mutation did not land" >&2; exit 2; }
  fi
  IFS='|' read -r W PD < <(run_reentry "$h")
  ts1=$(head -1 "$PD/.claude/.memory-backstop.jsonl" 2>/dev/null | jq -r '.terminal_scope // ""' 2>/dev/null)
  ts2=$(tail -1 "$PD/.claude/.memory-backstop.jsonl" 2>/dev/null | jq -r '.terminal_scope // ""' 2>/dev/null)
  if [[ "$arm" == baseline ]]; then
    if [[ -n "$ts1" && "$ts1" == "$ts2" ]]; then
      echo "  (M7 baseline: terminal_scope preserved across re-entry: '$ts1')"
    else
      echo "SETUP FAIL: M7 baseline did not preserve terminal_scope ('$ts1' -> '$ts2')" >&2
      teardown_synthetic "$W"; exit 2
    fi
  else
    report "M7-self-bind-on-reentry" "T15/AC10 logged terminal_scope stable" "$ts1" "$ts2"
  fi
  teardown_synthetic "$W"
done
echo

echo "killed=$killed survived=$survived"
[[ "$survived" -eq 0 ]] || exit 1
