#!/usr/bin/env bash
# SessionStart hook — bounds an agent session's memory via a systemd transient
# scope (ADR-155, #7166).
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

# Minimal JSON string escaper, used only when jq is absent (R8). The sibling
# supabase-loopback-warn.sh exits 1 when jq is missing precisely because stderr
# is a dead sink on an exit-0 hook; emitting valid JSON by hand lets this hook
# keep its unconditional exit-0 contract without writing to that dead sink.
_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# Operator-visible channel for an exit-0 hook.
emit_message() {
  local msg=$1
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{systemMessage:$m}' 2>/dev/null && return 0
  fi
  printf '{"systemMessage":"%s"}\n' "$(_json_escape "$msg")"
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

  local n=0
  for pid in "${!keep[@]}"; do
    (( n >= MAX_TREE )) && break
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

What this means: a command running here hit the ${SCOPE_MAX_BYTES:-0}-byte per-session limit${peak_h:+ (peak ${peak_h})} and the kernel stopped the largest process in the session. Uncommitted work in that command may be lost. This is not a crash in your code.

Note: the fleet-wide limit is shared, so a kill can occasionally land in a session other than the one that grew.

To raise this session's limit now:
  systemctl --user set-property --runtime soleur-agent-\$\$.scope MemoryHigh=infinity MemoryMax=infinity
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
        '{schema:1, ts:$ts, pid:($pid|tonumber?), tree_size:$tree, scope:$scope,
          terminal_scope:$tscope, slice:$slice, scope_high:$sh, scope_max:$sm,
          slice_high:$fh, slice_max:$fm, slice_high_before:$shb, slice_max_before:$smb,
          swap_max:0, identity_signal:$sig, outcome:$outcome, reason:$reason}' 2>/dev/null)
    fi
    # No jq: hand-rolled but still valid JSON, so the sink never goes dark.
    [[ -z "$line" ]] && line="{\"schema\":1,\"ts\":\"$(_json_escape "$ts")\",\"outcome\":\"$(_json_escape "$outcome")\",\"reason\":\"$(_json_escape "$reason")\",\"scope\":\"$(_json_escape "$scope")\",\"tree_size\":$tree_size}"
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

  # (7) Adopt the tree.
  local -a tree=()
  mapfile -t tree < <(collect_descendants "$claude_pid" /proc)
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
    >/dev/null 2>&1
  local start_rc=$?

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
        >/dev/null 2>&1
    else
      # Ours. Read attribution BEFORE refreshing, then refresh caps in place —
      # this is how a changed cap lands without a session restart.
      local scg="/sys/fs/cgroup${our_cg}"
      local last_oom last_high
      last_oom=$(_last_logged "$log_file" last_oom_kill)
      last_high=$(_last_logged "$log_file" last_high)
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
  local attached=0
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
  # precisely the #7151 defect — a green signal over an inert guard. The only
  # thing that proves adoption is cgroup membership, so read it back.
  local final_cg
  final_cg=$(cut -d: -f3 < "/proc/$claude_pid/cgroup" 2>/dev/null | head -1)
  if [[ "${final_cg##*/}" == "$scope" ]]; then
    outcome="applied"
    [[ -z "$reason" ]] && reason="ok"
  else
    outcome="failed"
    reason="adoption_unverified"
    msg="Soleur memory backstop could NOT cap this session — it is running UNPROTECTED.

The scope was requested but this process is not a member of it:
  expected: $scope
  actual:   ${final_cg##*/}

Nothing else is affected and your session is fine, but a runaway command here is
not bounded. Details: .claude/.memory-backstop.jsonl"
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
_last_logged() {
  local log_file=$1 field=$2
  [[ -r "$log_file" ]] || { printf '0'; return 0; }
  local v
  if command -v jq >/dev/null 2>&1; then
    v=$(tail -50 "$log_file" 2>/dev/null | jq -r --arg f "$field" 'select(.[$f] != null) | .[$f]' 2>/dev/null | tail -1)
  fi
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  printf '%s' "$v"
}

# Append the applied line, carrying the counters forward for the next run's
# increase comparison.
_log_with_counters() {
  local log_file=$1 cur_oom=$2 cur_high=$3
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg ts "$ts" --arg outcome "$outcome" --arg reason "$reason" \
      --arg scope "$scope" --arg tscope "$terminal_scope" --arg slice "$SLICE_NAME" \
      --arg sig "$identity_signal" --arg pid "$claude_pid" \
      --arg shb "$slice_high_before" --arg smb "$slice_max_before" \
      --argjson tree "$tree_size" --argjson oom "$cur_oom" --argjson hi "$cur_high" \
      --argjson sh "$SCOPE_HIGH_BYTES" --argjson sm "$SCOPE_MAX_BYTES" \
      --argjson fh "$FLEET_HIGH_BYTES" --argjson fm "$FLEET_MAX_BYTES" \
      '{schema:1, ts:$ts, pid:($pid|tonumber?), tree_size:$tree, scope:$scope,
        terminal_scope:$tscope, slice:$slice, scope_high:$sh, scope_max:$sm,
        slice_high:$fh, slice_max:$fm, slice_high_before:$shb, slice_max_before:$smb,
        swap_max:0, identity_signal:$sig, outcome:$outcome, reason:$reason,
        last_oom_kill:$oom, last_high:$hi}' 2>/dev/null >> "$log_file"
  else
    printf '{"schema":1,"ts":"%s","outcome":"%s","reason":"%s","scope":"%s","tree_size":%s,"last_oom_kill":%s,"last_high":%s}\n' \
      "$(_json_escape "$ts")" "$(_json_escape "$outcome")" "$(_json_escape "$reason")" \
      "$(_json_escape "$scope")" "$tree_size" "$cur_oom" "$cur_high" >> "$log_file"
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
