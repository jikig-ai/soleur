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

BASES="${SOLEUR_PURGE_BASES:-/tmp /var/tmp}"
[[ -n "${BASES//[[:space:]]/}" ]] || { echo "SOLEUR_TMP_PURGE FATAL: base list empty; refusing (fail-closed)" >&2; exit 1; }

LEDGER="${SOLEUR_PURGE_LEDGER:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/tmp-purge-ledger.log}"
LOCKFILE="${SOLEUR_PURGE_LOCKFILE:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/tmp-guard.lock}"
TTL_SCRATCH="${SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN:-10080}"   # 7d
TTL_WT="${SOLEUR_PURGE_QUAR_WT_TTL_MIN:-43200}"             # 30d
DRY_RUN="${SOLEUR_PURGE_DRY_RUN:-0}"

MODE="dry-run"; RESTORE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --restore) MODE="restore"; RESTORE_ARG="${2:-all}"; shift ;;
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
ledger_append() { # action class original dest
  local line
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\t'"$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"
  if ! printf '%s\n' "$line" >> "$LEDGER" 2>/dev/null; then
    echo "LEDGER-DROP: cannot append $LEDGER — action NOT recorded: $line" >&2
    echo "LEDGER-DROP: $line"
    return 0   # never abort a run on ledger failure; the drop IS the alarm
  fi
}

# --- drain -----------------------------------------------------------------------
drain_quarantine() {
  local base qroot cls ttl newest now_min f
  for base in $BASES; do
    qroot="$base/soleur-quarantine.$TC_UID"
    [[ -d "$qroot" ]] || continue
    for cls in "$qroot"/*/; do
      [[ -d "$cls" ]] || continue
      case "$(basename -- "$cls")" in worktrees) ttl="$TTL_WT" ;; *) ttl="$TTL_SCRATCH" ;; esac
      for f in "$cls"/*; do
        [[ -e "$f" ]] || continue
        now_min="$(tc_tree_age_min "$f")"
        if (( now_min >= ttl )); then
          if [[ "$MODE" == "drain" && "$DRY_RUN" != "1" ]]; then
            rm -rf -- "$f" && ledger_append "drain" "$(basename -- "$cls")" "$f" "-"
          else
            echo "  drain-pending $(basename -- "$cls")/$(basename -- "$f") age=${now_min}m"
          fi
        fi
      done
    done
  done
}

# --- restore ---------------------------------------------------------------------
do_restore() {
  local target="$1" line orig quar
  [[ -f "$LEDGER" ]] || { echo "SOLEUR_TMP_PURGE restore: no ledger at $LEDGER"; exit 1; }
  while IFS=$'\t' read -r ts action cls orig quar; do
    [[ "$action" == "move" && -n "${quar:-}" && -e "$quar" ]] || continue
    if [[ "$target" == "all" || "$(basename -- "$quar")" == "$target" || "$quar" == "$target" ]]; then
      if [[ -e "$orig" ]]; then
        echo "  restore-skip $(basename -- "$quar") — $orig exists"
        continue
      fi
      mv -- "$quar" "$orig" && { ledger_append "restore" "$cls" "$quar" "$orig"; echo "  restored $(basename -- "$orig")"; }
    fi
  done < "$LEDGER"
}

# --- enumeration + classification -------------------------------------------------

declare -A CLASS_COUNT CLASS_BYTES _CLASS_OF=()
REPORT_ROWS=()
OPERATOR_LIST=()

bump() { # class bytes
  CLASS_COUNT["$1"]=$(( ${CLASS_COUNT["$1"]:-0} + 1 ))
  CLASS_BYTES["$1"]=$(( ${CLASS_BYTES["$1"]:-0} + $2 ))
}

# decide <path> <class> — apply-mode disposition. Prints a row for the report.
decide_apply() {
  local p="$1" cls="$2" dest age
  case "$cls" in
    marker:*|schema:*)
      local pid="${cls##*:}"
      if tc_entry_is_live "$p" "$pid"; then echo "  retain $p (live)"; return 0; fi
      age="$(tc_tree_age_min "$p")"; (( age >= TC_AGE_FLOOR_MIN )) || { echo "  retain $p (age ${age}m<${TC_AGE_FLOOR_MIN}m)"; return 0; }
      dest="$(tc_quarantine_move "$p" "$(dirname "$p")" "scratch")" \
        && { ledger_append "move" "scratch" "$p" "$dest"; echo "  QUARANTINE $p -> $dest"; } \
        || echo "  RETAIN $p (move refused)"
      ;;
    empty)
      if tc_entry_is_live "$p" ""; then echo "  retain $p (live)"; return 0; fi
      rmdir -- "$p" 2>/dev/null && { ledger_append "rmdir" "empty" "$p" "-"; echo "  RMDIR $p"; } || echo "  retain $p (rmdir refused)"
      ;;
    prefix:*|file:*)
      if [[ -d "$p" ]] && tc_entry_is_live "$p" ""; then echo "  retain $p (live)"; return 0; fi
      age="$(tc_tree_age_min "$p")"; (( age >= TC_AGE_FLOOR_MIN )) || { echo "  retain $p (young)"; return 0; }
      dest="$(tc_quarantine_move "$p" "$(dirname "$p")" "prefix")" \
        && { ledger_append "move" "prefix" "$p" "$dest"; echo "  QUARANTINE $p -> $dest"; } \
        || echo "  RETAIN $p (move refused)"
      ;;
    worktree:unregistered)
      age="$(tc_tree_age_min "$p")"; (( age >= TC_WT_FLOOR_MIN )) || { echo "  retain $p (young)"; return 0; }
      if tc_entry_is_live "$p" ""; then echo "  retain $p (live)"; return 0; fi
      dest="$(tc_quarantine_move "$p" "$(dirname "$p")" "worktrees")" \
        && { ledger_append "move" "worktrees" "$p" "$dest"; echo "  QUARANTINE $p -> $dest"; } \
        || echo "  RETAIN $p (move refused)"
      ;;
    worktree:registered)
      age="$(tc_tree_age_min "$p")"; (( age >= TC_WT_FLOOR_MIN )) || { echo "  retain $p (young)"; return 0; }
      if tc_worktree_safe_to_remove "$p"; then
        local main; main="$(tc_git_main_dir "$p")" || { echo "  retain $p (gitdir lost)"; return 0; }
        git --git-dir="$main" worktree remove "$p" 2>/dev/null \
          && { ledger_append "worktree-remove" "worktrees" "$p" "-"; echo "  WT-REMOVE $p"; } \
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
  local base entry cls
  local -a entries=() sized_paths=()
  for base in $BASES; do
    [[ -d "$base" ]] || { echo "SOLEUR_TMP_PURGE: base $base missing — skipping"; continue; }
    mapfile -t entries < <(find "$base" -mindepth 1 -maxdepth 1 \
      ! -name 'soleur-quarantine.*' 2>/dev/null | LC_ALL=C sort)
    echo "SOLEUR_TMP_PURGE scanning $base (${#entries[@]} entries)…" >&2
    # Bulk liveness for apply mode: one /proc walk feeds every conjunct.
    if [[ "$MODE" == "apply" ]]; then tc_build_inuse_map "$base" || true; fi
    for entry in "${entries[@]}"; do
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
