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
# ATTRIBUTION LADDER (first match wins; protected is evaluated BEFORE all)
#   protected        never a candidate (systemd-private-*, skill-security-scan-*,
#                    bare tmp.*, quarantine artifacts, claude-<uid>, ...)
#   marker           <dir>/.soleur-owned valid marker → declared-owned
#   schema           soleur-run.<pid>.XXXXXXXX → declared-owned
#   worktree         .git FILE present → git registry classification
#   standalone-clone .git DIRECTORY present → report-only, never a candidate
#   empty            empty dir + long random-looking name → rmdir candidate
#   prefix:<name>    allowlisted prefix + required subpath signature present
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

# --- Protected names ---------------------------------------------------------
# Evaluated BEFORE every ladder rung: a future allowlist row must never outrank
# a protection. Quarantine artifacts are excluded from enumeration entirely
# here as a second layer beneath the caller's own exclusion.

tc_is_protected() {
  local name; name="$(basename -- "$1")"
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

# tc_marker_owner_pid <dir> → prints owner pid; rc 1 when marker absent/invalid.
# Marker contract: regular file, not a symlink, owned by TC_UID, carrying
# `pid=<top-level-harness-pid>` OR `owner_root=<soleur-run.* dir>`, plus
# `schema=` and `ns=pid:[<inode>]`.
tc_marker_owner_pid() {
  local dir="$1" m="$1/.soleur-owned" pid="" oroot="" ns=""
  [[ -f "$m" && ! -L "$m" ]] || return 1
  [[ "$(stat -c %u -- "$m" 2>/dev/null)" == "$TC_UID" ]] || return 1
  pid="$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$m" 2>/dev/null | head -1)"
  ns="$(sed -n 's/^ns=\(pid:\[[0-9]*\]\)$/\1/p' "$m" 2>/dev/null | head -1)"
  if [[ -n "$ns" && "$ns" != "$(tc_my_pid_ns)" ]]; then
    return 1   # marker written in another pid namespace — unverifiable, not trusted
  fi
  if [[ -z "$pid" ]]; then
    oroot="$(sed -n 's/^owner_root=\([^[:space:]]*\)$/\1/p' "$m" 2>/dev/null | head -1)"
    [[ -n "$oroot" ]] || return 1
    pid="$(tc_schema_owner_pid "$(basename -- "$oroot")" 2>/dev/null || true)"
    [[ -n "$pid" ]] || pid="$(tc_marker_owner_pid "$oroot" 2>/dev/null || true)"
    [[ -n "$pid" ]] || return 1
  fi
  printf '%s' "$pid"
}

# tc_schema_owner_pid <basename> → prints pid from soleur-run.<pid>.XXXXXXXX.
tc_schema_owner_pid() {
  local n="$1"
  [[ "$n" =~ ^soleur-run\.([0-9]+)\.[A-Za-z0-9_-]{8,}$ ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# tc_my_pid_ns → `pid:[<inode>]` of the caller's own pid namespace.
tc_my_pid_ns() {
  readlink "$TC_PROC/self/ns/pid" 2>/dev/null || printf 'pid:[unknown]'
}

# --- Liveness ------------------------------------------------------------------

# tc_owner_alive <pid> — /proc presence ONLY. Foreign reuse stays retentive
# downstream because the fd/environ conjuncts still apply.
tc_owner_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -d "$TC_PROC/$pid" ]]
}

# tc_tree_has_live_handles <dir> — scan procfs once for ANY process holding the
# dir: cwd, open fds, or environ containing the path. Fails CLOSED (returns
# "live") when procfs is unreadable — a degraded host must never prove "dead".
tc_tree_has_live_handles() {
  local dir="$1" p fd target
  [[ -d "$TC_PROC" ]] || return 0
  for p in "$TC_PROC"/[0-9]*; do
    [[ -d "$p" ]] || continue
    if target="$(readlink "$p/cwd" 2>/dev/null)" && [[ "$target" == "$dir" || "$target" == "$dir"/* ]]; then
      return 0
    fi
    for fd in "$p"/fd/*; do
      target="$(readlink "$fd" 2>/dev/null)" || continue
      if [[ "$target" == "$dir" || "$target" == "$dir"/* ]]; then return 0; fi
    done
    if grep -aqF -- "$dir" "$p/environ" 2>/dev/null; then return 0; fi
  done
  return 1
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
# defect class). Missing find -printf → prints 0 (fresh → retained).
tc_tree_age_min() {
  local dir="$1" newest now
  newest="$(find "$dir" -printf '%T@\n' 2>/dev/null | LC_ALL=C sort -rn 2>/dev/null | head -1 | cut -d. -f1)"
  if [[ ! "$newest" =~ ^[0-9]+$ ]]; then
    newest="$(stat -c %Y -- "$dir" 2>/dev/null || stat -f %m -- "$dir" 2>/dev/null || echo 0)"
  fi
  now="$(date +%s)"
  if (( newest <= 0 || newest > now )); then echo 0; else echo $(( (now - newest) / 60 )); fi
}

# --- Empty-dir rung ----------------------------------------------------------------

# tc_is_reapable_empty <dir> — empty AND a random-looking ≥15-char basename
# AND not a mountpoint (device-id compare against parent doubles as the
# BSD-portable mountpoint check).
tc_is_reapable_empty() {
  local dir="$1" name
  name="$(basename -- "$dir")"
  [[ "$name" =~ ^[A-Za-z0-9_.-]{15,}$ ]] || return 1
  [[ -d "$dir" && -z "$(ls -A -- "$dir" 2>/dev/null)" ]] || return 1
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
tc_classify_git_dir() {
  local dir="$1" gf="$1/.git" gitdir main_gitdir
  if [[ -d "$gf" && ! -L "$gf" ]]; then echo "standalone-clone"; return 0; fi
  [[ -f "$gf" && ! -L "$gf" ]] || { echo "not-git"; return 0; }
  gitdir="$(sed -n 's/^gitdir:[[:space:]]*//p' "$gf" 2>/dev/null | head -1)"
  [[ -n "$gitdir" ]] || { echo "unverifiable"; return 0; }
  [[ "$gitdir" != /* ]] && gitdir="$dir/$gitdir"
  gitdir="$(realpath -m -- "$gitdir" 2>/dev/null || printf '%s' "$gitdir")"
  [[ -d "$gitdir" ]] || { echo "unverifiable"; return 0; }
  # gitdir shape is <main>/.git/worktrees/<name> — main repo gitdir is two up.
  main_gitdir="$(dirname "$(dirname "$gitdir")")"
  [[ -d "$main_gitdir/objects" || -f "$main_gitdir/HEAD" ]] || { echo "unverifiable"; return 0; }
  local real_dir listing
  real_dir="$(realpath -m -- "$dir" 2>/dev/null || printf '%s' "$dir")"
  if ! listing="$(git --git-dir="$main_gitdir" worktree list --porcelain 2>/dev/null)"; then
    echo "unverifiable"; return 0
  fi
  [[ -n "$listing" ]] || { echo "unverifiable"; return 0; }
  local wt found=0
  while IFS= read -r wt; do
    [[ -n "$wt" ]] || continue
    if [[ "$(realpath -m -- "$wt" 2>/dev/null || printf '%s' "$wt")" == "$real_dir" ]]; then
      found=1; break
    fi
  done <<< "$(printf '%s\n' "$listing" | sed -n 's/^worktree //p')"
  if (( found == 1 )); then echo "registered"; else echo "unregistered"; fi
}

# tc_git_main_dir <dir> → prints the owning repo's gitdir (rc 1 if unverifiable).
tc_git_main_dir() {
  local dir="$1" gf="$1/.git" gitdir
  [[ -f "$gf" && ! -L "$gf" ]] || return 1
  gitdir="$(sed -n 's/^gitdir:[[:space:]]*//p' "$gf" 2>/dev/null | head -1)"
  [[ -n "$gitdir" ]] || return 1
  [[ "$gitdir" != /* ]] && gitdir="$dir/$gitdir"
  gitdir="$(realpath -m -- "$gitdir" 2>/dev/null || printf '%s' "$gitdir")"
  [[ -d "$gitdir" ]] || return 1
  dirname "$(dirname "$gitdir")"
}

# tc_worktree_clean <dir> — no modified AND no untracked AND no ignored files.
# `--ignored` is load-bearing: porcelain omits ignored paths, so a worktree
# holding only `.env.local` must NOT read clean.
tc_worktree_clean() {
  local dir="$1" out
  out="$(git -C "$dir" status --porcelain --ignored 2>/dev/null)" || return 1
  [[ -z "$out" ]]
}

# tc_default_ref <main_gitdir> — the owning repo's default ref AS LAST FETCHED:
# origin/HEAD → the main worktree's checked-out branch → main/master. No fetch.
tc_default_ref() {
  local main="$1" sym
  sym="$(git --git-dir="$main" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  [[ -n "$sym" ]] && { printf '%s' "$sym"; return 0; }
  sym="$(git --git-dir="$main" symbolic-ref --quiet --short HEAD 2>/dev/null)"
  [[ -n "$sym" ]] && { printf '%s' "$sym"; return 0; }
  for sym in main master; do
    git --git-dir="$main" rev-parse --verify --quiet "$sym" >/dev/null 2>&1 && { printf '%s' "$sym"; return 0; }
  done
  return 1
}

# tc_worktree_safe_to_remove <dir> — registered + clean + merged + no-unpushed
# + no live process inside. Caller applies the age floor separately.
tc_worktree_safe_to_remove() {
  local dir="$1" main head upstream
  main="$(tc_git_main_dir "$dir")" || return 1
  tc_worktree_clean "$dir" || return 1
  head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)" || return 1
  local defref
  defref="$(tc_default_ref "$main")" || return 1
  git --git-dir="$main" merge-base --is-ancestor "$head" "$defref" 2>/dev/null || return 1
  upstream="$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    local ahead
    ahead="$(git -C "$dir" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 999)"
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

# tc_prefix_class <dir> → prints `prefix:<prefix>` when the basename matches an
# allowlist prefix AND the required subpath exists. rc 1 otherwise.
tc_prefix_class() {
  local dir="$1" name row prefix sig
  name="$(basename -- "$dir")"
  for row in "${TC_DIR_ALLOWLIST[@]}"; do
    prefix="${row%%|*}"; sig="$(printf '%s' "$row" | cut -d'|' -f2)"
    # shellcheck disable=SC2254  # prefix is a deliberate glob from the frozen list
    case "$name" in $prefix)
      compgen -G "$dir/$sig" >/dev/null 2>&1 && { printf 'prefix:%s' "$prefix"; return 0; }
      ;;
    esac
  done
  return 1
}

# tc_file_class <file> → prints `file:<shape>` for allowlisted regular files.
tc_file_class() {
  local f="$1" name row prefix
  [[ -f "$f" && ! -L "$f" ]] || return 1
  [[ "$(stat -c %u -- "$f" 2>/dev/null)" == "$TC_UID" ]] || return 1
  name="$(basename -- "$f")"
  for row in "${TC_FILE_ALLOWLIST[@]}"; do
    prefix="${row%%|*}"
    # shellcheck disable=SC2254
    case "$name" in $prefix) printf 'file:%s' "$prefix"; return 0 ;; esac
  done
  return 1
}

# --- Top-level classification -----------------------------------------------------

# tc_classify_entry <path> → prints the class; never mutates.
tc_classify_entry() {
  local p="$1" name pid
  name="$(basename -- "$p")"
  tc_is_protected "$p" && { echo "protected"; return 0; }
  if [[ -f "$p" && ! -d "$p" ]]; then
    tc_file_class "$p" || echo "unattributable"
    return 0
  fi
  [[ -d "$p" ]] || { echo "unattributable"; return 0; }
  # marker rung
  if pid="$(tc_marker_owner_pid "$p")"; then echo "marker:$pid"; return 0; fi
  # schema rung
  if pid="$(tc_schema_owner_pid "$name")"; then echo "schema:$pid"; return 0; fi
  # git rungs
  local gc
  gc="$(tc_classify_git_dir "$p")"
  case "$gc" in
    standalone-clone|registered|unregistered|unverifiable)
      # A dir matching a signed prefix class AND carrying .git still classifies
      # by prefix — known fixture clones reclaim via their producer signature.
      if tc_prefix_class "$p" >/dev/null 2>&1; then tc_prefix_class "$p"; return 0; fi
      [[ "$gc" == "standalone-clone" ]] && { echo "standalone-clone"; return 0; }
      echo "worktree:$gc"; return 0 ;;
  esac
  # empty rung
  tc_is_reapable_empty "$p" && { echo "empty"; return 0; }
  # prefix rung
  tc_prefix_class "$p" && return 0
  echo "unattributable"
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

# tc_quarantine_move <path> <base> <class-subdir>
# mv into <base>/soleur-quarantine.<uid>/<class>/ with the pre-move checks:
# quarantine root not a symlink/mountpoint (device compare fails loud on EXDEV),
# basename collision → numeric suffix. Prints the final quarantine path.
# rc 1 = refused (nothing moved).
tc_quarantine_move() {
  local src="$1" base="$2" cls="$3"
  local qroot qdir
  qroot="$base/soleur-quarantine.$TC_UID"; qdir="$qroot/$cls"
  local src_dev base_dev
  src_dev="$(stat -c %d -- "$src" 2>/dev/null || stat -f %d -- "$src" 2>/dev/null || echo x)"
  base_dev="$(stat -c %d -- "$base" 2>/dev/null || stat -f %d -- "$base" 2>/dev/null || echo y)"
  [[ "$src_dev" != "x" && "$src_dev" == "$base_dev" ]] || return 1  # EXDEV → refuse
  [[ ! -L "$qroot" && ! -L "$qdir" ]] || return 1
  mkdir -p -- "$qdir" 2>/dev/null || return 1
  chmod 0700 "$qroot" 2>/dev/null || true
  local dest name i=0
  name="$(basename -- "$src")"
  dest="$qdir/$name"
  while [[ -e "$dest" ]]; do
    i=$((i + 1)); dest="$qdir/$name.$i"
  done
  mv -- "$src" "$dest" 2>/dev/null || return 1
  printf '%s' "$dest"
}
