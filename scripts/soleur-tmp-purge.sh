#!/usr/bin/env bash
# soleur-tmp-purge.sh — operator-invoked reclamation of stale Soleur scratch.
#
# Modes:
#   --dry-run   (default) classify every top-level entry under each base and
#               print a SOLEUR_TMP_PURGE report: per-class counts + est. bytes.
#   --apply     quarantine the certain-attribution classes (marker/schema dead
#               owners, proven-unregistered worktrees, signed prefix classes,
#               allowlisted file shapes, reapable empty dirs); registered
#               worktrees passing every conjunct go through `git worktree
#               remove`; everything unverifiable is RETAINED + stamped.
#   --restore [name|all]   mv quarantined entries back per the ledger.
#   --drain     delete quarantine entries past their class TTL.
#   --report    STRICTLY READ-ONLY (no lock, no ledger, no stamps, no moves):
#               per-class count+size, top-N prefix FAMILIES by size with the
#               unattributable bucket split out (vac*/td-*/perf-*/mut*/
#               sdkprobe.* stay visible), and per family a `.git`-bearing vs
#               non-`.git` size split (a `.git` within 4 levels of the entry),
#               plus quarantine bytes awaiting drain. Header line
#               SOLEUR_TMP_PURGE_REPORT. Report-only flags:
#                 --base DIR            scan DIR instead of the default bases
#                                       (repeatable; replaces SOLEUR_PURGE_BASES)
#                 --older-than-days N   keep only entries whose NEWEST mtime
#                                       anywhere in the tree is >= N days old
#               Space recovery after an --apply (quarantine frees nothing on
#               the same disk until drain):
#                 SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 soleur-tmp-purge.sh --drain
#
# SAFETY CONTRACT (ADR-124 / ADR-195 lineage)
#   * No content reads; no `rm -rf`/`find -delete` on shared-base paths — the
#     ONLY deletes are `rmdir` on verified-empty dirs, `git worktree remove`,
#     and the quarantine-internal TTL drain (the drain IS a terminal delete,
#     scoped strictly beneath soleur-quarantine.<uid>/).
#   * mv, never copy: same-device enforced; EXDEV refuses rather than
#     degrading to copy+unlink.
#   * Unattributable classes are reported, never moved. `tmp.*` belongs to
#     systemd-tmpfiles' 30d/10d aging, not us.
#   * Serialized by flock on a TMPDIR-independent lockfile; concurrent runs
#     skip loudly.
#
# SEAMS (env; tests point these at a sentinel root):
#   SOLEUR_PURGE_BASES      space-separated bases   (default "/tmp /var/tmp")
#   SOLEUR_PURGE_LEDGER     ledger path             (~/.local/state/soleur/tmp-purge-ledger.log)
#   SOLEUR_PURGE_LOCKFILE   serialization lock      (~/.local/state/soleur/tmp-guard.lock)
#   SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN / SOLEUR_PURGE_QUAR_WT_TTL_MIN
#   SOLEUR_PURGE_REPORT_TOP N   rows per --report family table (default 20)
#   SOLEUR_PURGE_DRY_RUN=1  forces report-only even under --apply
#
# Exit codes: 0 ok · 1 usage/fail-closed · 2 lock contention (nothing done)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the shared classifier: repo checkout first, then a shipped plugin root.
_TC_LIB=""
for cand in \
  "$SCRIPT_DIR/../plugins/soleur/scripts/lib/tmp-classify.sh" \
  "${CLAUDE_PLUGIN_ROOT:-}/scripts/lib/tmp-classify.sh"; do
  [[ -f "$cand" ]] && _TC_LIB="$cand" && break
done
if [[ -z "$_TC_LIB" ]] && command -v git >/dev/null 2>&1; then
  _top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$_top" && -f "$_top/plugins/soleur/scripts/lib/tmp-classify.sh" ]] \
    && _TC_LIB="$_top/plugins/soleur/scripts/lib/tmp-classify.sh"
fi
if [[ -z "$_TC_LIB" ]]; then
  echo "SOLEUR_TMP_PURGE FATAL: tmp-classify.sh not found (repo checkout or plugin install required)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$_TC_LIB"

shopt -s extglob   # tc_family / report only; no effect on the mutating arms
BASES="${SOLEUR_PURGE_BASES-/tmp /var/tmp}"
[[ -n "${BASES//[[:space:]]/}" ]] || { echo "SOLEUR_TMP_PURGE FATAL: base list empty; refusing (fail-closed). An empty SOLEUR_PURGE_BASES is honored, not defaulted — unset it to use /tmp /var/tmp." >&2; exit 1; }

LOCKFILE="${SOLEUR_PURGE_LOCKFILE:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/tmp-guard.lock}"
TTL_SCRATCH="${SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN:-10080}"   # 7d
TTL_WT="${SOLEUR_PURGE_QUAR_WT_TTL_MIN:-43200}"             # 30d
DRY_RUN="${SOLEUR_PURGE_DRY_RUN:-0}"

MODE="dry-run"; RESTORE_ARG=""
REPORT=0; EXPLICIT_MODE=0; OLDER_DAYS=""; BASE_ARGS=()
REPORT_TOP="${SOLEUR_PURGE_REPORT_TOP:-20}"
[[ "$REPORT_TOP" =~ ^[0-9]+$ ]] || REPORT_TOP=20
_usage() { echo "usage: soleur-tmp-purge.sh [--dry-run|--apply|--restore [name|all]|--drain|--report [--base DIR]... [--older-than-days N]]" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; EXPLICIT_MODE=1 ;;
    --apply)   MODE="apply"; EXPLICIT_MODE=1 ;;
    --restore)
      MODE="restore"; EXPLICIT_MODE=1
      # Only a non-flag argument is a restore target — `--restore --apply`
      # must not swallow the next flag, and bare `--restore` must not shift
      # past the end (set -e would kill the script silently).
      if [[ -n "${2:-}" && "$2" != -* ]]; then RESTORE_ARG="$2"; shift; else RESTORE_ARG="all"; fi ;;
    --drain)   MODE="drain"; EXPLICIT_MODE=1 ;;
    --report)  REPORT=1 ;;
    --base)
      # Report-only seam. A base containing whitespace cannot survive the
      # space-separated BASES list — refuse instead of splitting it.
      [[ -n "${2:-}" && "$2" != -* && "$2" != *[[:space:]]* ]] || _usage
      BASE_ARGS+=("$2"); shift ;;
    --older-than-days)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || _usage
      OLDER_DAYS="$2"; shift ;;
    -h|--help) sed -n '2,/^# Exit codes/p' "$0"; exit 0 ;;
    *) _usage ;;
  esac
  shift
done
# --report is exclusive with every other mode, and --base/--older-than-days
# exist only for it: neither may widen what a MUTATING mode can reach.
if (( REPORT )); then
  (( EXPLICIT_MODE )) && { echo "SOLEUR_TMP_PURGE: --report cannot be combined with --dry-run/--apply/--restore/--drain" >&2; exit 1; }
  MODE="report"
  if ((${#BASE_ARGS[@]})); then BASES="${BASE_ARGS[*]}"; fi
elif ((${#BASE_ARGS[@]})) || [[ -n "$OLDER_DAYS" ]]; then
  echo "SOLEUR_TMP_PURGE: --base and --older-than-days are --report-only flags" >&2; exit 1
fi
[[ "$DRY_RUN" == "1" && "$MODE" == "apply" ]] && MODE="dry-run"

# --- serialization -------------------------------------------------------------
# --report is exempt: it writes nothing (not even the lock file), so there is
# nothing to serialize and it must stay runnable while a purge is in flight.
if [[ "$MODE" != "report" ]]; then
  mkdir -p -- "$(dirname "$LOCKFILE")" 2>/dev/null || true
  exec 9>>"$LOCKFILE"
  if ! flock -n 9; then
    echo "SOLEUR_TMP_PURGE SKIP: another purge/sweep/guard holds $LOCKFILE"
    exit 2
  fi
fi

# --- ledger ----------------------------------------------------------------------
# tc_ledger_append (from tmp-classify.sh) is THE ledger — every consumer
# (purge, Reaper 3, session sweep) writes the same file so this restore
# picture is complete. $LEDGER stays as this script's display name for it.
LEDGER="$TC_LEDGER"

# --- drain -----------------------------------------------------------------------
# Shared with tmpfs-guard via tc_drain_quarantine: quarantine dwell is the
# entry's ctime (rename bumps it), not content mtime — aging on mtime makes
# the recovery window ~0 for the stale backlog that is quarantine's main
# population.
drain_quarantine() {
  local base drained=0
  for base in $BASES; do
    tc_drain_quarantine "$base" "$DRY_RUN" "$TTL_SCRATCH" "$TTL_WT"
    drained=$((drained + TC_DRAINED))
  done
  echo "SOLEUR_TMP_PURGE drain: $drained entr$( (( drained == 1 )) && echo y || echo ies) removed"
}

# --- restore ---------------------------------------------------------------------
do_restore() {
  local target="$1" orig quar
  [[ -f "$LEDGER" ]] || { echo "SOLEUR_TMP_PURGE restore: no ledger at $LEDGER"; exit 1; }
  while IFS=$'\t' read -r _ts action cls orig quar; do
    [[ "$action" == "move" ]] || continue
    [[ -n "${quar:-}" ]] || continue
    case "$quar" in
      */soleur-quarantine.*/*) ;;    # ledger rows only move quarantined paths
      *) echo "  restore-skip $quar — path is not beneath a quarantine root"; continue ;;
    esac
    if [[ ! -e "$quar" && ! -L "$quar" ]]; then
      echo "  restore-skip $quar — already gone (drained or moved)"
      continue
    fi
    if [[ "$target" == "all" || "$(basename -- "$quar")" == "$target" || "$quar" == "$target" ]]; then
      if [[ -e "$orig" ]]; then
        echo "  restore-skip $(basename -- "$quar") — $orig exists"
        continue
      fi
      if mv -- "$quar" "$orig"; then
        tc_ledger_append "restore" "$cls" "$quar" "$orig"
        echo "  restored $(basename -- "$orig")"
      else
        # The recovery surface must fail LOUD — a silent skip reads as success.
        echo "  RESTORE-FAIL $quar -> $orig" >&2
      fi
    fi
  done < "$LEDGER"
}

# --- enumeration + classification -------------------------------------------------

# Explicit `=()` on all three: a declared-but-unassigned assoc array is UNSET
# under `set -u` in bash 5.3, so an empty base crashed the report print (rc 1).
declare -A CLASS_COUNT=() CLASS_BYTES=() _CLASS_OF=()
OPERATOR_LIST=()

bump() { # class bytes
  CLASS_COUNT["$1"]=$(( ${CLASS_COUNT["$1"]:-0} + 1 ))
  CLASS_BYTES["$1"]=$(( ${CLASS_BYTES["$1"]:-0} + $2 ))
}

# decide_apply <path> <class> — apply-mode disposition. Prints a row per entry.
# Declared-owner classes route through tc_reap_decide — the same conjunct
# chain Reaper 3 and the sweep use — so the "safe to move" predicate is
# single-sourced. Operator-tool disposition is always quarantine (no direct
# delete), and every mutation lands a ledger row.
decide_apply() {
  local p="$1" cls="$2" dest age verdict
  case "$cls" in
    marker:*|schema:*)
      verdict="$(tc_reap_decide "$p" "$TC_AGE_FLOOR_MIN")"
      [[ "$verdict" == "reap" ]] || { echo "  retain $p ($verdict)"; return 0; }
      dest="$(tc_quarantine_move "$p" "$(dirname "$p")" "scratch")" \
        && { tc_ledger_append "move" "scratch" "$p" "$dest"; echo "  QUARANTINE $p -> $dest"; } \
        || echo "  RETAIN $p (move refused)"
      ;;
    empty)
      if tc_entry_is_live "$p" ""; then echo "  retain $p (live)"; return 0; fi
      age="$(tc_tree_age_min "$p")"; (( age >= TC_AGE_FLOOR_MIN )) || { echo "  retain $p (age ${age}m<${TC_AGE_FLOOR_MIN}m)"; return 0; }
      rmdir -- "$p" 2>/dev/null && { tc_ledger_append "rmdir" "empty" "$p" "-"; echo "  RMDIR $p"; } || echo "  retain $p (rmdir refused)"
      ;;
    prefix:*|file:*)
      if [[ -d "$p" ]] && tc_entry_is_live "$p" ""; then echo "  retain $p (live)"; return 0; fi
      if [[ -f "$p" ]] && tc_file_in_use "$p"; then echo "  retain $p (file in use)"; return 0; fi
      age="$(tc_tree_age_min "$p")"; (( age >= TC_AGE_FLOOR_MIN )) || { echo "  retain $p (young)"; return 0; }
      # A signature-matched dir can still hold a nested .git tree or a live
      # mount — the signature proves authorship, not internal emptiness.
      tc_tree_has_gitref "$p" && { echo "  retain $p (nested-git)"; return 0; }
      tc_tree_has_mount "$p" && { echo "  retain $p (nested-mount)"; return 0; }
      tc_inuse_map_refresh || true   # bound map staleness before the move lands
      dest="$(tc_quarantine_move "$p" "$(dirname "$p")" "prefix")" \
        && { tc_ledger_append "move" "prefix" "$p" "$dest"; echo "  QUARANTINE $p -> $dest"; } \
        || echo "  RETAIN $p (move refused)"
      ;;
    worktree:unregistered)
      age="$(tc_tree_age_min "$p")"; (( age >= TC_WT_FLOOR_MIN )) || { echo "  retain $p (young)"; return 0; }
      if tc_entry_is_live "$p" ""; then echo "  retain $p (live)"; return 0; fi
      tc_tree_has_gitref "$p" && { echo "  retain $p (nested-git)"; return 0; }
      tc_tree_has_mount "$p" && { echo "  retain $p (nested-mount)"; return 0; }
      dest="$(tc_quarantine_move "$p" "$(dirname "$p")" "worktrees")" \
        && { tc_ledger_append "move" "worktrees" "$p" "$dest"; echo "  QUARANTINE $p -> $dest"; } \
        || echo "  RETAIN $p (move refused)"
      ;;
    worktree:registered)
      age="$(tc_tree_age_min "$p")"; (( age >= TC_WT_FLOOR_MIN )) || { echo "  retain $p (young)"; return 0; }
      if tc_worktree_safe_to_remove "$p"; then
        local main; main="$(tc_git_main_dir "$p")" || { echo "  retain $p (gitdir lost)"; return 0; }
        _tc_git --git-dir="$main" worktree remove "$p" 2>/dev/null \
          && { tc_ledger_append "worktree-remove" "worktrees" "$p" "-"; echo "  WT-REMOVE $p"; } \
          || echo "  retain $p (worktree remove failed)"
      else
        echo "  retain $p (not clean/merged/pushed or live)"
      fi
      ;;
    worktree:unverifiable)
      local rmin; rmin="$(tc_retain_stamp "$p")"
      if (( rmin >= TC_RETAIN_FLOOR_MIN )); then
        OPERATOR_LIST+=("$p")
        echo "  OPERATOR-DECISION $p (unverifiable ${rmin}m)"
      else
        echo "  retain $p (unverifiable, retain-since ${rmin}m)"
      fi
      ;;
    *) echo "  report-only $p ($cls)" ;;
  esac
}

run_scan() {
  local base entry cls skipped_odd=0
  local -a entries=() sized_paths=()
  for base in $BASES; do
    [[ -d "$base" && ! -L "$base" ]] || { echo "SOLEUR_TMP_PURGE: base $base missing or a symlink — skipping"; continue; }
    # -user "$TC_UID" scopes to our own entries: on a non-sticky operator-set
    # base the disposition arms could otherwise move another user's dirs.
    # -print0 + mapfile -d '' keeps newline-named entries whole — a split
    # fragment would be evaluated as a cwd-relative fake candidate.
    mapfile -t -d '' entries < <(find "$base" -mindepth 1 -maxdepth 1 \
      -user "$TC_UID" ! -name 'soleur-quarantine.*' -print0 2>/dev/null | LC_ALL=C sort -z)
    echo "SOLEUR_TMP_PURGE scanning $base (${#entries[@]} entries)…" >&2
    # Bulk liveness for apply mode: one /proc walk feeds every conjunct.
    if [[ "$MODE" == "apply" ]]; then tc_build_inuse_map "$base" || true; fi
    for entry in "${entries[@]}"; do
      if [[ "$entry" == *$'\n'* || "$entry" == *$'\t'* ]]; then
        skipped_odd=$((skipped_odd + 1)); continue
      fi
      tc_classify_entry "$entry" >/dev/null; cls="$TC_CLASS"   # no per-entry fork
      bump "$cls" 0
      # Sizes only for classes a report consumer can act on — `du` walks each
      # tree, and on a measured 18k-entry base that is minutes of syscall time
      # for rows the operator cannot move anyway.
      case "$cls" in
        marker:*|schema:*|empty|prefix:*|file:*|worktree:*)
          sized_paths+=("$entry"); _CLASS_OF["$entry"]="$cls" ;;
      esac
      if [[ "$MODE" == "apply" ]]; then decide_apply "$entry" "$cls"; fi
    done
    # One du over just the actionable subset.
    if ((${#sized_paths[@]})); then
      local sz p
      while IFS=$'\t' read -r sz p; do
        [[ -n "$p" && -n "${_CLASS_OF[$p]:-}" ]] \
          && CLASS_BYTES["${_CLASS_OF[$p]}"]=$(( ${CLASS_BYTES["${_CLASS_OF[$p]}"]:-0} + sz ))
      done < <(printf '%s\0' "${sized_paths[@]}" | xargs -0 du -sk 2>/dev/null)
    fi
    sized_paths=()
  done
  # `if`, not `&&` — a plain `(( )) &&` list at function tail returns 1 when
  # zero were skipped, and set -e would abort before the report prints.
  if (( skipped_odd > 0 )); then
    echo "SOLEUR_TMP_PURGE: skipped $skipped_odd entr$( (( skipped_odd == 1 )) && echo y || echo ies) with control characters in the name — never actioned" >&2
  fi
}


# --- report (read-only) ---------------------------------------------------------
# tc_family <basename> -> FAM: name shape with the random suffix replaced by
# `*` and digit-only segments by `N`, so `tmp.Ab12Cd34`, `vac1234`, `td-123`,
# `soleur-run.4152.abcd1234` become `tmp.*`, `vac*`, `td-*`, `soleur-run.N.*`.
# Pure bash (no fork per entry — report mode walks bases with 10k+ entries).
FAM=""
tc_family() {
  local t="$1"
  if   [[ "$t" =~ ^(.*[-._])([A-Za-z0-9]{4,})$ ]]; then t="${BASH_REMATCH[1]}*"
  elif [[ "$t" =~ ^(.*[-._])([0-9]+)$ ]];           then t="${BASH_REMATCH[1]}*"
  elif [[ "$t" =~ ^([A-Za-z]{2,}[-_]?)[0-9][A-Za-z0-9._]*$ ]]; then t="${BASH_REMATCH[1]}*"
  fi
  while [[ "$t" =~ ^(.*[-._])[0-9]+([-._].*)$ ]]; do t="${BASH_REMATCH[1]}N${BASH_REMATCH[2]}"; done
  FAM="$t"
}

run_report() {
  local base entry cls bucket age sz p g rel key fam kb is_git rows
  local -a entries=() kept=()
  local -A HAS_GIT=() KCLS=() F_N=() F_KB=() F_GIT=() F_NOGIT=() C_N=() C_KB=()
  local skipped_odd=0 filtered=0 min_age=0
  [[ -n "$OLDER_DAYS" ]] && min_age=$(( OLDER_DAYS * 1440 ))

  echo "SOLEUR_TMP_PURGE_REPORT mode=report bases=[$BASES] older_than_days=${OLDER_DAYS:-none} top=$REPORT_TOP read-only=1"
  for base in $BASES; do
    [[ -d "$base" && ! -L "$base" ]] || { echo "SOLEUR_TMP_PURGE_REPORT base $base missing or a symlink — skipped"; continue; }
    mapfile -t -d '' entries < <(find "$base" -mindepth 1 -maxdepth 1 \
      -user "$TC_UID" ! -name 'soleur-quarantine.*' -print0 2>/dev/null | LC_ALL=C sort -z)
    # One bounded walk finds every `.git` within 4 levels of an entry (an
    # entry's own `.git` is depth 2); node_modules is pruned — a vendored
    # package's .git says nothing about the entry's registry exposure.
    HAS_GIT=()
    while IFS= read -r -d '' g; do
      rel="${g#"$base"/}"; HAS_GIT["$base/${rel%%/*}"]=1
    done < <(find "$base" -xdev -mindepth 2 -maxdepth 5 \( -name node_modules -prune \) -o -name .git -print0 2>/dev/null)
    kept=()
    for entry in "${entries[@]}"; do
      if [[ "$entry" == *$'\n'* || "$entry" == *$'\t'* ]]; then skipped_odd=$((skipped_odd + 1)); continue; fi
      if (( min_age > 0 )); then
        age="$(tc_tree_age_min "$entry")"
        (( age >= min_age )) || { filtered=$((filtered + 1)); continue; }
      fi
      tc_classify_entry "$entry" >/dev/null; cls="$TC_CLASS"
      case "$cls" in marker:*) bucket="marker" ;; schema:*) bucket="schema" ;; *) bucket="$cls" ;; esac
      KCLS["$entry"]="$bucket"; kept+=("$entry")
    done
    # One du over the kept set (-x: never cross into a mount inside an entry).
    ((${#kept[@]})) || continue
    while IFS=$'\t' read -r sz p; do
      [[ -n "$p" && -n "${KCLS[$p]:-}" ]] || continue
      bucket="${KCLS[$p]}"; tc_family "${p##*/}"; fam="$FAM"
      key="$bucket|$fam"; is_git=0; [[ -n "${HAS_GIT[$p]:-}" ]] && is_git=1
      F_N["$key"]=$(( ${F_N["$key"]:-0} + 1 )); F_KB["$key"]=$(( ${F_KB["$key"]:-0} + sz ))
      if (( is_git )); then F_GIT["$key"]=$(( ${F_GIT["$key"]:-0} + sz )); else F_NOGIT["$key"]=$(( ${F_NOGIT["$key"]:-0} + sz )); fi
      C_N["$bucket"]=$(( ${C_N["$bucket"]:-0} + 1 )); C_KB["$bucket"]=$(( ${C_KB["$bucket"]:-0} + sz ))
    done < <(printf '%s\0' "${kept[@]}" | xargs -0 du -skx 2>/dev/null)
  done

  echo "SOLEUR_TMP_PURGE_REPORT classes"
  if ((${#C_N[@]})); then
    for bucket in "${!C_N[@]}"; do
      printf '  class=%s n=%d kb=%d\n' "$bucket" "${C_N[$bucket]}" "${C_KB[$bucket]}"
    done | LC_ALL=C sort
  fi
  # kb-descending rows; key split on the FIRST `|` (a family may contain none).
  _rows() { # <class-filter: all|unattributable>
    for key in "${!F_N[@]}"; do
      bucket="${key%%|*}"; fam="${key#*|}"
      [[ "$1" == "all" || "$bucket" == "$1" ]] || continue
      printf '%d\tclass=%s family=%s n=%d kb=%d git_kb=%d nogit_kb=%d\n' "${F_KB[$key]}" "$bucket" "$fam" \
        "${F_N[$key]}" "${F_KB[$key]}" "${F_GIT[$key]:-0}" "${F_NOGIT[$key]:-0}"
    # awk (not head) truncates: `head` closing the pipe early gives sort a
    # SIGPIPE, and under pipefail+set -e that aborted the report mid-way
    # whenever there were more than TOP rows (measured on the operator host).
    done | LC_ALL=C sort -t$'\t' -k1,1nr -k2,2 | awk -F'\t' -v n="$REPORT_TOP" 'NR <= n { print "  " $2 }'
  }
  echo "SOLEUR_TMP_PURGE_REPORT families top=$REPORT_TOP by kb, all classes (git_kb = entries with a .git within 4 levels)"
  _rows all
  echo "SOLEUR_TMP_PURGE_REPORT unattributable-families top=$REPORT_TOP by kb (never moved by --apply; see the runbook)"
  _rows unattributable
  for base in $BASES; do
    p="$base/soleur-quarantine.$TC_UID"
    [[ -d "$p" && ! -L "$p" ]] || continue
    kb="$(du -skx "$p" 2>/dev/null | cut -f1)"
    rows="$(find "$p" -mindepth 2 -maxdepth 2 2>/dev/null | wc -l)"
    echo "SOLEUR_TMP_PURGE_REPORT quarantine $p entries=${rows//[[:space:]]/} kb=${kb:-0} (frees only at --drain; immediate: SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 --drain)"
  done
  (( filtered > 0 )) && echo "SOLEUR_TMP_PURGE_REPORT filtered $filtered entr$( (( filtered == 1 )) && echo y || echo ies) newer than ${OLDER_DAYS}d"
  (( skipped_odd > 0 )) && echo "SOLEUR_TMP_PURGE_REPORT skipped $skipped_odd entr$( (( skipped_odd == 1 )) && echo y || echo ies) with control characters in the name"
  echo "SOLEUR_TMP_PURGE_REPORT done (nothing was modified)"
  return 0
}

case "$MODE" in
  report)  run_report; exit 0 ;;
  restore) do_restore "$RESTORE_ARG"; exit 0 ;;
  drain)   drain_quarantine; exit 0 ;;
esac

run_scan

echo "SOLEUR_TMP_PURGE mode=$MODE bases=[$BASES]"
if ((${#CLASS_COUNT[@]})); then
  for cls in "${!CLASS_COUNT[@]}"; do
    printf '  %-28s n=%-7d kb=%d\n' "$cls" "${CLASS_COUNT[$cls]}" "${CLASS_BYTES[$cls]}"
  done | LC_ALL=C sort
fi
if ((${#OPERATOR_LIST[@]})); then
  echo "SOLEUR_TMP_PURGE operator-decision list (${#OPERATOR_LIST[@]} entries past retain floor):"
  printf '  %s\n' "${OPERATOR_LIST[@]:0:20}"
fi
[[ "$MODE" == "dry-run" ]] && echo "SOLEUR_TMP_PURGE dry-run — review the report, then re-run --apply. Ledger: $LEDGER"
exit 0
