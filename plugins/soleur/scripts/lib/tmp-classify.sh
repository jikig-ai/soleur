#!/usr/bin/env bash
# tmp-classify.sh — the single "safe to move" classifier for Soleur scratch dirs.
#
# WHY
# ---
# /tmp and /var/tmp accumulate tens of thousands of orphaned session dirs from
# Soleur runs (27 GB / ~67k entries measured 2026-09-24). Deleting the wrong
# entry destroys live session work or authored files, so EVERY consumer —
# soleur-tmp-purge.sh, tmpfs-guard Reaper 3, and the worktree-manager
# session-start sweep — sources THIS module rather than re-implementing
# "safe to move". Three divergent copies of a destructive predicate is the
# defect class this file exists to prevent.
#
# USAGE
# -----
#   source "<repo>/plugins/soleur/scripts/lib/tmp-classify.sh"   # repo-side
#   source "$SCRIPT_DIR/../../../scripts/lib/tmp-classify.sh"    # shipped plugin
#
#   class=$(tc_classify_entry "$dir")       # attribution ladder, below
#   tc_entry_is_live "$dir" <pid>           # conjunctive liveness
#   tc_quarantine_move "$dir" "$base" <class-subdir>
#
# ATTRIBUTION LADDER (first match wins)
#   worktree         .git FILE present → owning repo's registry classification —
#                    verified attribution, evaluated BEFORE protected/prefix so
#                    a signature collision can never steal a registered tree
#   protected        never a candidate (systemd-private-*, skill-security-scan-*,
#                    bare tmp.*, quarantine artifacts, claude-<uid>, ...)
#   marker           <dir>/.soleur-owned valid marker → declared-owned; a marker
#                    that exists but fails verification (foreign/absent
#                    namespace, owner_root cycle) VETOES the schema rung below —
#                    it classifies unattributable, never schema
#   schema           soleur-run.<pid>.XXXXXXXX → declared-owned
#   prefix:<name>    allowlisted prefix + required subpath signature present —
#                    evaluated BEFORE standalone-clone so `.git/config`-signature
#                    fixture classes (pirgate-*, deploygap-gate-*) stay reachable
#   standalone-clone .git DIRECTORY present → report-only, never a candidate
#   empty            empty dir + long random-looking name → rmdir candidate
#   file:<name>      allowlisted regular-file name-shape
#   unattributable   report only — never moved
#
# LIVENESS (conjunctive — every check must pass for "dead")
#   owner pid absent from procfs AND no process fd/cwd beneath the dir AND no
#   process environ contains the dir path AND the marker/schema's recorded
#   pid-namespace matches the caller's. PPID is never consulted: a dead
#   owner's children reparent to init. environ is exec-time, so it can only
#   ever show the path for processes exec'd AFTER the export — it is a
#   descendant scan, not owner evidence. pid-present-but-foreign (reuse) is
#   retentive: spare on ambiguity.
#
# SEAMS (env overrides, for tests and future multi-base callers)
#   TMP_CLASSIFY_PROC             procfs root            (default /proc)
#   TMP_CLASSIFY_AGE_FLOOR_MIN    min tree age, minutes  (default 1440)
#   TMP_CLASSIFY_WT_FLOOR_MIN     worktree age floor     (default 4320)
#   TMP_CLASSIFY_RETAIN_FLOOR_MIN retain-since hard floor (default 10080)
#   TMP_CLASSIFY_RETAIN_DIR       retain-since stamp dir
#   TMP_CLASSIFY_UID              uid scope              (default $(id -u))
#   TMP_CLASSIFY_LEDGER           disposition ledger     (~/.local/state/soleur/tmp-purge-ledger.log;
#                                                        SOLEUR_PURGE_LEDGER also honored)
#   TMP_CLASSIFY_INUSE_TOKEN_CAP  environ-token cap      (default 50000; on
#                                                        truncation map-misses fall back to a
#                                                        per-candidate walk — never a false dead)
#   TMP_CLASSIFY_INUSE_TTL_S      map staleness bound    (default 120; consumers
#                                                        call tc_inuse_map_refresh before actions)
#
# PORTABILITY: GNU find -printf and /proc are Linux-isms; on hosts without them
# the affected rungs fail CLOSED (entry reads as fresh/live → retained).

[[ -n "${_SOLEUR_TMP_CLASSIFY_SOURCED:-}" ]] && return 0
_SOLEUR_TMP_CLASSIFY_SOURCED=1

TC_PROC="${TMP_CLASSIFY_PROC:-/proc}"
TC_AGE_FLOOR_MIN="${TMP_CLASSIFY_AGE_FLOOR_MIN:-1440}"
TC_WT_FLOOR_MIN="${TMP_CLASSIFY_WT_FLOOR_MIN:-4320}"
TC_RETAIN_FLOOR_MIN="${TMP_CLASSIFY_RETAIN_FLOOR_MIN:-10080}"
TC_RETAIN_DIR="${TMP_CLASSIFY_RETAIN_DIR:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/tmp-retain}"
TC_UID="${TMP_CLASSIFY_UID:-$(id -u)}"
TC_LEDGER="${SOLEUR_PURGE_LEDGER:-${TMP_CLASSIFY_LEDGER:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/tmp-purge-ledger.log}}"
TC_INUSE_TTL_S="${TMP_CLASSIFY_INUSE_TTL_S:-120}"

# tc_uid_of <path> — portable owner uid (GNU stat -c, BSD stat -f).
tc_uid_of() { stat -c %u -- "$1" 2>/dev/null || stat -f %u -- "$1" 2>/dev/null; }

# Ambient git state must never leak into the safety conjuncts: a poisoned
# GIT_DIR/GIT_CONFIG_COUNT in the caller's environment would make a candidate's
# clean/merged/upstream verdicts answer for a DIFFERENT repo, and a candidate-
# controlled gitdir could run core.fsmonitor hooks. Every conjunct-side git
# call goes through this.
_tc_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_CONFIG_COUNT \
      -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM \
      git -c core.fsmonitor=false "$@"
}

# --- Protected names ---------------------------------------------------------
# Evaluated BEFORE every ladder rung: a future allowlist row must never outrank
# a protection. Quarantine artifacts are excluded from enumeration entirely
# here as a second layer beneath the caller's own exclusion.

# Takes a path OR a basename; ${1##*/} avoids a spawn per candidate — sweep
# callers enumerate tens of thousands of entries on a shared base.
tc_is_protected() {
  local name="${1##*/}"
  case "$name" in
    soleur-quarantine|soleur-quarantine.*|*.quarantine-meta) return 0 ;;
    tmp|tmp.*) return 0 ;;              # bare mktemp — unattributable, tmpfiles' job
    plan-*|shared-*|vbcr*) return 0 ;;
    skill-security-scan-*) return 0 ;;  # #6760 deliberate retention
    systemd-private-*) return 0 ;;
    playwright*|node-compile-cache|claude-*) return 0 ;;
    .|..) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Marker / schema parsing ---------------------------------------------------

# tc_marker_owner_pid <dir> [depth] → prints owner pid AND sets TC_PID.
# rc 0 = verified owner; rc 1 = no marker (caller may try the schema rung);
# rc 2 = marker PRESENT but unverifiable (wrong uid, foreign/absent/unknown
# pid-namespace, owner_root cycle) — a VETO: callers must not fall back to
# the schema rung, because a rejected declaration means the dir's provenance
# is in doubt and every recorded identity is untrustworthy.
# Marker contract: regular file, not a symlink, owned by TC_UID, carrying
# `pid=<top-level-harness-pid>` OR `owner_root=<soleur-run.* dir>`, plus
# `schema=` and `ns=pid:[<inode>]`. `ns=` must parse AND equal our namespace:
# `pid:[unknown]` (a writer whose readlink failed) and absent-ns markers are
# both unverifiable — never silently trusted.
tc_marker_owner_pid() {
  local dir="$1" depth="${2:-0}" m="$1/.soleur-owned" pid="" oroot="" ns="" myns
  (( depth <= 4 )) || return 2   # owner_root cycle bound — unverifiable
  [[ -f "$m" && ! -L "$m" ]] || return 1
  [[ "$(tc_uid_of "$m")" == "$TC_UID" ]] || return 2
  ns="$(sed -n 's/^ns=\(pid:\[[0-9]*\]\)$/\1/p' "$m" 2>/dev/null | head -1)"
  myns="$(tc_my_pid_ns)"
  if [[ -z "$ns" || "$ns" != "$myns" || "$myns" == "pid:[unknown]" ]]; then
    return 2   # namespace absent, unparseable, foreign, or unverifiable
  fi
  pid="$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$m" 2>/dev/null | head -1)"
  if [[ -z "$pid" ]]; then
    oroot="$(sed -n 's/^owner_root=\([^[:space:]]*\)$/\1/p' "$m" 2>/dev/null | head -1)"
    [[ -n "$oroot" ]] || return 2
    if tc_schema_owner_pid "${oroot##*/}" >/dev/null 2>&1; then pid="$TC_PID"; fi
    if [[ -z "$pid" ]] && tc_marker_owner_pid "$oroot" "$((depth + 1))" >/dev/null 2>&1; then pid="$TC_PID"; fi
    [[ -n "$pid" ]] || return 2
  fi
  TC_PID="$pid"
  printf '%s' "$pid"
}

# tc_schema_owner_pid <basename> → prints pid AND sets TC_PID from
# soleur-run.<pid>.XXXXXXXX.
tc_schema_owner_pid() {
  local n="$1"
  [[ "$n" =~ ^soleur-run\.([0-9]+)\.[A-Za-z0-9_-]{8,}$ ]] || return 1
  TC_PID="${BASH_REMATCH[1]}"
  printf '%s' "$TC_PID"
}

# tc_my_pid_ns → `pid:[<inode>]` of the caller's own pid namespace.
tc_my_pid_ns() {
  readlink "$TC_PROC/self/ns/pid" 2>/dev/null || printf 'pid:[unknown]'
}

# --- Liveness ------------------------------------------------------------------

# tc_owner_alive <pid> — /proc presence AND same-uid. A live pid owned by a
# DIFFERENT uid cannot be our marker's owner — the declaring writer runs as
# TC_UID — so `pid=1`-style claims (deliberate anti-reap or namespace
# confusion) do not count as a live owner. Genuine same-uid pid reuse stays
# retentive through the fd/environ conjuncts below.
tc_owner_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -d "$TC_PROC/$pid" ]] || return 1
  [[ "$(tc_uid_of "$TC_PROC/$pid")" == "$TC_UID" ]]
}

# tc_owner_pid_verify <dir> — resolve the declared owner honoring precedence:
# marker FIRST (it carries the pid-namespace discriminator), schema name only
# when NO marker exists. rc: 0 = owner pid in TC_PID (TC_DECL_KIND set to
# marker|schema), 1 = no declaration, 2 = declaration present but
# unverifiable — consumers must RETAIN rc 2 and never fall through to schema.
tc_owner_pid_verify() {
  local dir="$1" rc
  TC_DECL_KIND=""
  if [[ -e "$dir/.soleur-owned" || -L "$dir/.soleur-owned" ]]; then
    # `if` context is load-bearing: a plain call's nonzero rc aborts under
    # set -e before it can be inspected.
    if tc_marker_owner_pid "$dir" >/dev/null 2>&1; then rc=0; else rc=$?; fi
    if (( rc == 0 )); then TC_DECL_KIND="marker"; return 0; fi
    (( rc == 2 )) && return 2
    # rc 1 with a marker path existing is impossible here — belt: veto.
    return 2
  fi
  if tc_schema_owner_pid "${dir##*/}" >/dev/null 2>&1; then
    TC_DECL_KIND="schema"; return 0
  fi
  return 1
}

# tc_build_inuse_map <base>... — ONE /proc pass marking every top-level entry
# under the given bases that any live process touches via cwd, an open fd, a
# memory mapping, a bound unix socket, or an environ token. Callers sweeping
# many candidates (the session-start sweep) build it once and get O(1)
# membership from tc_tree_has_live_handles instead of paying a full procfs
# walk per candidate. map_files and net/unix are included so the coverage is
# the UNION of every handle class the guard's reapers know (JVM
# open-mmap-close, Chrome SingletonSocket) — the maps must never diverge on
# what counts as "live".
declare -gA TC_INUSE_MAP=()
declare -ga _TC_MAP_BASES=()

# Internal marker — dynamic-scoped over the caller's `_tc_bases` array.
_tc_mark_inuse() {
  local t="$1" rest top bb
  for bb in "${_tc_bases[@]}"; do
    case "$t" in
      "$bb"/*)
        rest="${t#"$bb"/}"
        top="${rest%%/*}"
        [[ -n "$top" ]] && TC_INUSE_MAP["$bb/$top"]=1
        ;;
    esac
  done
}

tc_build_inuse_map() {
  TC_INUSE_MAP=()
  _TC_MAP_BASES=("$@")
  [[ -d "$TC_PROC" ]] || return 1   # sentinel stays unset → per-candidate fallback
  local -a _tc_bases=("$@")
  local target tok

  # cwd + fd + map_files targets in ONE find: `-printf '%l'` hands back link
  # targets with no per-entry readlink spawn — ~30k syscalls collapse to a
  # single walk. map_files is load-bearing: open()+mmap(MAP_SHARED)+close()
  # leaves no fd to find — the JVM hsperfdata class — and its path appears
  # only here. Pseudo links (`socket:[…]`, `anon_inode:…`) are not absolute
  # and never match a base.
  while IFS= read -r target; do
    [[ "$target" == /* ]] && _tc_mark_inuse "$target"
  done < <(find "$TC_PROC"/[0-9]*/fd "$TC_PROC"/[0-9]*/cwd \
              "$TC_PROC"/[0-9]*/map_files -type l -printf '%l\n' 2>/dev/null)

  # Bound unix-domain sockets — a socket fd readlinks to `socket:[inode]`,
  # never its filesystem path, so a dir held only by a listener is invisible
  # to the walk above. /proc/net/unix is the only place the path appears; one
  # file read, same 7-column strip the guard's map uses.
  if [[ -r "$TC_PROC/net/unix" ]]; then
    while IFS= read -r target; do
      [[ -n "$target" ]] && _tc_mark_inuse "$target"
    done < <(
      awk '{ line = $0
             if (sub(/^([^ ]+[ ]+){7}/, "", line) && substr(line, 1, 1) == "/") print line }' \
        "$TC_PROC/net/unix" 2>/dev/null || true
    )
  fi

  # environ values are NUL-separated VAR=val with colon-joined path lists; a
  # descendant of a dead owner can still carry TMPDIR=<root>. One concatenated
  # pass rather than a grep per pid (a per-pid spawn measured ~10s for a
  # single candidate on a busy host). The cap bounds pathological environ
  # volume — on truncation a marker is set and map MISSES fall back to the
  # per-candidate walk, so a capped map can never prove a false "dead".
  local cap="${TMP_CLASSIFY_INUSE_TOKEN_CAP:-50000}"
  while IFS= read -r tok; do
    if [[ "$tok" == "/__TC_TRUNC__" ]]; then TC_INUSE_MAP["__truncated__"]=1; continue; fi
    [[ -n "$tok" ]] && _tc_mark_inuse "$tok"
  done < <(cat "$TC_PROC"/[0-9]*/environ 2>/dev/null \
             | tr '\0:' '\n' \
             | grep -oE '/[^[:space:]"'"'"']+' 2>/dev/null \
             | awk -v cap="$cap" -v sent="/__TC_TRUNC__" \
                   'NR <= cap { print; next } { print sent; exit }')

  TC_INUSE_MAP["__built_ts__"]="${EPOCHSECONDS:-$(date +%s)}"
  TC_INUSE_MAP["__built__"]=1     # set LAST — presence proves the build ran
}

# tc_inuse_map_refresh [ttl_s] — rebuild TC_INUSE_MAP when older than the
# staleness bound. The map is a snapshot; a multi-minute apply must not treat
# scan-start evidence as action-time truth (a dir can acquire a live handle
# mid-run). Cheap when fresh: one assoc read.
tc_inuse_map_refresh() {
  local ttl="${1:-$TC_INUSE_TTL_S}" now
  [[ -n "${TC_INUSE_MAP[__built__]:-}" ]] || return 0
  now="${EPOCHSECONDS:-$(date +%s)}"
  if (( now - ${TC_INUSE_MAP[__built_ts__]:-0} > ttl )); then
    tc_build_inuse_map "${_TC_MAP_BASES[@]}" || true
  fi
}

# _tc_walk_handles <dir> — the per-candidate procfs walk: cwd, fd, map_files,
# environ substring, and bound unix-socket paths. Fails CLOSED (returns
# "live") when procfs is unreadable — a degraded host must never prove "dead".
_tc_walk_handles() {
  local dir="$1" p fd target
  [[ -d "$TC_PROC" ]] || return 0
  for p in "$TC_PROC"/[0-9]*; do
    [[ -d "$p" ]] || continue
    if target="$(readlink "$p/cwd" 2>/dev/null)" && [[ "$target" == "$dir" || "$target" == "$dir"/* ]]; then
      return 0
    fi
    for fd in "$p"/fd/* "$p"/map_files/*; do
      [[ -e "$fd" || -L "$fd" ]] || continue
      target="$(readlink "$fd" 2>/dev/null)" || continue
      if [[ "$target" == "$dir" || "$target" == "$dir"/* ]]; then return 0; fi
    done
    if grep -aqF -- "$dir" "$p/environ" 2>/dev/null; then return 0; fi
  done
  # Bound unix sockets: fd links never carry the path — /proc/net/unix does.
  if [[ -r "$TC_PROC/net/unix" ]] && grep -aqF -- "$dir" "$TC_PROC/net/unix" 2>/dev/null; then
    return 0
  fi
  return 1
}

# tc_tree_has_live_handles <dir> — map-fast-path over _tc_walk_handles.
# A truncated map can never prove a negative: on miss it walks instead.
tc_tree_has_live_handles() {
  local dir="$1"
  [[ -d "$TC_PROC" ]] || return 0
  if [[ -n "${TC_INUSE_MAP[__built__]:-}" ]]; then
    local a="$dir"
    while [[ "$a" == */* && "$a" != "/" ]]; do
      [[ -n "${TC_INUSE_MAP[$a]:-}" ]] && return 0
      a="${a%/*}"
    done
    [[ -z "${TC_INUSE_MAP[__truncated__]:-}" ]] && return 1
    # truncated — a map miss is not evidence of death; walk it.
  fi
  _tc_walk_handles "$dir"
}

# tc_tree_has_live_handles_now <dir> — the walk, ALWAYS, ignoring the map.
# For action-time re-verification right before a TERMINAL delete: the map can
# be seconds stale mid-scan and tmpfs deletion has no quarantine to appeal to.
tc_tree_has_live_handles_now() {
  _tc_walk_handles "$1"
}

# tc_entry_is_live <dir> <owner-pid|""> — the full conjunct. rc 0 = live (retain).
tc_entry_is_live() {
  local dir="$1" pid="${2:-}"
  if [[ -n "$pid" ]] && tc_owner_alive "$pid"; then return 0; fi
  if tc_tree_has_live_handles "$dir"; then return 0; fi
  return 1
}

# --- Freshness -------------------------------------------------------------------

# tc_tree_age_min <dir> — minutes since the NEWEST mtime anywhere in the tree.
# A top-level dir mtime does not advance on nested writes (the _FRESH_TOP
# defect class). Missing find -printf (BSD find) → prints 0 (fresh →
# retained): a top-level-stat fallback would miss nested writes and read a
# fresh tree as stale — the fail direction here is deletion, so the probe
# fails closed.
tc_tree_age_min() {
  local dir="$1" newest now
  newest="$(find "$dir" -printf '%T@\n' 2>/dev/null \
              | awk 'NR==1 || $1 > m { m = $1 } END { if (NR) print m }' \
              | cut -d. -f1)"
  # awk max-scan: same IO as sort|head but O(1) memory and no full-buffer sort.
  [[ "$newest" =~ ^[0-9]+$ ]] || { echo 0; return 0; }
  now="$(date +%s)"
  if (( newest <= 0 || newest > now )); then echo 0; else echo $(( (now - newest) / 60 )); fi
}

# --- Empty-dir rung ----------------------------------------------------------------

# tc_is_reapable_empty <dir> — empty AND a random-looking ≥15-char basename
# AND not a mountpoint (device-id compare against parent doubles as the
# BSD-portable mountpoint check).
tc_is_reapable_empty() {
  local dir="$1" name
  name="${dir##*/}"
  [[ "$name" =~ ^[A-Za-z0-9_.-]{15,}$ ]] || return 1
  [[ -d "$dir" ]] || return 1
  # Emptiness: a caller sweeping a whole base may precompute TC_NONEMPTY
  # (one `find -mindepth 2` pass marking every dir that has children) — the
  # per-candidate `ls` spawn is the same cost class as the basename spawn this
  # function just dropped. Falls back to the per-dir check when unset.
  if [[ -n "${TC_NONEMPTY_BUILT:-}" ]]; then
    [[ -n "${TC_NONEMPTY[$dir]:-}" ]] && return 1
  else
    [[ -z "$(ls -A -- "$dir" 2>/dev/null)" ]] || return 1
  fi
  local dev_self dev_parent
  dev_self="$(stat -c %d -- "$dir" 2>/dev/null || stat -f %d -- "$dir" 2>/dev/null || echo x)"
  dev_parent="$(stat -c %d -- "$dir/.." 2>/dev/null || stat -f %d -- "$dir/.." 2>/dev/null || echo y)"
  [[ "$dev_self" != "x" && "$dev_self" == "$dev_parent" ]]
}

# --- Git / worktree arm ---------------------------------------------------------

# tc_classify_git_dir <dir> → one of:
#   standalone-clone  (.git is a real directory — report-only, never candidate)
#   not-git           (no .git at all)
#   unverifiable      (gitfile/gitdir/porcelain could not be resolved — RETAIN)
#   unregistered      (owning repo's registry read OK, path absent — quarantine)
#   registered        (registry read OK, path present — further gates apply)
# Prints the verdict AND sets TC_GITCLASS — hot-path callers invoke it directly
# (`tc_classify_git_dir "$d" >/dev/null; v="$TC_GITCLASS"`) to skip the fork.
# _tc_realpath <path> — canonicalize; empty output = unavailable (callers must
# treat that as UNVERIFIABLE, never fall back to the raw path: a non-
# canonicalized compare against git's canonical porcelain output misreads a
# registered worktree as unregistered → quarantine-move → registry damage).
_tc_realpath() {
  command -v realpath >/dev/null 2>&1 || return 1
  realpath -m -- "$1" 2>/dev/null
}

tc_classify_git_dir() {
  local dir="$1" gf="$1/.git" gitdir main_gitdir
  _gc() { TC_GITCLASS="$1"; printf '%s\n' "$1"; }
  if [[ -d "$gf" && ! -L "$gf" ]]; then _gc "standalone-clone"; return 0; fi
  [[ -f "$gf" && ! -L "$gf" ]] || { _gc "not-git"; return 0; }
  gitdir="$(sed -n 's/^gitdir:[[:space:]]*//p' "$gf" 2>/dev/null | head -1)"
  [[ -n "$gitdir" ]] || { _gc "unverifiable"; return 0; }
  [[ "$gitdir" != /* ]] && gitdir="$dir/$gitdir"
  gitdir="$(_tc_realpath "$gitdir")"
  [[ -n "$gitdir" && -d "$gitdir" ]] || { _gc "unverifiable"; return 0; }
  # gitdir shape is <main>/.git/worktrees/<name> — main repo gitdir is two up.
  main_gitdir="${gitdir%/*}"; main_gitdir="${main_gitdir%/*}"
  [[ -d "$main_gitdir/objects" || -f "$main_gitdir/HEAD" ]] || { _gc "unverifiable"; return 0; }
  local real_dir listing
  real_dir="$(_tc_realpath "$dir")"
  [[ -n "$real_dir" ]] || { _gc "unverifiable"; return 0; }
  if ! listing="$(_tc_git --git-dir="$main_gitdir" worktree list --porcelain 2>/dev/null)"; then
    _gc "unverifiable"; return 0
  fi
  [[ -n "$listing" ]] || { _gc "unverifiable"; return 0; }
  local wt found=0
  while IFS= read -r wt; do
    [[ -n "$wt" ]] || continue
    if [[ "$(_tc_realpath "$wt")" == "$real_dir" ]]; then
      found=1; break
    fi
  done <<< "$(printf '%s\n' "$listing" | sed -n 's/^worktree //p')"
  if (( found == 1 )); then _gc "registered"; else _gc "unregistered"; fi
}

# tc_git_main_dir <dir> → prints the owning repo's gitdir (rc 1 if unverifiable).
tc_git_main_dir() {
  local dir="$1" gf="$1/.git" gitdir
  [[ -f "$gf" && ! -L "$gf" ]] || return 1
  gitdir="$(sed -n 's/^gitdir:[[:space:]]*//p' "$gf" 2>/dev/null | head -1)"
  [[ -n "$gitdir" ]] || return 1
  [[ "$gitdir" != /* ]] && gitdir="$dir/$gitdir"
  gitdir="$(_tc_realpath "$gitdir")"
  [[ -n "$gitdir" && -d "$gitdir" ]] || return 1
  dirname "$(dirname "$gitdir")"
}

# tc_worktree_clean <dir> — no modified AND no untracked AND no ignored files.
# `--ignored` is load-bearing: porcelain omits ignored paths, so a worktree
# holding only `.env.local` must NOT read clean.
tc_worktree_clean() {
  local dir="$1" out
  out="$(_tc_git -C "$dir" status --porcelain --ignored 2>/dev/null)" || return 1
  [[ -z "$out" ]]
}

# tc_default_ref <main_gitdir> — the owning repo's default ref AS LAST FETCHED:
# origin/HEAD → the main worktree's checked-out branch → main/master. No fetch.
tc_default_ref() {
  local main="$1" sym
  sym="$(_tc_git --git-dir="$main" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  [[ -n "$sym" ]] && { printf '%s' "$sym"; return 0; }
  sym="$(_tc_git --git-dir="$main" symbolic-ref --quiet --short HEAD 2>/dev/null)"
  [[ -n "$sym" ]] && { printf '%s' "$sym"; return 0; }
  for sym in main master; do
    _tc_git --git-dir="$main" rev-parse --verify --quiet "$sym" >/dev/null 2>&1 && { printf '%s' "$sym"; return 0; }
  done
  return 1
}

# tc_worktree_safe_to_remove <dir> — registered + clean + merged + no-unpushed
# + no live process inside. Caller applies the age floor separately.
tc_worktree_safe_to_remove() {
  local dir="$1" main head upstream
  main="$(tc_git_main_dir "$dir")" || return 1
  tc_worktree_clean "$dir" || return 1
  head="$(_tc_git -C "$dir" rev-parse HEAD 2>/dev/null)" || return 1
  local defref
  defref="$(tc_default_ref "$main")" || return 1
  _tc_git --git-dir="$main" merge-base --is-ancestor "$head" "$defref" 2>/dev/null || return 1
  upstream="$(_tc_git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    local ahead
    ahead="$(_tc_git -C "$dir" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 999)"
    [[ "$ahead" == "0" ]] || return 1
  fi
  # A worktree with no recorded upstream and a detached-or-merged HEAD is fine;
  # a named branch with no upstream is retained by the caller's risk floor.
  if tc_tree_has_live_handles "$dir"; then return 1; fi
  return 0
}

# --- Prefix allowlist (purge-only rung) ------------------------------------------
# Each row: prefix|required-subpath-glob|writer-citation. The subpath is the
# content signature that makes prefix matching attributable rather than the
# rejected name-only heuristic. FROZEN — new producers get markers, not rows.
# All globs are matched against paths RELATIVE to the candidate dir.

TC_DIR_ALLOWLIST=(
  "rung2-archive.*|git-data-bootstrap.sh|tests/scripts/lib/git-data-birth-readiness-gate.sh"
  "gdboot.*|rows|scripts/lib/git-data-boot-signal-poll.sh"
  "infra-suites.*|_*.test.sh.meta|apps/web-platform/infra/run-registered-suites.sh"
  "soleur-inc-*|.claude|.claude/hooks/lib/test-incident-sandbox.sh"
  "mutbat.*|plugins|fixture producers (mutbat)"
  "mutbat2.*|pristine|fixture producers (mutbat2)"
  "pirgate-*|.git/config|plugins/soleur/test/ship-incident-pir-gate.test.ts"
  "kbcov-*|engineering|plugins/soleur/test/kb-coverage.test.ts"
  "gdpr-gate-incidents-*|.claude/.rule-incidents.jsonl|plugins/soleur/test/gdpr-gate.test.ts"
  "deploygap-gate-*|.git/config|deploygap test fixtures"
  "harness-discovery-*|plugin.json|harness discovery fixtures"
  "cron-filing-fixture-*|justified.md|cron filing fixtures"
  "luks-escrow.*|state/escrow.state|luks fixtures"
)

# Regular-file classes — signature is the name shape itself (no content reads).
TC_FILE_ALLOWLIST=(
  "inngest-ci-*.sh|scripts/inngest fixtures"
  "inngest-arm-*|inngest arm fixtures"
  "pr-*-body.md|pr body scratch files"
)

# tc_prefix_class <dir> → prints `prefix:<prefix>` AND sets TC_PREFIX_CLASS
# when the basename matches an allowlist prefix AND the required subpath
# exists. rc 1 otherwise.
tc_prefix_class() {
  local dir="$1" name row prefix sig
  name="${dir##*/}"
  for row in "${TC_DIR_ALLOWLIST[@]}"; do
    prefix="${row%%|*}"; sig="${row#*|}"; sig="${sig%%|*}"
    # shellcheck disable=SC2254  # prefix is a deliberate glob from the frozen list
    case "$name" in $prefix)
      compgen -G "$dir/$sig" >/dev/null 2>&1 && { TC_PREFIX_CLASS="prefix:$prefix"; printf '%s\n' "$TC_PREFIX_CLASS"; return 0; }
      ;;
    esac
  done
  return 1
}

# tc_file_class <file> → prints `file:<shape>` AND sets TC_FILE_CLASS for
# allowlisted regular files.
tc_file_class() {
  local f="$1" name row prefix
  [[ -f "$f" && ! -L "$f" ]] || return 1
  [[ "$(tc_uid_of "$f")" == "$TC_UID" ]] || return 1
  name="${f##*/}"
  for row in "${TC_FILE_ALLOWLIST[@]}"; do
    prefix="${row%%|*}"
    # shellcheck disable=SC2254
    case "$name" in $prefix) TC_FILE_CLASS="file:$prefix"; printf 'file:%s\n' "$prefix"; return 0 ;; esac
  done
  return 1
}

# --- Top-level classification -----------------------------------------------------

# tc_classify_entry <path> → prints the class; never mutates.
# ALSO sets the TC_CLASS global — a whole-base caller can invoke it as
# `tc_classify_entry "$p" >/dev/null; cls="$TC_CLASS"` and skip the
# command-substitution fork (81k entries × ~0.5ms is the difference between a
# ~20s scan and a ~60s one).
TC_CLASS=""
tc_classify_entry() {
  local p="$1" name rc gc
  name="${p##*/}"
  _class() { TC_CLASS="$1"; printf '%s\n' "$1"; }
  # Git-pointer rung FIRST: a `.git` FILE resolves the entry through the
  # OWNING repo's worktree registry — verified attribution that must outrank
  # every name heuristic INCLUDING the prefix allowlist (a signature collision
  # inside a registered worktree — e.g. `soleur-inc-*` containing `.claude/` —
  # must never hijack the tree out of the registry-aware arm). Without this
  # rung the measured backlog class (`tmp.*` dirs bearing `.git`, ~1.5k on the
  # reference host) would be invisible to every consumer. `.git` DIRECTORIES
  # (standalone clones) keep protected-first ordering — report-only either way.
  if [[ -d "$p" && -f "$p/.git" && ! -L "$p/.git" ]]; then
    tc_classify_git_dir "$p" >/dev/null; gc="$TC_GITCLASS"
    case "$gc" in
      registered|unregistered|unverifiable) _class "worktree:$gc"; return 0 ;;
    esac
  fi
  tc_is_protected "$p" && { _class "protected"; return 0; }
  if [[ -f "$p" && ! -d "$p" ]]; then
    if tc_file_class "$p" >/dev/null 2>&1; then _class "$TC_FILE_CLASS"; else _class "unattributable"; fi
    return 0
  fi
  [[ -d "$p" ]] || { _class "unattributable"; return 0; }
  # marker rung — rc 2 (marker present but unverifiable) VETOES the schema
  # rung: a rejected declaration means every recorded identity is untrusted.
  # The `if` wrapper is load-bearing: a plain call returning nonzero aborts
  # under a caller's set -e before the rc can be read.
  if tc_marker_owner_pid "$p" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  case "$rc" in
    0) _class "marker:$TC_PID"; return 0 ;;
    2) _class "unattributable"; return 0 ;;
  esac
  # schema rung — only when NO marker exists (a vetoed marker already returned)
  if tc_schema_owner_pid "$name" >/dev/null 2>&1; then _class "schema:$TC_PID"; return 0; fi
  # prefix rung — BEFORE standalone-clone: `.git/config`-signature fixture
  # classes (pirgate-*, deploygap-gate-*) are attributable by content
  # signature; letting the clone rung preempt them made those rows dead code.
  if tc_prefix_class "$p" >/dev/null 2>&1; then _class "$TC_PREFIX_CLASS"; return 0; fi
  # standalone-clone rung (.git dir; report-only)
  tc_classify_git_dir "$p" >/dev/null; gc="$TC_GITCLASS"
  [[ "$gc" == "standalone-clone" ]] && { _class "standalone-clone"; return 0; }
  # empty rung
  tc_is_reapable_empty "$p" && { _class "empty"; return 0; }
  _class "unattributable"
}

# --- Retain-since stamps ----------------------------------------------------------
# Bound the retentive arm: an entry retained as unverifiable gets a stamp; once
# the stamp is older than TC_RETAIN_FLOOR_MIN the caller escalates it to the
# operator-decision list instead of re-reporting forever.

tc_retain_stamp() { # <path> — record/refresh first-seen; prints age in min
  local p="$1" sf now mtime
  sf="$TC_RETAIN_DIR/$(printf '%s' "$p" | sha256sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$p" | md5sum | cut -d' ' -f1)"
  now="$(date +%s)"
  if [[ ! -f "$sf" ]]; then
    mkdir -p -- "$TC_RETAIN_DIR" 2>/dev/null || { echo 0; return 0; }
    printf '%s\t%s\n' "$now" "$p" > "$sf" 2>/dev/null || { echo 0; return 0; }
    echo 0; return 0
  fi
  mtime="$(stat -c %Y -- "$sf" 2>/dev/null || stat -f %m -- "$sf" 2>/dev/null || echo "$now")"
  echo $(( (now - mtime) / 60 ))
}

# --- Quarantine move ---------------------------------------------------------------

# tc_tree_has_gitref <dir> — any `.git` file OR dir beneath the tree's top
# level. A nested worktree or clone makes the whole tree registry-relevant:
# deleting or quarantining it leaves the owning repo's .git/worktrees/<id>
# metadata dangling (prunable) and destroys dirty content no conjunct
# inspected. Reapers must retain such trees — the worktree arm owns them.
tc_tree_has_gitref() {
  [[ -d "$1" ]] || return 1
  # mindepth 2: the candidate's OWN .git (a worktree pointer file) is at depth
  # 1 — registry-handled by the worktree arm, not a nested ref. Nested refs
  # live at depth >= 2. head -1 short-circuits; find may take SIGPIPE — rc
  # is ignored anyway.
  [[ -n "$(find "$1" -mindepth 2 -name .git -print 2>/dev/null | head -1)" ]]
}

# tc_tree_has_mount <dir> — any entry on a DIFFERENT device than the tree's
# root. A bind/loop mount inside a candidate is live foreign filesystem
# content: `find -delete` would empty it, `mv` would relocate the mountpoint
# into quarantine where the drain later deletes through it. Fail CLOSED: a
# probe that can't see devices answers "has mount" (retain).
tc_tree_has_mount() {
  local dir="$1" dev lines
  [[ -d "$dir" ]] || return 1    # a regular file can't contain a mount
  dev="$(stat -c %d -- "$dir" 2>/dev/null || stat -f %d -- "$dir" 2>/dev/null)"
  [[ -n "$dev" ]] || return 0
  # %D is the device number (find's %d is depth — same letter, wrong field).
  lines="$(find "$dir" -mindepth 1 -printf '%D\n' 2>/dev/null)"
  if [[ -z "$lines" ]]; then
    # Empty tree → no mount possible. Non-empty tree with a probe that
    # produced nothing (no -printf) → can't verify → treat as mounted.
    [[ -n "$(ls -A -- "$dir" 2>/dev/null)" ]]
    return
  fi
  printf '%s\n' "$lines" | grep -qvx -- "$dev"
}

# tc_quar_age_min <entry> — minutes since the entry entered quarantine.
# rename(2) bumps ctime, so %Z records quarantine-ARRIVAL. Aging on content
# mtime instead (mv preserves it) collapses the recovery window to ~0 for the
# stale backlog that is quarantine's main population. Missing/unreadable ctime
# → 0 (fresh → retained; the recovery window errs long, never short).
tc_quar_age_min() {
  local e="$1" ct now
  ct="$(stat -c %Z -- "$e" 2>/dev/null || stat -f %c -- "$e" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  [[ "$ct" =~ ^[0-9]+$ && "$ct" -gt 0 && "$ct" -le "$now" ]] || { echo 0; return 0; }
  echo $(( (now - ct) / 60 ))
}

# tc_ledger_append <action> <class> <orig> <dest> — ONE ledger for every
# destructive action across every consumer (purge, Reaper 3, session sweep),
# so --restore's replay picture is complete. TSV fields: a path containing a
# tab or newline cannot be recorded faithfully — drop loudly rather than
# corrupt the file's row structure.
tc_ledger_append() {
  local line
  case "$1$2$3$4" in
    *$'\t'*|*$'\n'*)
      printf 'LEDGER-DROP: tab/newline in field — action NOT recorded: %s %s\n' "$1" "$3" >&2
      return 0 ;;
  esac
  mkdir -p -- "$(dirname "$TC_LEDGER")" 2>/dev/null || true
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\t'"$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"
  if ! printf '%s\n' "$line" >> "$TC_LEDGER" 2>/dev/null; then
    printf 'LEDGER-DROP: cannot append %s — action NOT recorded: %s\n' "$TC_LEDGER" "$line" >&2
    printf 'LEDGER-DROP: %s\n' "$line"
  fi
}

# tc_drain_quarantine <base> <dry> <scratch_ttl_min> <wt_ttl_min> — the ONLY
# delete permitted inside soleur-quarantine.<uid>/: entries whose QUARANTINE
# dwell exceeds the class TTL (subdir name encodes it). A symlinked or
# foreign-owned quarantine root/class dir refuses outright — a squatter on a
# world-writable base must not aim the drain at an arbitrary tree. Sets
# TC_DRAINED.
TC_DRAINED=0
tc_drain_quarantine() {
  local base="$1" dry="${2:-0}" sttl="${3:-10080}" wttl="${4:-43200}"
  local qroot cls ttl e
  TC_DRAINED=0
  qroot="$base/soleur-quarantine.$TC_UID"
  [[ -d "$qroot" && ! -L "$qroot" ]] || return 0
  [[ "$(tc_uid_of "$qroot")" == "$TC_UID" ]] || return 0
  for cls in "$qroot"/*/; do
    cls="${cls%/}"
    [[ -d "$cls" && ! -L "$cls" ]] || continue
    [[ "$(tc_uid_of "$cls")" == "$TC_UID" ]] || continue
    case "${cls##*/}" in worktrees) ttl="$wttl" ;; *) ttl="$sttl" ;; esac
    while IFS= read -r -d '' e; do
      [[ -e "$e" && ! -L "$e" ]] || continue          # planted link — never follow
      (( "$(tc_quar_age_min "$e")" >= ttl )) || continue
      tc_tree_has_mount "$e" && continue             # never delete into a mount
      if [[ "$dry" == "1" ]]; then
        printf 'would drain %s\n' "$e"; continue
      fi
      if find "$e" -xdev -depth -delete 2>/dev/null; then
        tc_ledger_append "drain" "${cls##*/}" "$e" "-"
        TC_DRAINED=$((TC_DRAINED + 1))
      fi
    done < <(find "$cls" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  done
  return 0
}

# tc_file_in_use <file> — a regular FILE held open: any /proc/*/fd symlink or
# environ value naming it. For the allowlisted file classes a >24h-old file
# can still be mid-write (pr-*-body.md consumed by `gh -F`); the top-level map
# marks directories, so files need their own probe.
tc_file_in_use() {
  local f="$1"
  [[ -d "$TC_PROC" ]] || return 0    # can't check → assume live (fail closed)
  [[ -n "$(find "$TC_PROC"/[0-9]*/fd -lname "$f" -print -quit 2>/dev/null)" ]] && return 0
  grep -lqsaF -- "$f" "$TC_PROC"/[0-9]*/environ 2>/dev/null && return 0
  return 1
}

# tc_reap_decide <dir> <age_floor_min> — the SHARED "safe to reap" conjunct
# chain for declared-owner candidates; single-sourced so consumers cannot
# diverge on the safety gates. Prints a verdict token:
#   reap           every conjunct passed — caller may delete/quarantine
#   retain:<why>   a conjunct failed or evidence was unverifiable
# Sets TC_DECL_KIND=marker|schema on success — consumers use it for the
# disposition split (schema-named roots may direct-delete on tmpfs; marker
# dirs quarantine on every base — a marker is a self-declared file, weaker
# attribution than the creation-time schema).
tc_reap_decide() {
  local dir="$1" floor="$2" rc
  TC_DECL_KIND=""
  # `if` context is load-bearing: a plain call's nonzero rc aborts under
  # set -e before it can be inspected.
  if tc_owner_pid_verify "$dir" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if   (( rc == 2 )); then printf 'retain:unverifiable'; return 0
  elif (( rc != 0 )); then printf 'retain:no-owner';      return 0
  fi
  tc_owner_alive "$TC_PID" && { printf 'retain:owner-live'; return 0; }
  tc_inuse_map_refresh || true
  tc_tree_has_live_handles "$dir" && { printf 'retain:live-handles'; return 0; }
  (( "$(tc_tree_age_min "$dir")" >= floor )) || { printf 'retain:fresh'; return 0; }
  tc_tree_has_gitref "$dir" && { printf 'retain:nested-git'; return 0; }
  tc_tree_has_mount "$dir" && { printf 'retain:nested-mount'; return 0; }
  printf 'reap'
}

# --- Quarantine move ---------------------------------------------------------------

# tc_quarantine_move <path> <base> <class-subdir>
# mv into <base>/soleur-quarantine.<uid>/<class>/ with the pre-move checks:
# quarantine root not a symlink, owned by TC_UID, same-device (EXDEV refuses —
# mv, never copy), basename collision → numeric suffix with `mv -n` closing the
# check-then-act window. Prints the final quarantine path. rc 1 = refused
# (nothing moved).
tc_quarantine_move() {
  local src="$1" base="$2" cls="$3"
  local qroot qdir
  qroot="$base/soleur-quarantine.$TC_UID"; qdir="$qroot/$cls"
  local src_dev base_dev
  src_dev="$(stat -c %d -- "$src" 2>/dev/null || stat -f %d -- "$src" 2>/dev/null || echo x)"
  base_dev="$(stat -c %d -- "$base" 2>/dev/null || stat -f %d -- "$base" 2>/dev/null || echo y)"
  [[ "$src_dev" != "x" && "$src_dev" == "$base_dev" ]] || return 1  # EXDEV → refuse
  [[ ! -L "$qroot" && ! -L "$qdir" ]] || return 1
  # A foreign-owned qroot means a squatter pre-created our quarantine dir —
  # moved trees (which can carry .env-local-class secrets) would land inside
  # an attacker-owned root, and restore would replay tampered content.
  if [[ -d "$qroot" ]] && [[ "$(tc_uid_of "$qroot")" != "$TC_UID" ]]; then return 1; fi
  mkdir -p -- "$qdir" 2>/dev/null || return 1
  chmod 0700 "$qroot" "$qdir" 2>/dev/null || return 1
  local dest name i=0
  name="${src##*/}"
  dest="$qdir/$name"
  while [[ -e "$dest" || -L "$dest" ]]; do
    i=$((i + 1)); dest="$qdir/$name.$i"
  done
  # `mv -n` returns success even when it skips (a racer claimed $dest in the
  # check-then-act gap) — verify the move actually happened.
  mv -n -- "$src" "$dest" 2>/dev/null || return 1
  [[ ! -e "$src" && -e "$dest" ]] || return 1
  printf '%s' "$dest"
}
