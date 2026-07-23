#!/usr/bin/env bash
# tmpfs-guard.sh — keeps the shared /tmp tmpfs from filling.
#
# Two reapers, both scoped to files owned by the current user (no sudo):
#
#   1. reap_output_files    — oversized Claude Code task .output files.
#   2. reap_scratch_entries — stale, large, own-uid scratch entries at the top
#                             level of /tmp (added #6789).
#
# WHY (2) EXISTS. /tmp is a 4 GiB tmpfs — Layer 3 of the 2026-03-28 tmpfs guard,
# deliberately capped so a runaway file cannot consume all system memory. The
# cap is correct; what was missing was a reaper for the class of artifact now
# filling it. Measured 2026-07-22: /tmp at 86% with THREE abandoned scratch
# trees holding 3.1 GiB (88% of occupancy), while 4294 small entries held only
# 160 MB (4.5%). Because tmpfs is RAM-backed, that 3.5 GiB was memory withheld
# from a machine with ~6 GiB available and swap exhausted — precisely the
# condition under which concurrent test runs hit the timeout-flake class that
# reads as a false regression (#6726, #4096, #3817).
#
# This script had run every five minutes throughout, warning and cleaning
# nothing outside its .output scope. A guard that only warns is not a guard.
#
# SAFETY (plan R3). Reaping on a SINGLE dimension deletes live work: age alone
# removes a long-running session's scratch dir, size alone removes a small but
# active one. Every candidate must clear ALL of:
#   - ownership : owned by the invoking uid
#   - age       : NOTHING in the tree modified within the age floor
#   - size      : at least the size floor
#   - liveness  : no process cwd inside it, no open file handle
#   - not protected: /tmp/claude-<uid> belongs to worktree-manager.sh's
#     cleanup_claude_tmp, and the session-state root belongs to session-state.sh
#
# Designed to run as a user cron job every 5 minutes.
#
# Test seams (default to the real system; overridden only by tmpfs-guard.test.sh):
#   TMPFS_GUARD_TMP, TMPFS_GUARD_PROC, TMPFS_GUARD_DRY_RUN,
#   TMPFS_GUARD_SCRATCH_MIN_MB, TMPFS_GUARD_SCRATCH_AGE_MIN

set -euo pipefail

THRESHOLD_MB="${TMPFS_GUARD_THRESHOLD_MB:-200}"   # delete .output files larger than this
USAGE_WARN_PCT="${TMPFS_GUARD_USAGE_WARN_PCT:-70}"
TMP_ROOT="${TMPFS_GUARD_TMP:-/tmp}"
PROC_ROOT="${TMPFS_GUARD_PROC:-/proc}"
DRY_RUN="${TMPFS_GUARD_DRY_RUN:-0}"

# Scratch-reaper floors. 24h and 100MB are deliberately conservative: they
# clear the measured 3.1 GiB of abandoned trees without touching anything a
# session plausibly still wants.
SCRATCH_MIN_MB="${TMPFS_GUARD_SCRATCH_MIN_MB:-100}"
SCRATCH_AGE_MIN="${TMPFS_GUARD_SCRATCH_AGE_MIN:-1440}"

CLAUDE_TMP="$TMP_ROOT/claude-$(id -u)"

tmpfs_usage_pct() {
  local p
  p=$(df "$TMP_ROOT" --output=pcent 2>/dev/null | tail -1 | tr -d ' %') || p=""
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  printf '%s\n' "$p"
}

# Populate _INUSE_TOP with the top-level $TMP_ROOT entry of every live process
# that has EITHER its cwd OR an open file descriptor under $TMP_ROOT, in a
# SINGLE /proc pass. A cwd or fd target of /tmp/tmp.ABC/repo/x marks
# /tmp/tmp.ABC in use. Built once per run rather than rescanned per candidate —
# the naive per-candidate scan is O(candidates × pids) and on a full /tmp
# (6000+ stale entries, 600+ pids) that is millions of readlinks, far too slow
# for a 5-minute cron.
#
# BOTH cwd AND fds are load-bearing (the SAFETY header's "no open file handle"
# claim): a process can hold an OPEN FD to a file inside a scratch tree — an
# mmap'd dataset, a held-open DB, a downloaded artifact being served — while
# its cwd is elsewhere and nothing in the tree has a recent mtime. cwd alone
# would miss it and `rm` the live data out from under the reader. `fuser` below
# covers only top-level *file* candidates; this fd scan is what covers the
# common *directory* case (a scratch tree with a live open handle inside).
declare -A _INUSE_TOP
# Map an absolute path to its top-level $TMP_ROOT entry and mark it in use.
_mark_inuse() {
  local target="$1" rest top
  case "$target" in
    "$TMP_ROOT"/*)
      rest="${target#"$TMP_ROOT"/}"
      top="${rest%%/*}"
      [[ -n "$top" ]] && _INUSE_TOP["$TMP_ROOT/$top"]=1
      ;;
  esac
}
_build_inuse_top() {
  _INUSE_TOP=()
  local p fd target
  for p in "$PROC_ROOT"/[0-9]*; do
    if [[ -e "$p/cwd" ]]; then
      target=$(readlink "$p/cwd" 2>/dev/null) && _mark_inuse "$target"
    fi
    # Open file descriptors (skips a process whose /proc/<pid>/fd we cannot read
    # — a foreign-owned process; those never hold OUR uid-scoped candidates).
    [[ -d "$p/fd" ]] || continue
    for fd in "$p"/fd/*; do
      [[ -e "$fd" || -L "$fd" ]] || continue
      target=$(readlink "$fd" 2>/dev/null) && _mark_inuse "$target"
    done
  done
}

# --- Reaper 1: oversized .output files (pre-existing behaviour) -------------
reap_output_files() {
  local usage_pct="$1"
  # Scoped to the Claude temp dir; absent on a machine with no active session.
  [[ -d "$CLAUDE_TMP" ]] || return 0

  local cleaned=0 cleaned_mb=0 file size_bytes size_mb
  while IFS= read -r file; do
    size_bytes=$(stat --format=%s "$file" 2>/dev/null) || continue
    size_mb=$(( size_bytes / 1048576 ))
    # Skip files still being written by an active process.
    if fuser "$file" >/dev/null 2>&1; then
      if [[ "$usage_pct" -lt 90 ]]; then
        continue
      fi
      # At 90%+ usage, killing it is justified — the system is about to lock up.
    fi
    rm -f "$file"
    cleaned=$(( cleaned + 1 ))
    cleaned_mb=$(( cleaned_mb + size_mb ))
  done < <(find "$CLAUDE_TMP" -name "*.output" -size "+${THRESHOLD_MB}M" -type f 2>/dev/null)

  if [[ "$cleaned" -gt 0 ]]; then
    notify-send -u critical -i dialog-warning "tmpfs-guard" \
      "Removed $cleaned runaway .output file(s) (${cleaned_mb} MB). /tmp was at ${usage_pct}%." 2>/dev/null || true
    logger -t tmpfs-guard "Removed $cleaned .output files (${cleaned_mb} MB). /tmp at ${usage_pct}%."
  fi
  printf '%s\n' "$cleaned"
}

# --- Reaper 2: stale, large, own-uid scratch entries (#6789) ---------------
reap_scratch_entries() {
  [[ -d "$TMP_ROOT" ]] || return 0
  local uid; uid="$(id -u)"
  local reaped=0 reaped_mb=0
  local e base fresh size_mb

  _build_inuse_top

  # SIZE FIRST, via a SINGLE batched `du`. Size is the most selective gate — a
  # measured 3 of thousands of entries qualify — but it is also the only gate
  # that must walk a tree. Running it per-candidate (a fresh `du`/recursive
  # `find` for each of 6000+ stale entries) does not finish inside a 5-minute
  # cron window. One `du --files0-from` over the whole stale set walks every
  # tree exactly once (~2s on the measured /tmp) and hands back a tiny survivor
  # list, on which the expensive recursive-age + liveness gates then run.
  #
  # `--files0-from` (not an argv list) so a large candidate set cannot hit the
  # kernel's per-arg E2BIG ceiling (the ARGV lesson from work/SKILL.md). The
  # top-level `-mmin` prefilter is cheap and only ever more conservative; the
  # recursive age check below is the real R6 safety gate.
  local cand_file; cand_file="$(mktemp -t tmpfs-guard-cand.XXXXXX)" || return 0
  local sized_file; sized_file="$(mktemp -t tmpfs-guard-sized.XXXXXX)" || { rm -f "$cand_file"; return 0; }
  # shellcheck disable=SC2064
  trap "rm -f '$cand_file' '$sized_file'" RETURN

  find "$TMP_ROOT" -mindepth 1 -maxdepth 1 -user "$uid" -mmin "+${SCRATCH_AGE_MIN}" -print0 \
    2>/dev/null > "$cand_file" || true
  # `du -sm` emits ONE "<size>\t<path>" summary line per candidate. `-s` is
  # load-bearing — without it du descends and prints every subdirectory, which
  # would enqueue non-top-level paths for reaping. `du` exits non-zero on a
  # vanished entry (a concurrent reap elsewhere) — tolerate it, the survivors it
  # did size are still valid. Keep only rows at or above the floor; the size↔path
  # tab is preserved verbatim for the read loop below.
  du -sm --files0-from="$cand_file" 2>/dev/null \
    | awk -F'\t' -v floor="$SCRATCH_MIN_MB" '$1 ~ /^[0-9]+$/ && $1 >= floor' \
    > "$sized_file" || true

  while IFS=$'\t' read -r size_mb e; do
    [[ -n "$e" ]] || continue
    [[ "$size_mb" =~ ^[0-9]+$ ]] || continue
    base="${e##*/}"

    # Protected paths. These have other owners or are deliberately reused; reaping
    # them here would race a different cleanup path or destroy a live cache.
    # `node-compile-cache` is a reusable Node V8 cache, not a leak — spared here
    # for the same reason worktree-manager.sh's cleanup_stale_sandbox_tmp spares
    # it (that function owns the signature-gated sandbox-copy class; this reaper
    # additionally covers the dotted `tmp.XXXXXX` mkdtemp trees its 15+-char
    # regex excludes, so the two cooperate — see the delete-idiom note below).
    case "$base" in
      claude-*|soleur-session-state*|node-compile-cache|.X11-unix|.ICE-unix|.font-unix|.XIM-unix|.Test-unix|systemd-*|snap*)
        continue ;;
    esac

    # Never follow a symlink out of the scratch root.
    [[ -L "$e" ]] && continue

    # LIVENESS (O(1) set lookup for dirs — no /proc access here; fuser for files).
    [[ -n "${_INUSE_TOP[$e]:-}" ]] && continue
    if [[ ! -d "$e" ]]; then
      fuser "$e" >/dev/null 2>&1 && continue
    fi

    # AGE (recursive) — the R6 safety gate. A directory's own mtime does NOT
    # change when a nested file is written, so a top-level test alone would
    # delete a tree that is actively in use. `-print -quit` stops at the first
    # fresh entry. Runs only on the size-survivors, so its cost is bounded.
    fresh=$(find "$e" -mmin "-${SCRATCH_AGE_MIN}" -print -quit 2>/dev/null) || fresh=""
    [[ -n "$fresh" ]] && continue

    if [[ "$DRY_RUN" == "1" ]]; then
      echo "tmpfs-guard: would reap $e (${size_mb} MB)"
      continue
    fi
    echo "tmpfs-guard: reaping $e (${size_mb} MB)"
    # `find … -delete`, NEVER `rm -rf` — a size-survivor can be an abandoned repo
    # clone (a `.git`-bearing checkout), and the constitution's
    # guardrails:block-recursive-delete rule forbids `rm -rf` on such a target.
    # worktree-manager.sh's cleanup_stale_sandbox_tmp uses the same find-delete
    # idiom for the same reason; the cron context here means the PreToolUse hook
    # would not fire, so honouring the idiom (not relying on the hook) is what
    # keeps this inside the guardrail. `-delete` implies depth-first and never
    # follows symlinks. Tolerate partial failure (a vanished/permission entry).
    find "$e" -delete 2>/dev/null || true
    reaped=$(( reaped + 1 ))
    reaped_mb=$(( reaped_mb + size_mb ))
  done < "$sized_file"

  if [[ "$reaped" -gt 0 ]]; then
    notify-send -u normal -i dialog-information "tmpfs-guard" \
      "Reclaimed ${reaped_mb} MB from $reaped stale scratch entr(ies) in $TMP_ROOT." 2>/dev/null || true
    logger -t tmpfs-guard "Reaped $reaped stale scratch entries (${reaped_mb} MB) from $TMP_ROOT."
  fi
  printf '%s\n' "$reaped"
}

main() {
  local usage_pct cleaned reaped
  usage_pct="$(tmpfs_usage_pct)"

  # NOTE: the .output reaper self-guards on CLAUDE_TMP. This used to be a
  # top-of-script `exit 0`, which would now silently disable the scratch reaper
  # on any machine without an active Claude session — the reaper would never
  # run precisely where abandoned scratch accumulates unattended.
  cleaned="$(reap_output_files "$usage_pct")"
  reaped="$(reap_scratch_entries)"

  # Warn on high usage when neither reaper found anything — something else is
  # filling /tmp and no automated path will reclaim it.
  if [[ "$usage_pct" -ge "$USAGE_WARN_PCT" ]] \
     && [[ "${cleaned:-0}" -eq 0 ]] && [[ "${reaped:-0}" -eq 0 ]]; then
    notify-send -u normal -i dialog-information "tmpfs-guard" \
      "$TMP_ROOT is at ${usage_pct}% usage. Investigate with: du -sh $TMP_ROOT/*" 2>/dev/null || true
    logger -t tmpfs-guard "$TMP_ROOT at ${usage_pct}% — nothing reapable found."
  fi
}

# CLI vs. sourced (test harness). Mirrors the session-state.sh idiom.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
