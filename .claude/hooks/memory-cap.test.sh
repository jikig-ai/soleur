#!/usr/bin/env bash
# Fixture-based tests for memory-cap.sh (Guard 2 of the runaway-ugrep OOM fix).
#
# Every branch runs against a SYNTHETIC cgroup tree and a synthetic /proc, via
# the script's SOLEUR_CGROUP_MOUNT / SOLEUR_PROC_ROOT injection points. Nothing
# here touches the real /sys/fs/cgroup, and no test allocates memory.
#
# The load-bearing property is FAIL-SOFT: a guard that can block a session is
# worse than the bug it prevents, so every error path must still exit 0. That
# makes exit code alone a weak signal — each assertion therefore also pins the
# emitted SOLEUR_MEMORY_CAP reason and the resulting filesystem state.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/memory-cap.sh"

PASS=0; FAIL=0; TOTAL=0
ok()  { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: $1"; echo "  $2"; }

check() { # check <label> <expected-substring> <actual>
  if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "want substring: $2"$'\n''  got: '"$3"; fi
}

# Build a synthetic cgroup v2 tree + /proc. Echoes the sandbox root.
#   <root>/cg/cgroup.controllers                  — marks the mount as v2
#   <root>/cg/app.slice/cgroup.subtree_control    — delegation state
#   <root>/cg/app.slice/warp.scope/               — the terminal's own scope
#   <root>/proc/<pid>/cgroup                      — unified 0:: line
mk_tree() { # mk_tree <subtree_control> <pid> <pid-cgroup-path>
  local sc="$1" pid="$2" cgpath="$3" root
  root="$(mktemp -d)" || { echo "SETUP FAIL: mktemp" >&2; exit 2; }
  mkdir -p "$root/cg/app.slice/warp.scope" "$root/proc/$pid" \
    || { echo "SETUP FAIL: mkdir" >&2; exit 2; }
  printf 'cpu memory pids\n' > "$root/cg/cgroup.controllers"
  printf '%s\n' "$sc" > "$root/cg/app.slice/cgroup.subtree_control"
  printf '0::%s\n' "$cgpath" > "$root/proc/$pid/cgroup"
  printf '%s\n' "$root"
}

run_hook() { # run_hook <root> <pid> [extra env assignments...]
  local root="$1" pid="$2"; shift 2
  env "$@" \
    SOLEUR_CGROUP_MOUNT="$root/cg" \
    SOLEUR_PROC_ROOT="$root/proc" \
    SOLEUR_MEMORY_CAP_PID="$pid" \
    bash "$HOOK" 2>&1
}

CAP=$((12 * 1024 * 1024 * 1024))

# --- 1. Happy path: sibling cgroup created, capped, process moved in --------
R="$(mk_tree "memory pids" 4242 "/app.slice/warp.scope")"
OUT="$(run_hook "$R" 4242)"; RC=$?
OWN="$R/cg/app.slice/soleur-agent-4242"
[[ $RC -eq 0 ]] && ok "happy: exits 0" || bad "happy: exits 0" "rc=$RC"
check "happy: reports ok" "SOLEUR_MEMORY_CAP ok cgroup=/app.slice/soleur-agent-4242" "$OUT"
[[ -d "$OWN" ]] && ok "happy: owned cgroup created" || bad "happy: owned cgroup created" "missing $OWN"
check "happy: memory.max is the 12 GB cap" "$CAP" "$(cat "$OWN/memory.max" 2>/dev/null)"
check "happy: pid written to cgroup.procs" "4242" "$(cat "$OWN/cgroup.procs" 2>/dev/null)"

# The sharp edge, mechanically: the terminal's own scope must be untouched.
# Capping the scope that holds the terminal could take the terminal down —
# which is the exact failure this whole PR exists to prevent.
[[ ! -e "$R/cg/app.slice/warp.scope/memory.max" ]] \
  && ok "happy: terminal scope NEVER written" \
  || bad "happy: terminal scope NEVER written" "warp.scope/memory.max was created"
rm -rf "$R"

# --- 2. Cap value is honoured (not hardcoded at the write site) -------------
R="$(mk_tree "memory pids" 7 "/app.slice/warp.scope")"
run_hook "$R" 7 SOLEUR_MEMORY_CAP_BYTES=536870912 >/dev/null
check "override: memory.max reads back the overridden value" "536870912" \
  "$(cat "$R/cg/app.slice/soleur-agent-7/memory.max" 2>/dev/null)"
rm -rf "$R"

# --- 3. Idempotent: already inside a cgroup we own -> re-assert, no new dir --
R="$(mk_tree "memory pids" 99 "/app.slice/soleur-agent-99")"
mkdir -p "$R/cg/app.slice/soleur-agent-99"
OUT="$(run_hook "$R" 99)"; RC=$?
[[ $RC -eq 0 ]] && ok "idempotent: exits 0" || bad "idempotent: exits 0" "rc=$RC"
check "idempotent: reports already-capped" "reason=already-capped" "$OUT"
check "idempotent: cap re-asserted" "$CAP" \
  "$(cat "$R/cg/app.slice/soleur-agent-99/memory.max" 2>/dev/null)"
# Must not nest a second cgroup inside the one we already own.
[[ ! -d "$R/cg/app.slice/soleur-agent-99/soleur-agent-99" ]] \
  && ok "idempotent: no nested cgroup" || bad "idempotent: no nested cgroup" "nested dir created"
rm -rf "$R"

# --- 4. FAIL-SOFT: no cgroup v2 at the mount -------------------------------
R="$(mk_tree "memory pids" 5 "/app.slice/warp.scope")"
rm -f "$R/cg/cgroup.controllers"
OUT="$(run_hook "$R" 5)"; RC=$?
[[ $RC -eq 0 ]] && ok "no-v2: exits 0 (fail-soft)" || bad "no-v2: exits 0 (fail-soft)" "rc=$RC"
check "no-v2: names its reason" "reason=no-cgroup-v2" "$OUT"
[[ ! -d "$R/cg/app.slice/soleur-agent-5" ]] \
  && ok "no-v2: creates nothing" || bad "no-v2: creates nothing" "cgroup was created"
rm -rf "$R"

# --- 5. FAIL-SOFT: memory controller not delegated by the parent ------------
R="$(mk_tree "pids" 6 "/app.slice/warp.scope")"
OUT="$(run_hook "$R" 6)"; RC=$?
[[ $RC -eq 0 ]] && ok "no-delegation: exits 0 (fail-soft)" || bad "no-delegation: exits 0 (fail-soft)" "rc=$RC"
check "no-delegation: names its reason" "reason=memory-controller-not-delegated" "$OUT"
[[ ! -d "$R/cg/app.slice/soleur-agent-6" ]] \
  && ok "no-delegation: creates nothing" || bad "no-delegation: creates nothing" "cgroup was created"
rm -rf "$R"

# Guard against a substring-matching bug: `memory` must be matched as a WHOLE
# word in subtree_control, so a controller merely CONTAINING it does not count.
R="$(mk_tree "memoryfoo pids" 61 "/app.slice/warp.scope")"
OUT="$(run_hook "$R" 61)"
check "no-delegation: 'memoryfoo' is not 'memory'" "reason=memory-controller-not-delegated" "$OUT"
rm -rf "$R"

# --- 6. FAIL-SOFT: writes refused (AC8) ------------------------------------
# The read-only parent makes mkdir fail the way a revoked delegation would.
if [[ "$(id -u)" == "0" ]]; then
  echo "SKIP: running as root — chmod cannot make a dir unwritable"
else
  R="$(mk_tree "memory pids" 8 "/app.slice/warp.scope")"
  chmod 555 "$R/cg/app.slice"
  OUT="$(run_hook "$R" 8)"; RC=$?
  [[ $RC -eq 0 ]] && ok "write-refused: session still starts (exit 0)" \
    || bad "write-refused: session still starts (exit 0)" "rc=$RC"
  check "write-refused: names its reason" "reason=mkdir-refused" "$OUT"
  chmod 755 "$R/cg/app.slice"
  rm -rf "$R"
fi

# --- 7. FAIL-SOFT: the claude process cannot be found -----------------------
R="$(mk_tree "memory pids" 11 "/app.slice/warp.scope")"
OUT="$(env SOLEUR_CGROUP_MOUNT="$R/cg" SOLEUR_PROC_ROOT="$R/proc" \
  SOLEUR_MEMORY_CAP_START_PID=999999 bash "$HOOK" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && ok "no-process: exits 0 (fail-soft)" || bad "no-process: exits 0 (fail-soft)" "rc=$RC"
check "no-process: names its reason" "reason=claude-process-not-found" "$OUT"
rm -rf "$R"

# --- 8. FAIL-SOFT: no unified (0::) cgroup line ----------------------------
R="$(mk_tree "memory pids" 12 "/app.slice/warp.scope")"
printf '3:cpu:/legacy\n' > "$R/proc/12/cgroup"
OUT="$(run_hook "$R" 12)"; RC=$?
[[ $RC -eq 0 ]] && ok "no-unified: exits 0 (fail-soft)" || bad "no-unified: exits 0 (fail-soft)" "rc=$RC"
check "no-unified: names its reason" "reason=no-unified-cgroup" "$OUT"
rm -rf "$R"

# --- 9. Ancestry discovery finds the claude process by comm ----------------
# Mirrors the real shape: hook -> bash -> claude -> bash -> warp. `ps` renders
# the claude process as its version directory, never as "claude"/"ugrep" — the
# red herring that kept this class un-root-caused across multiple crashes.
R="$(mk_tree "memory pids" 300 "/app.slice/warp.scope")"
mkdir -p "$R/proc/100" "$R/proc/200"
printf '100 (bash) S 200\n' > "$R/proc/100/stat"; printf 'bash\n'   > "$R/proc/100/comm"
printf '200 (bash) S 300\n' > "$R/proc/200/stat"; printf 'bash\n'   > "$R/proc/200/comm"
printf '300 (claude) S 400\n' > "$R/proc/300/stat"; printf 'claude\n' > "$R/proc/300/comm"
OUT="$(env SOLEUR_CGROUP_MOUNT="$R/cg" SOLEUR_PROC_ROOT="$R/proc" \
  SOLEUR_MEMORY_CAP_START_PID=100 bash "$HOOK" 2>&1)"
check "discovery: walks past bash ancestors to claude" "pid=300" "$OUT"
[[ -d "$R/cg/app.slice/soleur-agent-300" ]] \
  && ok "discovery: caps the discovered pid" || bad "discovery: caps the discovered pid" "no cgroup for 300"
rm -rf "$R"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
