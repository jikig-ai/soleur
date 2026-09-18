#!/usr/bin/env bash
# Report workflow transitions that the declared edge set does not permit.
#
# WHY THIS IS OFFLINE AND NOT A HOOK (#8302, ADR-225).
# The plan originally specified a record-mode PreToolUse hook on the Skill
# matcher. Plan review cut it on two independent grounds:
#
#   1. Its output would dead-end. A record-mode event carries no corpus rule-id
#      prefix, so scripts/rule-metrics-aggregate.sh files it under
#      summary.non_corpus_counts -- a bare integer that nothing reads -- and
#      compound's Deviation Analyst ingests only
#      event_type in {deny, bypass} or kind == "hook_self_fault",
#      none of which a record-mode gate can emit. It would have recorded forever
#      into a counter no surface displays.
#   2. The data already exists. .claude/hooks/skill-invocation-logger.sh appends
#      {ts, skill, session_id} on every Skill call. Only the
#      classification was missing, and classification does not need a hook --
#      which also means nothing new can wedge a session, and ADR-070's two-tier
#      rule (deny-by-default only on re-fetching layers) is not engaged at all.
#
# PROPERTY: for every session in the invocation log, each consecutive
# (previous skill -> next skill) pair absent from the declared edge set is
# reported exactly once, attributed to the session it occurred in.
#
# Usage:
#   scripts/classify-workflow-transitions.sh              # one row per violation
#   scripts/classify-workflow-transitions.sh --summary    # counts only
#
# CLASSIFY_REPO_ROOT is an EXCLUSIVE override: when set, only that root is read
# and sibling-worktree enumeration is skipped. Tests depend on that narrowing;
# never widen past it.
set -euo pipefail

SUMMARY=0
for arg in "$@"; do
  case "$arg" in
    --summary) SUMMARY=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/incidents-roots.sh
source "$SCRIPT_DIR/lib/incidents-roots.sh"

REPO_ROOT="${CLASSIFY_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
VIEW="$REPO_ROOT/.claude/workflow-transitions.json"

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }

# FAIL CLOSED on a missing edge set. Classifying against an empty set would
# report EVERY transition as undeclared -- a confident wrong answer, which is
# worse than a missing one.
if [[ ! -r "$VIEW" ]]; then
  echo "FATAL: declared transition view not readable at $VIEW" >&2
  exit 2
fi

# The invocation log has the SAME per-root fragmentation as the incident log --
# both resolve through the hook's own dirname -- so it gets the same treatment:
# enumerate sibling worktrees, then dedupe by inode so a root reachable by two
# different path strings is not walked twice.
ROOTS=("$REPO_ROOT/.claude")
if [[ -z "${CLASSIFY_REPO_ROOT:-}" ]]; then
  while IFS= read -r _wt; do
    [[ -n "$_wt" ]] || continue
    ROOTS+=("$_wt/.claude")
  done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | incidents_roots_from_porcelain)
  _dd=()
  while IFS= read -r _d; do
    [[ -n "$_d" ]] || continue
    _dd+=("$_d")
  done < <(incidents_dedupe_existing_dirs "${ROOTS[@]}")
  [[ ${#_dd[@]} -gt 0 ]] && ROOTS=("${_dd[@]}")
fi

MERGED=$(mktemp -t classifyinv.XXXXXXXX)
trap 'rm -f -- "$MERGED"' EXIT INT TERM

found=0
for d in "${ROOTS[@]}"; do
  if [[ -s "$d/.skill-invocations.jsonl" ]]; then
    cat "$d/.skill-invocations.jsonl" >> "$MERGED" || true
    found=1
  fi
done

# Absence must be LOUD. A missing log and a log of genuinely zero violations
# both produce an empty report, and the silent one reads as an all-clear --
# the same null-reading trap the aggregator guards with
# SOLEUR_RULE_METRICS_NO_INCIDENTS.
if [[ "$found" -eq 0 ]]; then
  echo "SOLEUR_WORKFLOW_TRANSITIONS_NO_INVOCATIONS roots=${ROOTS[*]} reason=absent — this is a NULL reading, not an all-clear" >&2
  [[ "$SUMMARY" -eq 1 ]] && echo "undeclared=0 sessions=0 pairs=0 unclassified=0 (NULL READING)"
  exit 0
fi

# Classification, in one jq pass:
#   - strip the `soleur:` namespace so skills match the edge set's node names
#   - group by session_id, because without it the "previous skill" is whatever
#     the last call of a DIFFERENT session was, which makes cross-session false
#     positives the dominant output rather than the exception
#   - sort within a session by timestamp, then walk consecutive pairs
#   - a pair whose `from` is not a declared node is UNCLASSIFIED, not a
#     violation: entry points like `go` legitimately precede a lifecycle skill
#     and reporting them would drown the real signal. The count is surfaced in
#     --summary so the exclusion is visible rather than silent.
read -r -d '' JQ <<'JQEOF' || true
  [inputs]
  # The producer's timestamp field is `ts` (skill-invocation-logger.sh), NOT
  # `timestamp`. Reading the generator's prose instead of a real record cost a
  # silent zero: filtering on `.timestamp` dropped all 10,260 live records and
  # reported "undeclared=0 pairs=0", which is indistinguishable from a clean
  # run. `dropped` below exists so that can never be silent again.
  | . as $raw
  | map(select(.skill != null and .session_id != null and ((.ts // .timestamp) != null)))
  | map(.t = (.ts // .timestamp))
  | map(.skill |= sub("^soleur:"; ""))
  | ($raw | length) as $read
  | (length) as $kept
  | group_by(.session_id)
  | map(sort_by(.t))
  | map(. as $s | [range(1; ($s | length))]
        | map({ session: $s[0].session_id, from: $s[. - 1].skill, to: $s[.].skill }))
  | flatten
  # Bind the edge map AND each field BEFORE piping. `X | has(.from)` evaluates
  # `.from` against X, not against the element, because `|` rebinds `.` -- the
  # same scoping trap as `list | index(.key)`. It does not error quietly either:
  # it fails with "Cannot check whether object has a null key", which is at
  # least loud, but the `index` variant would silently never match.
  | ($decl[0].transitions) as $T
  | { read: $read,
      kept: $kept,
      dropped: ($read - $kept),
      pairs: length,
      sessions: (map(.session) | unique | length),
      # BOTH endpoints must be lifecycle nodes. A transition whose destination
      # is a SUB-SKILL of the current node is not a lifecycle transition at all:
      # measured against 16 months of real sessions, keying only on `from` made
      # ship -> preflight (797), plan -> deepen-plan (736), review -> qa (549)
      # and compound -> compound-capture (124) read as violations, which is an
      # instrument misreporting itself rather than a finding.
      unclassified: (map(select(. as $p | (($T | has($p.from)) and ($T | has($p.to))) | not)) | length),
      violations: (map(select(. as $p | ($T | has($p.from)) and ($T | has($p.to))))
                   | map(select(. as $p | ($T[$p.from] // []) | index($p.to) == null))) }
JQEOF

# `-n` so jq does not consume the first object implicitly; `[inputs]` then slurps
# the whole stream. Errors are NOT suppressed: an empty RESULT renders exactly
# like "no violations", so a parse failure must be loud rather than clean.
if ! RESULT=$(jq -n --slurpfile decl "$VIEW" "$JQ" < "$MERGED"); then
  echo "FATAL: could not classify $MERGED against $VIEW" >&2
  exit 2
fi
if [[ -z "$RESULT" ]]; then
  echo "FATAL: classification produced no output for $MERGED — treating as unresolved, not clean" >&2
  exit 2
fi

n=$(printf '%s' "$RESULT" | jq -r '.violations | length')
pairs=$(printf '%s' "$RESULT" | jq -r '.pairs')
sessions=$(printf '%s' "$RESULT" | jq -r '.sessions')
unclassified=$(printf '%s' "$RESULT" | jq -r '.unclassified')
read_n=$(printf '%s' "$RESULT" | jq -r '.read')
kept=$(printf '%s' "$RESULT" | jq -r '.kept')
dropped=$(printf '%s' "$RESULT" | jq -r '.dropped')

# A LOG THAT PARSES TO NOTHING IS NOT A CLEAN RUN. If records were read but none
# carried the expected shape, every downstream count is zero and reads exactly
# like "no violations" -- the failure this script hit on its own first live run,
# where a wrong timestamp field name discarded all 10,260 records behind
# "undeclared=0". Fail loudly rather than reporting a zero nobody can distinguish
# from a pass.
if [[ "$read_n" -gt 0 && "$kept" -eq 0 ]]; then
  echo "FATAL: read $read_n invocation record(s) and kept 0 — none carried skill + session_id + ts." >&2
  echo "       This is an UNPARSEABLE log, not an absence of violations. Check the producer's record shape" >&2
  echo "       (.claude/hooks/skill-invocation-logger.sh) against the filter in this script." >&2
  exit 2
fi
if [[ "$dropped" -gt 0 ]]; then
  echo "WARNING: dropped $dropped of $read_n invocation record(s) for missing skill/session_id/ts." >&2
fi

if [[ "$SUMMARY" -eq 1 ]]; then
  echo "undeclared=$n sessions=$sessions pairs=$pairs unclassified=$unclassified read=$read_n dropped=$dropped"
  exit 0
fi

printf '%s' "$RESULT" | jq -r '.violations[] | "  \(.session)\t\(.from) -> \(.to)"'
exit 0
