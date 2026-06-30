#!/usr/bin/env bash

# roadmap-reconcile.sh — READ-ONLY roadmap↔GitHub reconcile module.
#
# Shared core behind `product-roadmap validate` (drift report) and `next`
# (advisory next-action). Part of feat-roadmap-program-layer's report-only
# design: this module NEVER writes to roadmap.md or any file. When drift is
# found, remediation routes through the existing cron-roadmap-review.ts (the
# sole writer, via reviewed fix PRs) — see ADR-033 / ADR-054.
#
# Verdict vocabulary mirrors cron-roadmap-review.ts's prompt:
#   STALE_STATUS    — roadmap count cell disagrees with the live milestone
#   MISSING_ISSUE   — a roadmap Phase row resolves to no GitHub milestone
#   EMPTY_MILESTONE — a milestone has 0 open AND 0 closed issues
#
# Public functions (sourced by plugins/soleur/test/roadmap-reconcile.test.sh):
#   extract_phase_counts          stdin: roadmap md  -> "N|open|closed" per Phase row
#   reconcile_counts ROADMAP MS   files: roadmap, milestones-json -> verdict lines
#   pick_next_action ISSUES       file: open-issues-json -> CODEABLE|OPERATOR|NONE line
#
# Milestone↔phase is NOT 1:1 (the Phase-N milestone also holds internal-tooling
# issues not on roadmap rows); reconcile keys strictly off the Current-State
# count cell, never feature-row tallies.

set -euo pipefail

ROADMAP_FILE="${ROADMAP_FILE:-knowledge-base/product/roadmap.md}"

# Labels that mark an issue as codeable (an agent can build it via /soleur:go).
# Everything else (recruitment, interviews, research, ops) is an operator action.
CODEABLE_LABELS='"domain/engineering","type/bug","type/feature","type/refactor","type/chore"'

# extract_phase_counts: read roadmap markdown on stdin, emit "N|open|closed"
# for each `| Phase N (...) |` row in the `## Current State` table that carries
# an "X open, Y closed" count. Rows without counts (prose, Beta users) are skipped.
extract_phase_counts() {
  awk '
    /^## Current State/ { inblock = 1; next }
    inblock && /^## / { inblock = 0 }
    inblock { print }
  ' \
  | grep -E '^\| Phase [0-9]+' \
  | while IFS= read -r line; do
      printf '%s\n' "$line" | grep -qE '[0-9]+ open, [0-9]+ closed' || continue
      num="$(printf '%s\n' "$line" | sed -E 's/^\| Phase ([0-9]+).*/\1/')"
      counts="$(printf '%s\n' "$line" | grep -oE '[0-9]+ open, [0-9]+ closed' | head -1)"
      open="$(printf '%s\n' "$counts" | sed -E 's/^([0-9]+) open.*/\1/')"
      closed="$(printf '%s\n' "$counts" | sed -E 's/^[0-9]+ open, ([0-9]+) closed/\1/')"
      printf '%s|%s|%s\n' "$num" "$open" "$closed"
    done
}

# reconcile_counts ROADMAP_FILE MILESTONES_JSON_FILE: emit verdict lines.
reconcile_counts() {
  local roadmap_file="$1" milestones_file="$2"
  local rows num ropen rclosed found mopen mclosed ms_json
  # Slurp milestones ONCE — the caller may pass a process-substitution FIFO,
  # which drains on first read; re-reading it per loop iteration would yield
  # empty and spuriously emit MISSING_ISSUE for every phase after the first.
  ms_json="$(cat "$milestones_file")"
  rows="$(extract_phase_counts < "$roadmap_file")"
  [[ -z "$rows" ]] && return 0
  while IFS='|' read -r num ropen rclosed; do
    [[ -z "${num:-}" ]] && continue
    found="$(jq -r --arg n "$num" '
      [ .[] | select(.title | test("^Phase " + $n + "[:( ]")) ] | first
      | if . == null then empty else "\(.open_issues)|\(.closed_issues)" end' \
      <<< "$ms_json")"
    if [[ -z "$found" ]]; then
      printf 'MISSING_ISSUE|phase %s|roadmap=%so/%sc|milestone=none\n' "$num" "$ropen" "$rclosed"
      continue
    fi
    mopen="${found%%|*}"
    mclosed="${found##*|}"
    if [[ "$mopen" -eq 0 && "$mclosed" -eq 0 ]]; then
      printf 'EMPTY_MILESTONE|phase %s|milestone=0o/0c\n' "$num"
    fi
    if [[ "$mopen" != "$ropen" || "$mclosed" != "$rclosed" ]]; then
      printf 'STALE_STATUS|phase %s|roadmap=%so/%sc|milestone=%so/%sc\n' \
        "$num" "$ropen" "$rclosed" "$mopen" "$mclosed"
    fi
  done <<< "$rows"
}

# pick_next_action OPEN_ISSUES_JSON_FILE: lowest-numbered open issue first
# (deterministic tie-break), classified CODEABLE vs OPERATOR by label; explicit
# NONE when the set is empty (never silent).
pick_next_action() {
  local issues_file="$1" first num title codeable
  first="$(jq -c 'sort_by(.number) | (first // empty)' "$issues_file")"
  if [[ -z "$first" || "$first" == "null" ]]; then
    echo "NONE|no actionable next item"
    return 0
  fi
  num="$(printf '%s' "$first" | jq -r '.number')"
  title="$(printf '%s' "$first" | jq -r '.title')"
  codeable="$(printf '%s' "$first" | jq -r \
    "if any(.labels[]?.name; IN($CODEABLE_LABELS)) then \"yes\" else \"no\" end")"
  if [[ "$codeable" == "yes" ]]; then
    printf 'CODEABLE|#%s|%s\n' "$num" "$title"
  else
    printf 'OPERATOR|#%s|%s\n' "$num" "$title"
  fi
}

# --- CLI entrypoint (only when executed directly, never when sourced) ---
_milestones_json() {
  gh api 'repos/{owner}/{repo}/milestones?state=all&per_page=100' \
    --jq '[ .[] | {title, open_issues, closed_issues} ]'
}

main() {
  local mode="${1:-validate}"
  case "$mode" in
    validate)
      local ms verdicts
      if ! ms="$(_milestones_json 2>/dev/null)"; then
        echo "roadmap-reconcile: ERROR — could not fetch GitHub milestones (gh auth?)." >&2
        return 2
      fi
      verdicts="$(reconcile_counts "$ROADMAP_FILE" <(printf '%s' "$ms"))"
      if [[ -z "$verdicts" ]]; then
        echo "roadmap-validate: clean — Current State counts match GitHub milestones."
        return 0
      fi
      echo "roadmap-validate: drift detected (read-only — no file was modified)"
      echo "$verdicts"
      echo ""
      echo "To fix: trigger the roadmap-review cron, which opens a reviewed PR:"
      echo "  /soleur:trigger-cron cron/roadmap-review.manual-trigger"
      return 1
      ;;
    *)
      echo "usage: roadmap-reconcile.sh [validate]" >&2
      return 64
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
