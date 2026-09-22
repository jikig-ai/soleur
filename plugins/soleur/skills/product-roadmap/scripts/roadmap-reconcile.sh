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

# jq helpers shared by every line this module prints about an issue. `clean`
# makes a title safe to print as the last field of a `|`-separated line: issue
# titles are attacker-authorable on a public repo, and a newline in one could
# otherwise forge a whole extra `CODEABLE|#N|…` line. `classify` is the single
# CODEABLE-vs-OPERATOR rule, used by both `next` and `next --frontier`.
ISSUE_JQ_DEFS="
  def clean: (.title // \"\") | gsub(\"[[:cntrl:]\\u2028\\u2029]\"; \" \") | gsub(\"[|]\"; \"/\");
  def classify: if any(.labels[]?.name; IN($OPERATOR_DOMAIN_LABELS)) then \"OPERATOR\"
                elif any(.labels[]?.name; IN($CODEABLE_LABELS)) then \"CODEABLE\"
                else \"OPERATOR\" end;
"

# pick_next_action OPEN_ISSUES_JSON_FILE: lowest-numbered open issue first
# (deterministic tie-break), classified CODEABLE vs OPERATOR by label; explicit
# NONE when the set is empty (never silent). One jq pass.
pick_next_action() {
  local line
  line="$(jq -r "$ISSUE_JQ_DEFS"'
    sort_by(.number) | (first // empty) | "\(classify)|#\(.number)|\(clean)"' "$1")" || return 2
  if [[ -z "$line" ]]; then
    echo "NONE|no actionable next item"
    return 0
  fi
  printf '%s\n' "$line"
}

# pick_phase MILESTONES_JSON_FILE: the lowest-numbered OPEN `Phase N` milestone
# that still has open issues, as "N|title"; empty when none. Read from live
# milestones, not the roadmap's Current State cells: a phase row may carry no
# frozen count, and skipping it picked the phase after it.
# Known edge: the REST open_issues count includes open pull requests, so a
# phase whose only open items are PRs is still picked (its frontier is empty).
pick_phase() {
  jq -r '
    [ .[] | select(.state == "open" and (.open_issues // 0) > 0)
          | select(.title | test("^Phase [0-9]+[:( ]"))
          | {n: (.title | capture("^Phase (?<n>[0-9]+)").n | tonumber), title} ]
    | sort_by(.n) | (first // empty) | "\(.n)|\(.title)"' "$1"
}

# filter_frontier OPEN_ISSUES_JSON_FILE: split a phase's open issues into the
# frontier (no open blocker, no assignee; sorted by number) and the held-back
# sets. Fails closed: a blocker counts as resolved only when its node reads
# CLOSED. An issue with an OPEN blocker is `blocked`; one whose blockers could
# not all be read (count above the nodes returned — a blocker in a repo the
# token cannot see, or a truncated page — or a node whose state is neither OPEN
# nor CLOSED) is `unverified`, held back but reported separately so "could not
# check" never reads as "waiting". Blockers in any repository count. Returns 2,
# naming the field, when number is not a number, blockedBy not an object or
# assignees not an array (a missing or null field would otherwise read as
# unblocked and unclaimed, and a string number could carry a forged line).
# ONE jq pass: callers may pass a FIFO.
filter_frontier() {
  local out
  out="$(jq -c '
    def nodes: (.blockedBy.nodes // []);
    def blocked: any(nodes[]; .state == "OPEN");
    def held: ((.blockedBy.totalCount // 0) > (nodes | length)) or any(nodes[]; .state != "CLOSED");
    def claimed: ((.assignees // []) | length) > 0;
    ([ .[] | ((if (.number | type) == "number" then empty else "number" end),
              (if (.blockedBy | type) == "object" then empty else "blockedBy" end),
              (if (.assignees | type) == "array" then empty else "assignees" end)) ]
     | unique) as $missing
    | if ($missing | length) > 0 then {missing: $missing}
      else { frontier:   ([ .[] | select((held | not) and (claimed | not)) ] | sort_by(.number)),
             blocked:    ([ .[] | select(blocked) ] | sort_by(.number)),
             unverified: ([ .[] | select(held and (blocked | not)) ] | sort_by(.number)),
             claimed:    ([ .[] | select((held | not) and claimed) ] | sort_by(.number)) }
      end' "$1")" || return 2
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

_usage() {
  echo "usage: roadmap-reconcile.sh [validate|next [--frontier]]" >&2
}

# Held-back counts in the founder's words (DC-6), from filter_frontier output.
_held_text() {
  jq -r '"\(.blocked | length) waiting on another issue"
    + (if (.unverified | length) > 0 then ", \(.unverified | length) whose blockers could not be read" else "" end)
    + ", \(.claimed | length) with someone on it"' <<< "$1"
}

main() {
  local mode="${1:-validate}"
  [[ $# -gt 0 ]] && shift
  case "$mode" in
    validate)
      if [[ $# -gt 0 ]]; then
        _usage
        return 64
      fi
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
      # Exit contract: 0 = answer printed; 2 = the data could not be trusted
      # (fetch failure, old gh, unparseable data) — never "nothing to do";
      # 64 = usage.
      local frontier_mode=0 pfx=roadmap-next
      if [[ $# -eq 1 && "$1" == "--frontier" ]]; then
        frontier_mode=1
        pfx=roadmap-frontier
      elif [[ $# -gt 0 ]]; then
        _usage
        return 64
      fi
      local errf ms sel phase mstitle issues filtered frontier held ready action num title
      errf="$(mktemp)" || return 2
      _RR_TMP="$errf"
      if ! ms="$(_milestones_json 2>"$errf")"; then
        echo "roadmap-next: ERROR — could not fetch GitHub milestones:" >&2
        cat "$errf" >&2
        rm -f "$errf"
        return 2
      fi
      if ! sel="$(pick_phase <(printf '%s' "$ms"))"; then
        echo "roadmap-next: ERROR — could not parse the milestone list." >&2
        rm -f "$errf"
        return 2
      fi
      if [[ -z "$sel" ]]; then
        rm -f "$errf"
        echo "$pfx: all phases complete — no open Phase milestone has open issues."
        return 0
      fi
      phase="${sel%%|*}"
      mstitle="${sel#*|}"
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
      filtered="$(filter_frontier <(printf '%s' "$issues"))" || return 2
      held="$(_held_text "$filtered")" || return 2
      if [[ "$frontier_mode" -eq 1 ]]; then
        # Line 1 is always the `roadmap-frontier:` summary; then one line per
        # ready issue, then one per held-back issue. Every issue line is
        # KIND|#N|title[|detail] with the title cleaned of `|` and control chars.
        ready="$(jq -r '.frontier | length' <<< "$filtered")" || return 2
        echo "roadmap-frontier: Phase $phase — $ready ready to start, $held"
        jq -r "$ISSUE_JQ_DEFS"'
          (.frontier[]   | "\(classify)|#\(.number)|\(clean)"),
          (.blocked[]    | "WAITING|#\(.number)|\(clean)|\([.blockedBy.nodes[] | select(.state == "OPEN") | "\(.repository.nameWithOwner // "")#\(.number)"] | join(","))"),
          (.unverified[] | "UNVERIFIED|#\(.number)|\(clean)"),
          (.claimed[]    | "CLAIMED|#\(.number)|\(clean)")' <<< "$filtered" || return 2
        return 0
      fi
      frontier="$(jq -c '.frontier' <<< "$filtered")" || return 2
      action="$(pick_next_action <(printf '%s' "$frontier"))" || return 2
      num="${action#*|}"
      num="${num%%|*}"
      title="${action#*|*|}"
      case "${action%%|*}" in
        CODEABLE|OPERATOR)
          # Defence in depth: filter_frontier already refuses a non-numeric
          # .number, so this is unreachable on data that passed it.
          if [[ ! "$num" =~ ^#[0-9]+$ ]]; then
            echo "roadmap-next: ERROR — unexpected issue line: $action" >&2
            return 2
          fi
          ;;
      esac
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
          echo "  See which issues are waiting, and on what: roadmap-reconcile.sh next --frontier"
          ;;
      esac
      return 0
      ;;
    *)
      _usage
      return 64
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Owns `next`'s stderr capture file if the script dies between mktemp and rm
  # (measured: bash runs this trap on SIGTERM too).
  _RR_TMP=""
  trap '[[ -z "${_RR_TMP:-}" ]] || rm -f "$_RR_TMP"' EXIT
  main "$@"
fi
