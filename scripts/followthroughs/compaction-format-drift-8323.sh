#!/usr/bin/env bash
# Transcript-format drift canary for #8323 (FR7).
#
# WHAT THIS CAN AND CANNOT SEE -- stated first, because the plan's Risks table
# overclaimed it and the correction is load-bearing.
#
# CAN see: that Claude Code still writes `"subtype": "compact_boundary"` records
# into `~/.claude/projects/**/*.jsonl`, in a spelling the shipped hook's grep
# matches. That is the assumption `compaction-state.sh` makes when it reports
# `prior_boundaries=N`, and it is the only assumption a file-reading script can
# check. Synthesized fixtures structurally cannot: they pin the shape Soleur
# WROTE, not the shape the CLI EMITS, so they stay green through an upstream
# rename forever.
#
# CANNOT see: whether the feature still works. Since the Phase 0 measurement,
# `count_auto` and `trigger` come from a per-session TMPDIR ledger, not from the
# transcript -- the transcript cannot answer at the moment `SessionStart:compact`
# fires. A rename therefore degrades the `prior_boundaries` marker and nothing
# else. What this canary really reports is that the measurements recorded in
# `compaction-state.sh`'s header have gone stale and want re-taking. It is a
# staleness signal, not a liveness one; do not read a PASS as "the hook fires".
#
# WHY IT IS A SCHEDULE AND NOT A SUITE CASE: it reads the operator's real
# transcripts. On a clean CI box there are none, so a suite case would red for
# everyone who is not this operator.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (>= MIN_BOUNDARIES boundary records across the scanned transcripts)
#   1 = FAIL       (transcripts exist and were readable, but ZERO boundaries -- drift)
#   2 = TRANSIENT  (no projects dir, no transcripts, or nothing readable -- cannot measure)
#
# No credentials: this reads local files only and never leaves the machine, so
# there is no xtrace-credential refusal to make.

set -uo pipefail

PROJECTS_DIR="${SOLEUR_COMPACTION_PROJECTS_DIR:-$HOME/.claude/projects}"
SCAN_N="${SOLEUR_COMPACTION_DRIFT_SCAN_N:-40}"
MIN_BOUNDARIES="${SOLEUR_COMPACTION_DRIFT_MIN:-1}"

case "$SCAN_N" in ''|*[!0-9]*) SCAN_N=40 ;; esac
case "$MIN_BOUNDARIES" in ''|*[!0-9]*) MIN_BOUNDARIES=1 ;; esac

if [[ ! -d "$PROJECTS_DIR" ]]; then
  printf 'TRANSIENT: no transcript directory at %s -- cannot measure\n' "$PROJECTS_DIR" >&2
  exit 2
fi

# Newest first. A boundary is a comparatively rare event (measured locally: 11
# across 22 recent sessions), so a small N can legitimately contain none --
# which is why "no boundaries at all" is only a FAIL once enough transcripts
# were actually read, and why COMPACTED_FILES is reported alongside.
mapfile -t FILES < <(find "$PROJECTS_DIR" -type f -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null \
  | sort -rn | head -n "$SCAN_N" | cut -f2-)

if (( ${#FILES[@]} == 0 )); then
  printf 'TRANSIENT: no *.jsonl transcripts under %s -- cannot measure\n' "$PROJECTS_DIR" >&2
  exit 2
fi

SCANNED=0
UNREADABLE=0
BOUNDARIES=0
COMPACTED_FILES=0

for f in "${FILES[@]}"; do
  if [[ ! -r "$f" ]]; then
    UNREADABLE=$((UNREADABLE + 1))
    continue
  fi
  SCANNED=$((SCANNED + 1))
  # Same expression the shipped hook greps, spacing tolerance included. If this
  # ever diverges from compaction-state.sh the canary stops guarding the thing
  # it names -- keep the two in step.
  n="$(grep -cE '"subtype"[[:space:]]*:[[:space:]]*"compact_boundary"' "$f" 2>/dev/null || true)"
  n="${n:-0}"
  BOUNDARIES=$((BOUNDARIES + n))
  (( n > 0 )) && COMPACTED_FILES=$((COMPACTED_FILES + 1))
done

if (( SCANNED == 0 )); then
  printf 'TRANSIENT: %d transcripts found, none readable -- cannot measure\n' "${#FILES[@]}" >&2
  exit 2
fi

printf 'scanned=%d unreadable=%d boundaries=%d compacted_transcripts=%d min=%d dir=%s\n' \
  "$SCANNED" "$UNREADABLE" "$BOUNDARIES" "$COMPACTED_FILES" "$MIN_BOUNDARIES" "$PROJECTS_DIR"

if (( BOUNDARIES < MIN_BOUNDARIES )); then
  printf 'FAIL: %d compact_boundary record(s) across %d transcripts, expected at least %d.\n' \
    "$BOUNDARIES" "$SCANNED" "$MIN_BOUNDARIES" >&2
  printf 'Either the operator genuinely had no compactions in this window, or Claude Code\n' >&2
  printf 'renamed the record and compaction-state.sh prior_boundaries is now silently 0.\n' >&2
  printf 'Check by hand: grep -o %s <a recent transcript> | head\n' "'\"subtype\":\"[a-z_]*\"'" >&2
  exit 1
fi

printf 'PASS: transcript format still recognized (%d boundaries across %d transcripts).\n' \
  "$BOUNDARIES" "$SCANNED"
exit 0
