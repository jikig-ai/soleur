#!/usr/bin/env bash
# Guard 2 (backstop) for the runaway-ugrep OOM class — see guardrails.sh
# `guardrails:block-catastrophic-grep-repeat`, which is the primary fix.
#
# Places the live Claude Code process into a dedicated cgroup v2 with a
# memory.max cap, so an UNPREDICTED allocation blowup dies alone instead of
# driving the whole box into swap. On 2026-08-01 a runaway reached 9.5 GB RSS
# and was still climbing, taking a 31 GB desktop to 691 MB free / 88.5% swap
# and (very likely) crashing the terminal with six sessions in it.
#
# WHY cgroup v2 AND NOT `ulimit -v` (measured 2026-08-01, both directions):
#   `ulimit -v` is categorically incompatible with this toolchain. vitest dies
#   instantly at EVERY virtual-address cap tested — 6, 8, 12, 16, 24 and even
#   32 GB — at only 97 MB of ACTUAL RSS, with
#   `WebAssembly.instantiate(): Out of memory`. V8/WASM *reserves* vast virtual
#   address space, and `ulimit -v` counts reservations, not usage, so a 32 GB
#   cap on a 31 GB box still fails. cgroup v2 `memory.max` limits RSS, which is
#   the quantity that actually exhausts the machine.
#
# FAIL-SOFT BY DESIGN. Every error path (no cgroup v2, no controller
# delegation, write refused, process not found) logs and exits 0. A guard that
# can block a session is worse than the bug it prevents. This is the one place
# in the repo where a silent-ish degrade is correct, so each branch names
# itself on stdout for `SOLEUR_MEMORY_CAP` telemetry.
#
# KNOWN RESIDUAL (stated in PR #7151): under a cap the ugrep blowup dies by
# SIGSEGV after ~45 s at 2.7 GB (measured at a 3 GB cap) — ugrep does not
# handle allocation failure gracefully. Guard 2 bounds the damage; it does not
# prevent ~45 s of 100% CPU. Guard 1 is the real fix.
#
# KNOWN CAVEAT: the cgroup is created under a systemd-managed slice that is not
# marked `Delegate=`. systemd's single-writer rule means a `systemctl
# daemon-reload` may garbage-collect it, at which point the processes fall back
# to the parent and the cap silently lapses. That is an acceptable degrade for
# a backstop (it fails toward "no cap", never toward "blocked session"), and
# re-running this hook at the next SessionStart restores it.
#
# NOT `set -e` — fail-soft requires that no single command abort the script.
set -uo pipefail

# 12 GB: ~4.9x the heaviest observed real workload (`tsc --noEmit` peaks at
# 2.45 GB over 66 s; a full vitest run peaks at 898 MB), while bounding a
# runaway to ~38% of a 31 GB box. The 2026-08-01 reproducer would have died
# here instead of reaching 9.5 GB and climbing.
CAP_BYTES="${SOLEUR_MEMORY_CAP_BYTES:-$((12 * 1024 * 1024 * 1024))}"

# Injection points exist ONLY so memory-cap.test.sh can exercise every branch
# against a synthetic cgroup tree; production always uses the defaults.
CGROUP_MOUNT="${SOLEUR_CGROUP_MOUNT:-/sys/fs/cgroup}"
PROC_ROOT="${SOLEUR_PROC_ROOT:-/proc}"

# Only a cgroup whose basename carries this prefix is ever written to. This is
# the mechanical form of the plan's sharp edge "never modify the terminal's own
# scope": the Warp scope holds the terminal's own processes, so capping it
# could take the terminal down — exactly the failure being fixed.
OWNED_PREFIX="soleur-agent-"

say() { printf 'SOLEUR_MEMORY_CAP %s\n' "$*"; }

# --- 1. cgroup v2 present? --------------------------------------------------
if [[ ! -f "$CGROUP_MOUNT/cgroup.controllers" ]]; then
  say "skip reason=no-cgroup-v2 mount=$CGROUP_MOUNT"
  exit 0
fi

# --- 2. Locate the Claude Code process --------------------------------------
# Walk up the PPID chain from this hook. The claude process is identified by
# its resolved exe matching $CLAUDE_CODE_EXECPATH (the same variable the shell
# snapshot's own `grep` shim uses to find the binary), with comm=claude as the
# fallback identifier. NOTE: `ps` renders this process as the version directory
# (e.g. "2.1.220"), never as "claude" or "ugrep" — that presentation is exactly
# why the 2026-08-01 blowup read as "Claude Code is leaking memory" and went
# un-root-caused across multiple crashes.
find_claude_pid() {
  local p="$1" exe comm i
  for (( i = 0; i < 12; i++ )); do
    [[ -z "$p" || "$p" == "0" || "$p" == "1" ]] && break
    exe="$(readlink "$PROC_ROOT/$p/exe" 2>/dev/null || true)"
    comm="$(cat "$PROC_ROOT/$p/comm" 2>/dev/null || true)"
    if [[ -n "${CLAUDE_CODE_EXECPATH:-}" && "$exe" == "$CLAUDE_CODE_EXECPATH" ]] \
       || [[ "$comm" == "claude" ]]; then
      printf '%s\n' "$p"; return 0
    fi
    p="$(awk '{print $4}' "$PROC_ROOT/$p/stat" 2>/dev/null || true)"
  done
  return 1
}

TARGET_PID="${SOLEUR_MEMORY_CAP_PID:-}"
if [[ -z "$TARGET_PID" ]]; then
  TARGET_PID="$(find_claude_pid "${SOLEUR_MEMORY_CAP_START_PID:-$PPID}" || true)"
fi
if [[ -z "$TARGET_PID" || ! -d "$PROC_ROOT/$TARGET_PID" ]]; then
  say "skip reason=claude-process-not-found"
  exit 0
fi

# --- 3. Resolve its current cgroup ------------------------------------------
# cgroup v2 unified line is `0::<path>`.
CUR_REL="$(sed -n 's|^0::||p' "$PROC_ROOT/$TARGET_PID/cgroup" 2>/dev/null | head -1)"
if [[ -z "$CUR_REL" || "$CUR_REL" != /* ]]; then
  say "skip reason=no-unified-cgroup pid=$TARGET_PID"
  exit 0
fi

CUR_ABS="$CGROUP_MOUNT$CUR_REL"
CUR_BASE="${CUR_REL##*/}"

# --- 4. Already in a cgroup we own? Re-assert the cap and stop. --------------
# SessionStart fires on startup|resume|clear|compact, so this runs repeatedly
# within one session; it must be idempotent.
if [[ "$CUR_BASE" == "$OWNED_PREFIX"* ]]; then
  if printf '%s\n' "$CAP_BYTES" > "$CUR_ABS/memory.max" 2>/dev/null; then
    say "ok reason=already-capped cgroup=$CUR_REL bytes=$(cat "$CUR_ABS/memory.max" 2>/dev/null || echo '?')"
  else
    say "degraded reason=reassert-write-refused cgroup=$CUR_REL"
  fi
  exit 0
fi

# --- 5. The parent must delegate the memory controller ----------------------
PARENT_REL="${CUR_REL%/*}"
[[ -z "$PARENT_REL" ]] && PARENT_REL="/"
PARENT_ABS="$CGROUP_MOUNT$PARENT_REL"

if ! grep -qw memory "$PARENT_ABS/cgroup.subtree_control" 2>/dev/null; then
  say "skip reason=memory-controller-not-delegated parent=$PARENT_REL"
  exit 0
fi

# --- 6. Create (or reuse) our own sibling cgroup and cap it -----------------
# A SIBLING of the terminal's scope, never the scope itself. Keyed by pid so
# parallel sessions get independent caps: a shared cgroup would make six honest
# sessions running `tsc` (2.45 GB each) OOM-kill each other's work.
OWN_REL="$PARENT_REL/${OWNED_PREFIX}${TARGET_PID}"
OWN_ABS="$CGROUP_MOUNT$OWN_REL"

if ! mkdir -p "$OWN_ABS" 2>/dev/null; then
  say "degraded reason=mkdir-refused cgroup=$OWN_REL"
  exit 0
fi

if ! printf '%s\n' "$CAP_BYTES" > "$OWN_ABS/memory.max" 2>/dev/null; then
  say "degraded reason=memory-max-write-refused cgroup=$OWN_REL"
  rmdir "$OWN_ABS" 2>/dev/null || true
  exit 0
fi

# Read back — a write that silently did not take is indistinguishable from no
# cap at all, and reads as safety.
READBACK="$(cat "$OWN_ABS/memory.max" 2>/dev/null || true)"
if [[ "$READBACK" != "$CAP_BYTES" ]]; then
  say "degraded reason=memory-max-readback-mismatch want=$CAP_BYTES got=${READBACK:-<empty>}"
  rmdir "$OWN_ABS" 2>/dev/null || true
  exit 0
fi

# --- 7. Move the process in. New children inherit the cap. ------------------
if ! printf '%s\n' "$TARGET_PID" > "$OWN_ABS/cgroup.procs" 2>/dev/null; then
  say "degraded reason=cgroup-procs-write-refused cgroup=$OWN_REL pid=$TARGET_PID"
  rmdir "$OWN_ABS" 2>/dev/null || true
  exit 0
fi

say "ok cgroup=$OWN_REL pid=$TARGET_PID bytes=$CAP_BYTES"
exit 0
