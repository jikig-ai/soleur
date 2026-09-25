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

BASES="${SOLEUR_PURGE_BASES-/tmp /var/tmp}"
[[ -n "${BASES//[[:space:]]/}" ]] || { echo "SOLEUR_TMP_PURGE FATAL: base list empty; refusing (fail-closed). An empty SOLEUR_PURGE_BASES is honored, not defaulted — unset it to use /tmp /var/tmp." >&2; exit 1; }

LOCKFILE="${SOLEUR_PURGE_LOCKFILE:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/tmp-guard.lock}"
TTL_SCRATCH="${SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN:-10080}"   # 7d
TTL_WT="${SOLEUR_PURGE_QUAR_WT_TTL_MIN:-43200}"             # 30d
DRY_RUN="${SOLEUR_PURGE_DRY_RUN:-0}"

MODE="dry-run"; RESTORE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --restore)
      MODE="restore"
      # Only a non-flag argument is a restore target — `--restore --apply`
      # must not swallow the next flag, and bare `--restore` must not shift
      # past the end (set -e would kill the script silently).
      if [[ -n "${2:-}" && "$2" != -* ]]; then RESTORE_ARG="$2"; shift; else RESTORE_ARG="all"; fi ;;
    --drain)   MODE="drain" ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "usage: soleur-tmp-purge.sh [--dry-run|--apply|--restore [name|all]|--drain]" >&2; exit 1 ;;
  esac
  shift
done
[[ "$DRY_RUN" == "1" && "$MODE" == "apply" ]] && MODE="dry-run"

# --- serialization -------------------------------------------------------------
mkdir -p -- "$(dirname "$LOCKFILE")" 2>/dev/null || true
exec 9>>"$LOCKFILE"
if ! flock -n 9; then
  echo "SOLEUR_TMP_PURGE SKIP: another purge/sweep/guard holds $LOCKFILE"
  exit 2
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

declare -A CLASS_COUNT CLASS_BYTES _CLASS_OF=()
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

case "$MODE" in
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
