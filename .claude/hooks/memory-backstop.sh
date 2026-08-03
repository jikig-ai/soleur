#!/usr/bin/env bash
# SessionStart hook — bounds an agent session's memory via a systemd transient
# scope (ADR-158, #7166).
#
# WHAT HAPPENED. On 2026-08-01 a one-line regex search against a single 21 kB
# markdown file reached 9.5 GB RSS in 171 s at 99 % CPU and was still climbing,
# driving a 31 GB box to 691 MB free with swap at 88.5 %. The terminal crashed,
# killing six concurrent agent sessions and their in-flight work.
#
# WHAT THIS DOES. Adopts this session's whole process tree into
# `soleur-agent-<pid>.scope` under a shared `soleur-agents.slice`, with a
# per-session cap and a fleet-wide cap. systemd is the SINGLE WRITER to the
# cgroup hierarchy: this hook never creates a cgroup directory itself.
#
# WHAT THIS DOES NOT DO, stated up front: under a cap that runaway dies by
# SIGSEGV after ~45 s at 2.7 GB (measured at a 3 GB cap) — ugrep does not handle
# allocation failure gracefully. A cap BOUNDS DAMAGE; it does not prevent ~45 s
# of 100 % CPU on one core. What it does prevent is the memory-and-swap
# exhaustion that froze the desktop and killed six sessions.
#
# WHY THE SANCTIONED API. The previous attempt (#7151, closed unmerged) wrote a
# RAW cgroup v2 directory and moved the live process into it. That violated
# systemd's single-writer invariant, leaked a cgroup per session, and — because
# the new cgroup was a SIBLING of the terminal's scope — the process stopped
# being a scope member, so closing the terminal no longer reaped a runaway. For
# a non-technical operator that is the only stop mechanism there is.
# `StartTransientUnit` gives the identical kernel effect with systemd as the
# single writer, the cap visible to `systemctl --user status`, and the scope
# self-cleaning when its last process exits.
#
# NO TEST SEAMS. #7151 read four unvalidated test-injection env vars in
# production; one of them skipped the identity check entirely and another
# (`_BYTES=0`) was a one-token session kill. This file is split into functions
# plus `main`, guarded by the standard `BASH_SOURCE == $0` idiom: tests SOURCE it
# and call functions with ordinary arguments, production EXECS it. Those defects
# are not defended against here — they are unrepresentable. The one environment
# variable this hook honours is the documented kill switch
# SOLEUR_DISABLE_MEMORY_BACKSTOP, matching four sibling hooks.
#
# NEVER BLOCKS. `exit 0` on every path, `set -e` deliberately NOT used (the
# duplicate-unit branch returns rc=1 by design). It can decline to protect; it
# cannot block a session. Every non-applied outcome is logged with a
# machine-readable reason.
#
# OUTPUT CHANNEL. `systemMessage` on STDOUT is the operator-visible channel for
# an exit-0 hook; plain stderr is DISCARDED (.claude/hooks/README.md). Messages
# are EDGE-TRIGGERED only — never per-session. And every `busctl` call's stdout
# is redirected to /dev/null: `busctl call` prints the returned job object path,
# and a SessionStart hook's stdout is injected into session context.

# ------------------------------------------------------------------ constants
# All four cap values live here so raising one is a one-token change. They are
# re-validated against a two-sided band on every run (see validate_caps): a
# floor alone does not encode "below the harm point".
readonly SCOPE_HIGH_BYTES=6442450944      #  6 GiB — throttle; above the 3.85 GiB honest peak
readonly SCOPE_MAX_BYTES=7516192768       #  7 GiB — kill; 8.0 GB with baseline, vs the 9.5 GB harm point
readonly FLEET_HIGH_BYTES=17179869184     # 16 GiB — clears four concurrent `tsc`
readonly FLEET_MAX_BYTES=21474836480      # 20 GiB — last resort: three simultaneously-maxed sessions

readonly SLICE_NAME="soleur-agents.slice"
readonly MAX_TREE=256
readonly MAX_WALK_HOPS=8

# ------------------------------------------------------------------ helpers

# Canonicalize via cd -P / pwd -P so a symlinked .claude/ does not produce two
# disjoint flock inodes (precedent: agent-token-tee.sh, skill-invocation-logger.sh).
_repo_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    (cd -P "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P) || echo "$CLAUDE_PROJECT_DIR"
    return
  fi
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)
}

# Any /proc-derived string that reaches a systemMessage is untrusted. A cgroup
# basename is the one such string here, and the scope directory is user-owned
# (Delegate=true), so anything running inside the session — a build script, an
# npm postinstall, an MCP server — can create a cgroup whose name ends in
# `.scope` and contains arbitrary bytes. That name would otherwise be emitted
# into the NEXT session's context: session N's untrusted code writing into
# session N+1's model context, and raw ANSI into the operator's terminal.
# jq escapes control bytes correctly for transport, which does not help — the
# consumer un-escapes them.
_sanitize() {
  local s=${1:-}
  [[ "$s" =~ ^[A-Za-z0-9:._@-]+$ ]] || { printf '<unprintable>'; return 0; }
  printf '%s' "$s"
}

# Byte counts in operator-facing text are rendered in GiB. "7516192768-byte" is
# not a limit a non-technical operator can act on.
_human_bytes() {
  local b=${1:-0}
  [[ "$b" =~ ^[0-9]+$ ]] || { printf '%s' "$b"; return 0; }
  awk -v b="$b" 'BEGIN{ printf (b >= 1073741824 ? "%.1f GiB" : "%d bytes"), (b >= 1073741824 ? b/1073741824 : b) }'
}

# Operator-visible channel for an exit-0 hook.
emit_message() {
  local msg=$1
  jq -n --arg m "$msg" '{systemMessage:$m}' 2>/dev/null
}

# Two-sided range validation. Each floor is set so the band CANNOT admit a value
# this design rejected: 4 GiB per-session high sits below the 3.85 GiB measured
# honest concurrency peak (a brake that low is a permanent tax, not a brake), and
# the per-session ceiling keeps the cap below the 9.5 GB harm point after the
# ~0.5 GiB non-migrated baseline is added back.
validate_caps() {
  local sh=${1:-} sm=${2:-} fh=${3:-} fm=${4:-}
  local v
  for v in "$sh" "$sm" "$fh" "$fm"; do
    [[ "$v" =~ ^[0-9]+$ ]] || { printf 'not_numeric:%s' "$v"; return 1; }
  done
  #  3 GiB .. 8 GiB : floor > the 2.45 GB tsc peak; ceiling 8.59 GB < 9.5 GB harm point
  (( sm >= 3221225472 && sm <= 8589934592 )) || { printf 'scope_max:%s' "$sm"; return 1; }
  #  5 GiB .. < scope_max : floor clears the 3.85 GiB honest concurrency peak
  (( sh >= 5368709120 && sh < sm ))          || { printf 'scope_high:%s' "$sh"; return 1; }
  # 10 GiB .. 24 GiB : floor >= one session ceiling + the idle fleet
  (( fm >= 10737418240 && fm <= 25769803776 )) || { printf 'fleet_max:%s' "$fm"; return 1; }
  # 14 GiB .. < fleet_max : floor clears three concurrent `tsc` (13.35 GiB)
  (( fh >= 15032385536 && fh < fm ))         || { printf 'fleet_high:%s' "$fh"; return 1; }
  # Cross-LEVEL relation. Each band above is independent, so they happily admit a
  # combination that cannot compose — e.g. scope_max 8 GiB with fleet_max 10 GiB,
  # a fleet that cannot hold two sessions at their own ceiling. The per-level
  # bands encode "is this value sane"; this encodes "do these two levels agree".
  (( fm >= 2 * sm )) || { printf 'fleet_max_below_two_sessions:%s' "$fm"; return 1; }
  return 0
}

# Label-anchored PPid. NEVER `awk '{print $4}'` over /proc/<pid>/stat: that
# breaks on any ancestor whose comm contains a space, and fails SOFT — it yields
# a garbage pid that reads as "process not found".
read_ppid() {
  local pid=$1 procroot=${2:-/proc}
  local line
  # Probe readability first: a PID can vanish mid-walk (this hook runs while the
  # session is actively spawning and reaping children), and letting the redirect
  # fail would spray "No such file or directory" onto a SessionStart hook's
  # stderr on every run.
  [[ -r "$procroot/$pid/status" ]] || return 1
  while IFS= read -r line; do
    if [[ "$line" == PPid:* ]]; then
      line=${line#PPid:}
      printf '%s' "${line//[[:space:]]/}"
      return 0
    fi
  done < "$procroot/$pid/status" 2>/dev/null
  return 1
}

# starttime is /proc/<pid>/stat field 22. `comm` (field 2) is parenthesised and
# is the ONLY field that can contain the delimiter — including ')' itself — so
# split on the LAST ')' and index from there. Used to disambiguate PID reuse.
read_starttime() {
  local pid=$1 procroot=${2:-/proc}
  local raw tail_
  raw=$(cat "$procroot/$pid/stat" 2>/dev/null) || return 1
  [[ "$raw" == *')'* ]] || return 1
  tail_=${raw##*')'}
  # After the last ')': field 3 (state) onward. starttime is field 22 overall,
  # i.e. the 20th token here.
  # shellcheck disable=SC2086
  set -- $tail_
  [[ $# -ge 20 ]] || return 1
  printf '%s' "${20}"
}

# Positive identity match, and adopt NOTHING on failure. `readlink /proc/<pid>/exe`
# returns EMPTY (not an error) for an exited process, so a walk that treats "no
# match" as "keep walking" and then adopts the last pid examined could put
# warp-terminal or the login shell under a 7 GiB cap bound to itself.
# Echoes "<pid> <identity-signal>" on success.
discover_claude_pid() {
  local pid=${1:-$$} procroot=${2:-/proc}
  local hops=0 exe comm

  while (( hops < MAX_WALK_HOPS )); do
    hops=$((hops + 1))
    # Reject unusable / dangerous candidates outright.
    if [[ ! "$pid" =~ ^[0-9]+$ ]] || (( pid <= 1 )); then
      return 1
    fi

    exe=$(readlink "$procroot/$pid/exe" 2>/dev/null || true)
    comm=$(cat "$procroot/$pid/comm" 2>/dev/null || true)

    if [[ -n "$exe" && "$exe" == */claude/versions/* ]]; then
      printf '%s exe' "$pid"; return 0
    fi
    if [[ -n "${CLAUDE_CODE_EXECPATH:-}" && -n "$exe" && "$exe" == "${CLAUDE_CODE_EXECPATH}" ]]; then
      printf '%s execpath' "$pid"; return 0
    fi
    if [[ "$comm" == "claude" ]]; then
      printf '%s comm' "$pid"; return 0
    fi

    pid=$(read_ppid "$pid" "$procroot") || return 1
  done
  return 1
}

# Whole descendant set in ONE bounded /proc pass. SessionStart runs CONCURRENTLY
# with MCP startup and MCP servers are direct children of `claude`, so adopting
# only claude's own pid loses that race and leaves headless Chrome — the largest
# memory risk on the box — outside the cap.
collect_descendants() {
  local root=$1 procroot=${2:-/proc}
  local d pid ppid
  local -A parent=()
  local -a order=()

  for d in "$procroot"/[0-9]*; do
    pid=${d##*/}
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    ppid=$(read_ppid "$pid" "$procroot") || continue
    parent[$pid]=$ppid
    order+=("$pid")
  done

  local -A keep=([$root]=1)
  local changed=1 pass=0
  while (( changed == 1 && pass < 12 )); do
    changed=0; pass=$((pass + 1))
    for pid in "${order[@]}"; do
      [[ -n "${keep[$pid]:-}" ]] && continue
      if [[ -n "${keep[${parent[$pid]:-}]:-}" ]]; then keep[$pid]=1; changed=1; fi
    done
  done

  # NOTE: iteration order of an associative array is bash hash order, i.e.
  # arbitrary. Above MAX_TREE the kept subset is therefore arbitrary too, and it
  # could drop the very process the design names as the biggest risk (headless
  # Chrome under an MCP server). Emit a sentinel line so the caller can record
  # that truncation happened rather than silently capping an arbitrary subset.
  local n=0
  for pid in "${!keep[@]}"; do
    if (( n >= MAX_TREE )); then printf 'TRUNCATED\n'; break; fi
    printf '%s\n' "$pid"; n=$((n + 1))
  done
}

# The terminal's own scope, from cgroup membership. Must end in `.scope`; the
# name contains dots and dashes (app-gnome-dev.warp.Warp-3591813.scope) and must
# be passed quoted.
terminal_scope_for() {
  local pid=$1
  local cg base
  cg=$(cut -d: -f3 < "/proc/$pid/cgroup" 2>/dev/null | head -1) || return 1
  [[ -n "$cg" ]] || return 1
  base=${cg##*/}
  [[ "$base" == *.scope ]] || return 1
  printf '%s' "$base"
}

# Kill attribution and near-miss. Fires on INCREASE, never on non-zero:
# memory.events counters are monotonic for the life of the cgroup, so a
# non-zero test would re-emit the same post-mortem on every SessionStart
# forever, for a kill the operator already saw.
#
# memory.events is read from a PATH ARGUMENT, deliberately not an env var —
# this must not re-introduce the injection surface the design removed.
#
# The wording must not claim causation: at slice MemoryMax the kernel kills the
# largest task in the subtree, which can sit in ANOTHER session's scope, so a
# message may reach a session that did not cause the kill.
attribution_message() {
  local events_path=$1 peak_path=${2:-} last_oom=${3:-0} last_high=${4:-0}
  local oom_kill high peak_h=""
  [[ -r "$events_path" ]] || return 0
  oom_kill=$(awk '/^oom_kill /{print $2}' "$events_path" 2>/dev/null)
  high=$(awk '/^high /{print $2}' "$events_path" 2>/dev/null)
  [[ "$oom_kill" =~ ^[0-9]+$ ]] || oom_kill=0
  [[ "$high" =~ ^[0-9]+$ ]] || high=0
  [[ "$last_oom" =~ ^[0-9]+$ ]] || last_oom=0
  [[ "$last_high" =~ ^[0-9]+$ ]] || last_high=0

  if [[ -n "$peak_path" && -r "$peak_path" ]]; then
    local pb; pb=$(cat "$peak_path" 2>/dev/null)
    [[ "$pb" =~ ^[0-9]+$ ]] && peak_h=$(awk -v b="$pb" 'BEGIN{printf "%.2f GiB", b/1073741824}')
  fi

  if (( oom_kill > last_oom )); then
    printf '%s' "Soleur memory backstop: a process in this session was terminated by the kernel after this session's memory cap was reached.

What this means: a command running here hit this session's $(_human_bytes "$SCOPE_MAX_BYTES") memory limit${peak_h:+ (peak ${peak_h})} and the kernel stopped the largest process in the session. Uncommitted work in that command may be lost. This is not a crash in your code.

Note: the fleet-wide limit is shared, so a kill can occasionally land in a session other than the one that grew.

To raise this session's limit now (replace <pid> with the number in the scope name from \`systemctl --user list-units 'soleur-agent-*'\`):
  systemctl --user set-property --runtime soleur-agent-<pid>.scope MemoryHigh=infinity MemoryMax=infinity
To turn the backstop off entirely: set SOLEUR_DISABLE_MEMORY_BACKSTOP=1"
    return 0
  fi

  if (( high > last_high )); then
    printf '%s' "Soleur memory backstop: this session crossed its memory brake $(( high - last_high )) time(s)${peak_h:+ (peak ${peak_h})} but nothing was terminated.

This is a warning, not an error — the brake throttles before the hard limit. If it keeps happening, the cap is probably too low for your workload; raise it in .claude/hooks/memory-backstop.sh."
    return 0
  fi
  return 0
}

# ------------------------------------------------------------------ main
main() {
  set -uo pipefail   # deliberately NOT -e; scoped to main so sourcing leaks nothing

  local project_dir log_file lock_file stamp_file
  project_dir=$(_repo_root)
  log_file="$project_dir/.claude/.memory-backstop.jsonl"
  lock_file="$project_dir/.claude/.memory-backstop.lock"
  stamp_file="$project_dir/.claude/.memory-backstop.stamp"
  mkdir -p "$project_dir/.claude" 2>/dev/null

  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local outcome="skipped" reason="" scope="" terminal_scope="" tree_size=0
  local identity_signal="" claude_pid="" msg=""
  local slice_high_before="" slice_max_before=""
  local scope_high_after="" scope_max_after="" scope_swap_after=""
  local slice_high_after="" slice_max_after="" slice_swap_after=""
  local attached=0 tree_truncated="false"

  _log() {
    local rotator
    rotator="$(dirname "${BASH_SOURCE[0]}")/lib/log-rotation.sh"
    if [[ -f "$rotator" ]]; then
      # shellcheck source=/dev/null
      source "$rotator" 2>/dev/null || true
      declare -F rotate_if_needed >/dev/null 2>&1 && rotate_if_needed "$log_file" 2>/dev/null
    fi
    local line
    if command -v jq >/dev/null 2>&1; then
      line=$(jq -nc \
        --arg ts "$ts" --arg outcome "$outcome" --arg reason "$reason" \
        --arg scope "$scope" --arg tscope "$terminal_scope" --arg slice "$SLICE_NAME" \
        --arg sig "$identity_signal" --arg pid "$claude_pid" \
        --arg shb "$slice_high_before" --arg smb "$slice_max_before" \
        --argjson tree "$tree_size" \
        --argjson sh "$SCOPE_HIGH_BYTES" --argjson sm "$SCOPE_MAX_BYTES" \
        --argjson fh "$FLEET_HIGH_BYTES" --argjson fm "$FLEET_MAX_BYTES" \
        '{schema:1, ts:$ts, pid:(($pid|tonumber?) // null), tree_size:$tree, scope:$scope,
          terminal_scope:$tscope, slice:$slice, scope_high:$sh, scope_max:$sm,
          slice_high:$fh, slice_max:$fm, slice_high_before:$shb, slice_max_before:$smb,
          swap_max:0, identity_signal:$sig, outcome:$outcome, reason:$reason}' 2>/dev/null)
    fi
    # An empty $line means the jq filter produced no object (an empty stream from
    # a `?`-suppressed conversion, say). Writing it would append a blank line and
    # the sink would look present-but-useless, so fall back to a minimal record
    # that always has the two fields any reader needs.
    [[ -z "$line" ]] && line="{\"schema\":1,\"ts\":\"$ts\",\"outcome\":\"$outcome\",\"reason\":\"$reason\",\"log_degraded\":true}"
    printf '%s\n' "$line" >> "$log_file" 2>/dev/null
  }

  # (1) Kill switch first. R12: if this is set you are unprotected and nothing
  # else will tell you.
  if [[ "${SOLEUR_DISABLE_MEMORY_BACKSTOP:-}" == "1" ]]; then
    reason="disabled"; _log; exit 0
  fi

  # (2) Environment gates. Gate on the SOCKET, not on parsing a busctl error
  # string — an error-string match rots with every systemd release.
  if ! command -v busctl >/dev/null 2>&1; then
    reason="no_busctl"; _log; exit 0
  fi
  # jq is required, not optional. A hand-rolled JSON fallback was tried and
  # removed: it wrote lines WITHOUT the counter fields while the reader
  # (_last_logged) required jq to read them, so `last_oom_kill` was 0 forever and
  # the OOM post-mortem re-emitted on EVERY SessionStart — inverting the exact
  # edge-triggered contract the increase-comparison exists to enforce. Declining
  # loudly beats a second, silently-wrong output mode.
  if ! command -v jq >/dev/null 2>&1; then
    reason="no_jq"; _log; exit 0
  fi
  local bus="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
  if [[ ! -S "$bus" ]]; then
    reason="no_bus"; _log; exit 0
  fi

  # macOS ships no `timeout`; hardcoding it made a sibling hook exit 127 and go
  # silently dark. A wedged D-Bus must not stall every SessionStart.
  local TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 5)

  if ! "${TO[@]}" busctl --user --no-pager status >/dev/null 2>&1; then
    reason="no_bus"; _log; exit 0
  fi

  # (3) Validate caps BEFORE any D-Bus call. Refusing is correct: a cap outside
  # the validated band is either useless or dangerous, and a hook that
  # half-applies is worse than one that declines. Refusal ALWAYS messages —
  # these are readonly constants in a tracked file, so this can essentially only
  # fire after an edit, and the person who just edited them is the one who needs
  # to be told.
  local bad
  if ! bad=$(validate_caps "$SCOPE_HIGH_BYTES" "$SCOPE_MAX_BYTES" "$FLEET_HIGH_BYTES" "$FLEET_MAX_BYTES"); then
    outcome="refused"; reason="cap_out_of_range"; _log
    emit_message "Soleur memory backstop: REFUSED to apply — a cap value is outside its validated range (${bad}).

Accepted ranges (bytes):
  SCOPE_MAX_BYTES   3 GiB .. 8 GiB   (floor above the 2.45 GB tsc peak; ceiling below the 9.5 GB harm point)
  SCOPE_HIGH_BYTES  5 GiB .. < SCOPE_MAX_BYTES
  FLEET_MAX_BYTES  10 GiB .. 24 GiB
  FLEET_HIGH_BYTES 14 GiB .. < FLEET_MAX_BYTES

Nothing was applied — this session is UNPROTECTED. To restore the shipped values:
  git checkout -- .claude/hooks/memory-backstop.sh"
    exit 0
  fi

  # (4) Identity. Adopt nothing without a positive match.
  local found
  if ! found=$(discover_claude_pid "$$" /proc); then
    reason="claude_pid_not_found"; _log; _maybe_never_worked "$stamp_file" "$log_file"; exit 0
  fi
  claude_pid=${found%% *}
  identity_signal=${found##* }

  if ! terminal_scope=$(terminal_scope_for "$claude_pid"); then
    reason="no_terminal_scope"; _log; exit 0
  fi

  # (5) Serialize discover→apply→log. SessionStart fires up to four ways per
  # PID; `startup` then a fast `/clear`, or overlapping `resume`+`compact`, has
  # both invocations reach SetUnitProperties and re-sweep different trees.
  exec 9>>"$lock_file" 2>/dev/null
  if ! flock -w 5 -x 9 2>/dev/null; then
    reason="concurrent_apply"; _log; exit 0
  fi

  local starttime; starttime=$(read_starttime "$claude_pid" /proc || echo "0")
  scope="soleur-agent-${claude_pid}.scope"

  # Read the slice's PRE-EXISTING values. 14 active worktrees on this box and
  # .claude/hooks/ is per-checkout, so the moment caps are tuned old- and
  # new-version sessions flap the SHARED slice. Logging only what we wrote would
  # make that flap invisible.
  slice_high_before=$(systemctl --user show "$SLICE_NAME" -p MemoryHigh --value 2>/dev/null)
  slice_max_before=$(systemctl --user show "$SLICE_NAME" -p MemoryMax --value 2>/dev/null)

  # (6) Slice first: the fleet bound and the oomd preference are live before
  # anything can be charged. runtime=true writes only under /run/user/<uid>/ —
  # `systemctl --user set-property` without it permanently mutates
  # ~/.config/systemd/user.control/, which this hook has no business doing.
  #
  # ManagedOOMPreference=avoid: systemd-oomd is a USERSPACE killer that SIGKILLs
  # every PID in the cgroup it selects and ignores OOMPolicy entirely. Its
  # candidate set is the monitored cgroup's direct children, so once soleur.slice
  # exists the whole fleet becomes one target. Honest caveat: oomctl currently
  # monitors zero cgroups, so this property is armed but its runtime efficacy is
  # UNVALIDATED — the readback proves a string was transmitted, not that
  # behaviour changed.
  "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
    "$SLICE_NAME" true 4 \
    "MemoryHigh" "t" "$FLEET_HIGH_BYTES" \
    "MemoryMax" "t" "$FLEET_MAX_BYTES" \
    "MemorySwapMax" "t" 0 \
    "ManagedOOMPreference" "s" "avoid" \
    >/dev/null 2>&1

  # ...and on the PARENT slice too. systemd-oomd chooses among the MONITORED
  # cgroup's DIRECT CHILDREN, and the monitored cgroup is user@<uid>.service —
  # whose direct child is `soleur.slice`, not `soleur-agents.slice`. Setting
  # `avoid` only on the latter arms it on a unit oomd never consults, which is a
  # targeting error rather than the separately-disclosed "efficacy unvalidated"
  # caveat. (systemd creates `soleur.slice` implicitly via the dash convention.)
  "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
    "soleur.slice" true 1 \
    "ManagedOOMPreference" "s" "avoid" \
    >/dev/null 2>&1

  # (7) Adopt the tree.
  local -a tree=()
  mapfile -t tree < <(collect_descendants "$claude_pid" /proc)
  if [[ "${tree[-1]:-}" == "TRUNCATED" ]]; then
    tree_truncated="true"
    unset 'tree[-1]'
  fi
  (( ${#tree[@]} == 0 )) && tree=("$claude_pid")
  tree_size=${#tree[@]}

  # ADOPT claude's OWN PID ONLY in StartTransientUnit, then attach the rest.
  # Measured: systemd fails the ENTIRE call with "Failed to set unit properties:
  # No such process" if ANY pid in the array has exited between collection and
  # the call — and an agent session spawns and reaps short-lived children
  # continuously, so a whole-tree array loses that race on most runs. Passing the
  # one stable PID makes scope creation deterministic; descendants are attached
  # separately below, where a dead PID costs only itself. Anything spawned after
  # this point inherits the cgroup automatically.
  local -a pid_args=("PIDs" "au" 1 "$claude_pid")

  # OOMPolicy=continue is passed EXPLICITLY: transient scopes default to `stop`,
  # which makes systemd kill the whole scope — including claude — on any OOM,
  # losing the session this exists to protect. With `continue` the kernel kills
  # the single largest task, which at MemoryMax is the runaway by construction.
  #
  # Delegate=true is REQUIRED, not cosmetic: without it AttachProcessesToUnit
  # fails with "Process migration not available on non-delegated units", and the
  # re-entry re-sweep below is unimplementable — the only other route is writing
  # cgroup.procs directly, which is #7151's single-writer violation.
  "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
    org.freedesktop.systemd1.Manager StartTransientUnit "ssa(sv)a(sa(sv))" \
    "$scope" "fail" 10 \
    "${pid_args[@]}" \
    "Slice" "s" "$SLICE_NAME" \
    "MemoryHigh" "t" "$SCOPE_HIGH_BYTES" \
    "MemoryMax" "t" "$SCOPE_MAX_BYTES" \
    "MemorySwapMax" "t" 0 \
    "OOMPolicy" "s" "continue" \
    "Delegate" "b" true \
    "BindsTo" "as" 1 "$terminal_scope" \
    "After" "as" 1 "$terminal_scope" \
    "Description" "s" "Soleur agent session $claude_pid" \
    0 \
    >/dev/null 2>&1
  local start_rc=$?
  # ^ That trailing `0` is the empty `aux` array of the signature
  # `ssa(sv)a(sa(sv))`. Omitting it makes busctl fail with "Too few parameters
  # for signature" — and because this hook redirects busctl's stdout AND stderr
  # (the job object path would otherwise land in session context), the failure is
  # invisible: the run falls through to the re-entry branch, invents a
  # PID-reuse-disambiguated scope name, and every subsequent readback is empty.
  # Caught only by the membership verification below.

  if (( start_rc != 0 )); then
    # Unit already exists (the normal re-entry case) — OR a stale scope left
    # `active (abandoned)` by a straggler whose PID has since been REUSED. Do not
    # treat rc=1 as "already adopted": refreshing a scope this process is not a
    # member of reports success while nothing is capped, which is #7151's failure
    # shape by a different route.
    local our_cg; our_cg=$(cut -d: -f3 < "/proc/$claude_pid/cgroup" 2>/dev/null | head -1)
    if [[ "${our_cg##*/}" != "$scope" ]]; then
      scope="soleur-agent-${claude_pid}-${starttime}.scope"
      reason="pid_reuse_disambiguated"
      "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
        org.freedesktop.systemd1.Manager StartTransientUnit "ssa(sv)a(sa(sv))" \
        "$scope" "fail" 10 \
        "${pid_args[@]}" \
        "Slice" "s" "$SLICE_NAME" \
        "MemoryHigh" "t" "$SCOPE_HIGH_BYTES" \
        "MemoryMax" "t" "$SCOPE_MAX_BYTES" \
        "MemorySwapMax" "t" 0 \
        "OOMPolicy" "s" "continue" \
        "Delegate" "b" true \
        "BindsTo" "as" 1 "$terminal_scope" \
        "After" "as" 1 "$terminal_scope" \
        "Description" "s" "Soleur agent session $claude_pid" \
        0 \
        >/dev/null 2>&1
    else
      # Ours. Read attribution BEFORE refreshing, then refresh caps in place —
      # this is how a changed cap lands without a session restart.
      local scg="/sys/fs/cgroup${our_cg}"
      local last_oom last_high
      last_oom=$(_last_logged "$log_file" last_oom_kill "$scope")
      last_high=$(_last_logged "$log_file" last_high "$scope")
      msg=$(attribution_message "$scg/memory.events" "$scg/memory.peak" "$last_oom" "$last_high")

      # NEVER re-derive the terminal scope here: our own cgroup basename is now
      # our scope, so re-deriving would bind the scope to ITSELF and silently
      # destroy the kill switch. Preserve the existing BindsTo instead.
      local existing_bt; existing_bt=$(systemctl --user show "$scope" -p BindsTo --value 2>/dev/null)
      terminal_scope="${existing_bt:-$terminal_scope}"

      "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
        org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
        "$scope" true 4 \
        "MemoryHigh" "t" "$SCOPE_HIGH_BYTES" \
        "MemoryMax" "t" "$SCOPE_MAX_BYTES" \
        "MemorySwapMax" "t" 0 \
        "OOMPolicy" "s" "continue" \
        >/dev/null 2>&1

    fi
  fi

  # Sweep the descendants into the scope. Runs on EVERY path, not just re-entry:
  # on a fresh adoption the MCP servers are already running (SessionStart races
  # MCP startup, and they are direct children of claude), and on re-entry this is
  # what closes that race for anything spawned since. Attaching is per-process
  # and best-effort — one PID that exited between collection and now costs only
  # itself, which is exactly why the tree is not passed to StartTransientUnit.
  for p in "${tree[@]}"; do
    [[ "$p" == "$claude_pid" ]] && continue
    [[ -r "/proc/$p/cgroup" ]] || continue
    local pcg; pcg=$(cut -d: -f3 < "/proc/$p/cgroup" 2>/dev/null | head -1)
    [[ "${pcg##*/}" == "$scope" ]] && { attached=$((attached + 1)); continue; }
    if "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
      org.freedesktop.systemd1.Manager AttachProcessesToUnit "ssau" \
      "$scope" "/" 1 "$p" >/dev/null 2>&1; then
      attached=$((attached + 1))
    fi
  done

  # VERIFY, do not assume. Reporting `applied` because a D-Bus call was issued is
  # precisely the #7151 defect — a green signal over an inert guard.
  #
  # Membership alone is NOT enough, and on the re-entry path it is worse than not
  # enough: that branch is only reached when the PID is already in `$scope`, so
  # asserting membership there re-asserts the branch's own entry condition and
  # can never fail. Every `/clear` and every resume takes that path. So read back
  # the properties that actually constitute the cap, at BOTH levels, and record
  # what was OBSERVED rather than what was intended.
  #
  # Reading back is required rather than checking rc: SetUnitProperties returns
  # rc=0 for a unit that does not exist yet (it loads it inactive), so a zero
  # exit proves the call was accepted, not that the running unit carries the cap.
  # And the call is all-or-nothing — one unsupported property (ManagedOOMPreference
  # needs systemd >= 247) drops MemoryHigh, MemoryMax AND MemorySwapMax with it,
  # which would silently restore the swap-exhaustion half of the incident.
  local final_cg
  final_cg=$(cut -d: -f3 < "/proc/$claude_pid/cgroup" 2>/dev/null | head -1)
  scope_max_after=$(systemctl --user show "$scope" -p MemoryMax --value 2>/dev/null)
  scope_high_after=$(systemctl --user show "$scope" -p MemoryHigh --value 2>/dev/null)
  scope_swap_after=$(systemctl --user show "$scope" -p MemorySwapMax --value 2>/dev/null)
  slice_high_after=$(systemctl --user show "$SLICE_NAME" -p MemoryHigh --value 2>/dev/null)
  slice_max_after=$(systemctl --user show "$SLICE_NAME" -p MemoryMax --value 2>/dev/null)
  slice_swap_after=$(systemctl --user show "$SLICE_NAME" -p MemorySwapMax --value 2>/dev/null)

  if [[ "${final_cg##*/}" != "$scope" ]]; then
    outcome="failed"
    reason="adoption_unverified"
    msg="Soleur memory backstop could NOT cap this session — it is running UNPROTECTED.

The scope was requested but this process is not a member of it:
  expected: $scope
  actual:   $(_sanitize "${final_cg##*/}")

Nothing else is affected and your session is fine, but a runaway command here is
not bounded. Details: .claude/.memory-backstop.jsonl"
  elif [[ "$scope_max_after" != "$SCOPE_MAX_BYTES" || "$scope_high_after" != "$SCOPE_HIGH_BYTES" \
       || "$scope_swap_after" != "0" ]]; then
    outcome="failed"
    reason="scope_caps_unverified"
    msg="Soleur memory backstop: this session's scope exists but its memory limits were NOT applied.

  MemoryMax     expected $(_human_bytes "$SCOPE_MAX_BYTES"), got ${scope_max_after:-<unset>}
  MemoryHigh    expected $(_human_bytes "$SCOPE_HIGH_BYTES"), got ${scope_high_after:-<unset>}
  MemorySwapMax expected 0, got ${scope_swap_after:-<unset>}

A runaway command here is NOT bounded. Details: .claude/.memory-backstop.jsonl"
  elif [[ "$slice_max_after" != "$FLEET_MAX_BYTES" || "$slice_high_after" != "$FLEET_HIGH_BYTES" \
       || "$slice_swap_after" != "0" ]]; then
    # This session is capped, but the SHARED bound is not there — so N sessions
    # can still exhaust the box between them, and swap is uncapped at the slice.
    outcome="failed"
    reason="fleet_caps_unverified"
    msg="Soleur memory backstop: this session is capped, but the FLEET-WIDE limit was not applied.

  $SLICE_NAME MemoryMax     expected $(_human_bytes "$FLEET_MAX_BYTES"), got ${slice_max_after:-<unset>}
  $SLICE_NAME MemoryHigh    expected $(_human_bytes "$FLEET_HIGH_BYTES"), got ${slice_high_after:-<unset>}
  $SLICE_NAME MemorySwapMax expected 0, got ${slice_swap_after:-<unset>}

Each session is still individually bounded, but several sessions together are not.
On systemd older than 247 this is expected: ManagedOOMPreference is unsupported and
fails the whole property call. Details: .claude/.memory-backstop.jsonl"
  else
    outcome="applied"
    # Distinguish a fresh adoption (caps proven by StartTransientUnit succeeding)
    # from a refresh (caps proven only by the readback above) — otherwise the log
    # cannot tell the two apart after the fact.
    [[ -z "$reason" ]] && reason=$( (( start_rc == 0 )) && echo "ok_fresh" || echo "ok_refreshed" )
  fi

  # Record the counters this run observed so the next run compares against them.
  local scg2 cur_oom=0 cur_high=0
  scg2="/sys/fs/cgroup$(cut -d: -f3 < "/proc/$claude_pid/cgroup" 2>/dev/null | head -1)"
  if [[ -r "$scg2/memory.events" ]]; then
    cur_oom=$(awk '/^oom_kill /{print $2}' "$scg2/memory.events" 2>/dev/null || echo 0)
    cur_high=$(awk '/^high /{print $2}' "$scg2/memory.events" 2>/dev/null || echo 0)
  fi
  [[ "$cur_oom" =~ ^[0-9]+$ ]] || cur_oom=0
  [[ "$cur_high" =~ ^[0-9]+$ ]] || cur_high=0

  _log_with_counters "$log_file" "$cur_oom" "$cur_high"

  # (8) Edge-triggered messages only — never per-session.
  if [[ -n "$msg" ]]; then
    emit_message "$msg"
  elif [[ ! -f "$stamp_file" ]]; then
    printf '%s\n' "$(hostname 2>/dev/null || echo host):${SCOPE_MAX_BYTES}:${FLEET_MAX_BYTES}" > "$stamp_file" 2>/dev/null
    emit_message "Soleur memory backstop is active on this machine.

Each agent session now runs in its own memory-capped systemd scope, and all of
them share a fleet-wide limit — so one runaway command can no longer exhaust
memory and swap and take down every open session.

If a session is stopped unexpectedly you will get a message explaining what hit
which limit. To stop just one session:      systemctl --user stop soleur-agent-<pid>.scope
To raise one session's limit:               systemctl --user set-property --runtime soleur-agent-<pid>.scope MemoryHigh=infinity MemoryMax=infinity
To stop EVERY agent session on this box:    systemctl --user stop soleur.slice   (this kills them all)
To turn the backstop off entirely:          set SOLEUR_DISABLE_MEMORY_BACKSTOP=1"
  fi

  exit 0
}

# Last recorded value of a counter field, for the increase comparison.
# Counters are per-SCOPE, but the log is per-worktree and several sessions share
# it. Without the scope filter, session B (a fresh scope, counters at 0) writes
# last_oom_kill=0, and session A — which has already seen 3 kills and already
# messaged — then reads 0, decides 3 > 0, and re-emits its post-mortem. The ADR's
# own scenario is six concurrent sessions, so that is the default condition, not
# an edge case.
_last_logged() {
  local log_file=$1 field=$2 want_scope=$3
  [[ -r "$log_file" ]] || { printf '0'; return 0; }
  local v
  v=$(tail -200 "$log_file" 2>/dev/null \
      | jq -r --arg f "$field" --arg s "$want_scope" \
          'select(.scope == $s and .[$f] != null) | .[$f]' 2>/dev/null | tail -1)
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# Append the applied line, carrying the counters forward for the next run's
# increase comparison.
_log_with_counters() {
  local log_file=$1 cur_oom=$2 cur_high=$3
  # Rotate here too. `_log` is only reached on the DECLINE paths, so on a machine
  # where the hook always applies nothing ever rotated and the sink grew forever.
  local _rot; _rot="$(dirname "${BASH_SOURCE[0]}")/lib/log-rotation.sh"
  if [[ -f "$_rot" ]]; then
    # shellcheck source=/dev/null
    source "$_rot" 2>/dev/null || true
    declare -F rotate_if_needed >/dev/null 2>&1 && rotate_if_needed "$log_file" 2>/dev/null
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg ts "$ts" --arg outcome "$outcome" --arg reason "$reason" \
      --arg scope "$scope" --arg tscope "$terminal_scope" --arg slice "$SLICE_NAME" \
      --arg sig "$identity_signal" --arg pid "$claude_pid" \
      --arg shb "$slice_high_before" --arg smb "$slice_max_before" \
      --argjson tree "$tree_size" --argjson oom "$cur_oom" --argjson hi "$cur_high" \
      --argjson sh "$SCOPE_HIGH_BYTES" --argjson sm "$SCOPE_MAX_BYTES" \
      --argjson fh "$FLEET_HIGH_BYTES" --argjson fm "$FLEET_MAX_BYTES" \
      --arg sha "$scope_high_after" --arg sma "$scope_max_after" --arg swa "$scope_swap_after" \
      --arg fha "$slice_high_after" --arg fma "$slice_max_after" --arg fwa "$slice_swap_after" \
      --argjson att "$attached" --argjson trunc "$tree_truncated" \
      '{schema:1, ts:$ts, pid:(($pid|tonumber?) // null), tree_size:$tree, scope:$scope,
        terminal_scope:$tscope, slice:$slice,
        scope_high:$sh, scope_max:$sm, slice_high:$fh, slice_max:$fm,
        scope_high_after:$sha, scope_max_after:$sma, scope_swap_after:$swa,
        slice_high_after:$fha, slice_max_after:$fma, slice_swap_after:$fwa,
        slice_high_before:$shb, slice_max_before:$smb,
        attached:$att, tree_truncated:$trunc,
        swap_max:0, identity_signal:$sig, outcome:$outcome, reason:$reason,
        last_oom_kill:$oom, last_high:$hi}' 2>/dev/null >> "$log_file"
  fi
}

# R11 — the never-worked edge trigger. The regression channel is "previously
# succeeded and now fails", so on a machine where it NEVER succeeded there is no
# "previously" and it never fires: a non-standard install (npm-global gives
# exe=/usr/bin/node) would log `skipped` forever while the operator believes they
# are protected. That is #7151's own class, so it needs its own detector.
_maybe_never_worked() {
  local stamp_file=$1 log_file=$2
  [[ -f "$stamp_file" ]] && return 0
  [[ -f "${stamp_file}.nagged" ]] && return 0
  printf 'nagged\n' > "${stamp_file}.nagged" 2>/dev/null
  emit_message "Soleur memory backstop could not identify this agent session, so NO memory cap is in effect here.

This machine has a working systemd user bus, so the backstop should have applied.
The likely cause is a non-standard Claude Code install (the process identity check
looks for a claude executable in the ancestry).

Nothing is broken and your session is unaffected — but you are not protected from
a runaway command exhausting memory. Details: .claude/.memory-backstop.jsonl"
}

# `if`, not `[[ ... ]] && main`: as the file's LAST command the `&&` form returns
# 1 when the condition is false, so `source` itself would report failure to the
# test harness even though sourcing succeeded.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
