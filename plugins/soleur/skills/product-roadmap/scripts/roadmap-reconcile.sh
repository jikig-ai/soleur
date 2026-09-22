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
#   pick_phase MS                 file: milestones-json -> "N|title" of the live phase, or empty
#   filter_frontier ISSUES        file: open-issues-json -> {frontier,blocked,claimed}
#
# pick_phase depends on milestones being titled `Phase N: ...`. The frontier is a
# phase's open issues with no open blocker (GitHub-native "blocked by" edges) and
# no assignee; it needs `gh` >= 2.94.0, the first release exposing `blockedBy`.
#
# Milestone↔phase is NOT 1:1 (the Phase-N milestone also holds internal-tooling
# issues not on roadmap rows); reconcile keys strictly off the Current-State
# count cell, never feature-row tallies.

set -euo pipefail

ROADMAP_FILE="${ROADMAP_FILE:-knowledge-base/product/roadmap.md}"

# Labels that mark an issue as codeable (an agent can build it via /soleur:go).
# Deliberately narrow: anything else (recruitment, interviews, research, marketing,
# ops, chores) classifies as an operator action. Under-classifying to OPERATOR is
# the safe failure for an advisory tool — it only ever NAMES the item, never wrongly
# tells the founder to /soleur:go a non-codeable task.
CODEABLE_LABELS='"domain/engineering","type/bug","type/feature","type/refactor"'

# A non-engineering domain-leader label means the work is operator-driven (marketing,
# legal, ops, sales, finance, support, product) — it OVERRIDES a codeable type/* label.
# Caught by dogfooding: #2603 ("Publish a case study") is type/feature + domain/marketing
# and must classify OPERATOR, not CODEABLE — never tell the founder to /soleur:go it.
OPERATOR_DOMAIN_LABELS='"domain/marketing","domain/legal","domain/operations","domain/sales","domain/finance","domain/support","domain/product"'

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
    "if any(.labels[]?.name; IN($OPERATOR_DOMAIN_LABELS)) then \"no\"
     elif any(.labels[]?.name; IN($CODEABLE_LABELS)) then \"yes\"
     else \"no\" end")"
  if [[ "$codeable" == "yes" ]]; then
    printf 'CODEABLE|#%s|%s\n' "$num" "$title"
  else
    printf 'OPERATOR|#%s|%s\n' "$num" "$title"
  fi
}

# pick_phase MILESTONES_JSON_FILE: the lowest-numbered OPEN `Phase N` milestone
# that still has open issues, as "N|title"; empty when none. Read from live
# milestones, not the roadmap's Current State cells: a phase row may carry no
# frozen count, and skipping it picked the phase after it.
pick_phase() {
  jq -r '
    [ .[] | select(.state == "open" and (.open_issues // 0) > 0)
          | select(.title | test("^Phase [0-9]+[:( ]"))
          | {n: (.title | capture("^Phase (?<n>[0-9]+)").n | tonumber), title} ]
    | sort_by(.n) | (first // empty) | "\(.n)|\(.title)"' "$1"
}

# filter_frontier OPEN_ISSUES_JSON_FILE: split a phase's open issues into the
# frontier (no open blocker, no assignee; sorted by number) and the held-back
# counts. Fails closed: a blocker counts as resolved only when its node reads
# CLOSED, and an issue whose blocker count exceeds the nodes returned (a blocker
# the token cannot read, or a truncated page) is held back. Returns 2, naming the
# field, when the issue data lacks blockedBy or assignees (in jq a missing field
# would otherwise read as unblocked). ONE jq pass: callers may pass a FIFO.
filter_frontier() {
  local out
  out="$(jq -c '
    def held: ((.blockedBy.totalCount // 0) > ((.blockedBy.nodes // []) | length))
              or any((.blockedBy.nodes // [])[]; .state != "CLOSED");
    def claimed: ((.assignees // []) | length) > 0;
    ([ .[] | (["assignees", "blockedBy"] - keys)[] ] | unique) as $missing
    | if ($missing | length) > 0 then {missing: $missing}
      else { frontier: ([ .[] | select((held | not) and (claimed | not)) ] | sort_by(.number)),
             blocked: ([ .[] | select(held) ] | length),
             claimed: ([ .[] | select((held | not) and claimed) ] | length) }
      end' "$1")"
  if [[ "$(jq -r 'has("missing")' <<< "$out")" == "true" ]]; then
    echo "roadmap-reconcile: ERROR — issue data lacks field(s): $(jq -r '.missing | join(", ")' <<< "$out") (needs gh >= 2.94.0)." >&2
    return 2
  fi
  printf '%s\n' "$out"
}

# --- CLI entrypoint (only when executed directly, never when sourced) ---
_milestones_json() {
  gh api 'repos/{owner}/{repo}/milestones?state=all&per_page=100' \
    --jq '[ .[] | {title, state, open_issues, closed_issues} ]'
}

_next_usage() {
  echo "usage: roadmap-reconcile.sh [validate|next [--frontier]]" >&2
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
    next)
      # Advisory, read-only: the next action for the live phase, chosen from its
      # frontier (open, no open blocker, no assignee). `--frontier` lists it all.
      local frontier_mode=0
      shift
      if [[ $# -eq 1 && "$1" == "--frontier" ]]; then
        frontier_mode=1
      elif [[ $# -gt 0 ]]; then
        _next_usage
        return 64
      fi
      local ms sel phase mstitle errf issues filtered rc ready held action num title
      if ! ms="$(_milestones_json 2>/dev/null)"; then
        echo "roadmap-reconcile: ERROR — could not fetch GitHub milestones (gh auth?)." >&2
        return 2
      fi
      sel="$(pick_phase <(printf '%s' "$ms"))"
      if [[ -z "$sel" ]]; then
        echo "roadmap-next: all phases complete — no open Phase milestone has open issues."
        return 0
      fi
      phase="${sel%%|*}"
      mstitle="${sel#*|}"
      errf="$(mktemp)"
      _RR_TMP="$errf"
      if ! issues="$(gh issue list --milestone "$mstitle" --state open --limit 1000 \
          --json number,title,labels,assignees,blockedBy 2>"$errf")"; then
        if grep -q 'Unknown JSON field' "$errf"; then
          echo "roadmap-next: ERROR — reading blocking edges requires gh >= 2.94.0 (upgrade: https://github.com/cli/cli#installation)." >&2
        else
          echo "roadmap-next: ERROR — could not list open issues for $mstitle:" >&2
          cat "$errf" >&2
        fi
        rm -f "$errf"
        return 2
      fi
      rm -f "$errf"
      rc=0
      filtered="$(filter_frontier <(printf '%s' "$issues"))" || rc=$?
      [[ "$rc" -eq 0 ]] || return 2
      ready="$(jq -r '.frontier | length' <<< "$filtered")"
      held="$(jq -r '"\(.blocked) waiting on another issue, \(.claimed) with someone on it"' <<< "$filtered")"
      if [[ "$frontier_mode" -eq 1 ]]; then
        echo "roadmap-frontier: Phase $phase — $ready ready to start, $held"
        jq -r "
          .frontier[]
          | (if any(.labels[]?.name; IN($OPERATOR_DOMAIN_LABELS)) then \"OPERATOR\"
             elif any(.labels[]?.name; IN($CODEABLE_LABELS)) then \"CODEABLE\"
             else \"OPERATOR\" end) + \"|#\\(.number)|\\(.title)\"" <<< "$filtered"
        return 0
      fi
      action="$(pick_next_action <(jq -c '.frontier' <<< "$filtered"))"
      num="$(printf '%s' "$action" | cut -d'|' -f2)"
      title="$(printf '%s' "$action" | cut -d'|' -f3)"
      case "${action%%|*}" in
        CODEABLE)
          echo "roadmap-next: Phase $phase — next codeable item ($held):"
          echo "  $num $title"
          echo "  Build it: /soleur:go $num"
          ;;
        OPERATOR)
          echo "roadmap-next: Phase $phase — next item is operator-driven, not codeable ($held):"
          echo "  $num $title"
          echo "  This needs you (recruitment / interviews / ops), not an agent build."
          ;;
        *)
          echo "roadmap-next: Phase $phase ($mstitle) — nothing ready to start: $held."
          echo "  Unblock or unassign an issue, or see: roadmap-reconcile.sh next --frontier"
          ;;
      esac
      return 0
      ;;
    *)
      _next_usage
      return 64
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Owns `next`'s stderr capture file if the script dies between mktemp and rm.
  _RR_TMP=""
  trap '[[ -z "${_RR_TMP:-}" ]] || rm -f "$_RR_TMP"' EXIT
  main "$@"
fi
