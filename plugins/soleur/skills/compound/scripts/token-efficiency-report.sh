#!/usr/bin/env bash
# Token-efficiency report — invoked from compound Phase 1.6 (issue #3494).
#
# Reads three signals from the just-completed session, prints a top-3 cost
# table, and emits incidents.sh `warn` telemetry under the `te-*` synthetic
# rule_id namespace when an outlier triggers. Companion catalog: #3493.
# Tuning follow-up: #3497.
#
# Inputs (resolved from env or git-rev-parse):
#   TE_REPORT_REPO_ROOT       repo root override (tests)
#   INCIDENTS_REPO_ROOT       redirect for emit_incident (tests)
#   CLAUDE_CODE_SESSION_ID    session id (env, set by Claude Code at session start)
#   RATIO_EMIT_ENABLED        0|1 — gates te-agents-md-turn-cost (default 0 until #3497)
#
# Side effects: appends to .claude/.rule-incidents.jsonl on outlier detection.
# Output: a Markdown block to stdout (≤600 tokens of generated text).

set -euo pipefail

# ---- Flags + thresholds (all env-overridable for #3497 tuning) ----------
# Per code-quality review: defining these as `${VAR:=default}` lets the
# tuning PR ship a config change without code edits.
: "${RATIO_EMIT_ENABLED:=0}"
: "${SUBAGENT_OVERSHOOT_TOKENS:=100000}"
: "${SKILL_PAYLOAD_FLOOR_BYTES:=200000}"
: "${RATIO_THRESHOLD_X1000:=2000}"      # 2k tokens/line × 1000 scaling
: "${SKIP_LINES_THRESHOLD:=50}"
: "${TURN_COUNT_PROXY:=25}"             # fixed approximation; refined via #3497

FIXTURE_MODE=0
[[ "${1:-}" == "--fixture-mode" ]] && FIXTURE_MODE=1

# Per-run tempfile via mktemp + EXIT trap. `$$` is the parent PID and is
# predictable across concurrent runs in shared shells (per code-quality +
# pattern-recognition review). Trap registered before any work so SIGINT/
# SIGTERM mid-script doesn't leak.
SHORTSTAT_TMP="$(mktemp -t te-shortstat.XXXXXX)"
trap 'rm -f "$SHORTSTAT_TMP"' EXIT INT TERM

# ---- Repo-root + session resolution -------------------------------------
if [[ -n "${TE_REPORT_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$TE_REPORT_REPO_ROOT"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"

# Session-id fallback (per pattern-recognition review): when neither env var
# is set (e.g., direct script invocation outside a Claude Code session),
# read the most recent session_id from the session-tokens telemetry. The
# hook always records it; this makes the writer/reader contract symmetric.
if [[ -z "$SESSION_ID" && -f "$REPO_ROOT/.claude/.session-tokens.jsonl" ]]; then
  SESSION_ID=$(jq -r 'select(.schema == 1) | .session_id' \
    "$REPO_ROOT/.claude/.session-tokens.jsonl" 2>/dev/null \
    | tail -1)
fi

# ---- Skip rule (lines<50 → exit early; R7 merge-base fallback) ----------
# `timeout 5s` bounds the git diff per performance review — a stale long-
# running branch can produce a multi-second shortstat that would otherwise
# silently extend the report's runtime via the `2>/dev/null` mask.
LINES=0
(
  cd "$REPO_ROOT" 2>/dev/null || exit 0
  if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    DIFF_BASE="HEAD~1"
  else
    DIFF_BASE="$(git merge-base HEAD main 2>/dev/null \
      || git rev-list --max-parents=0 HEAD 2>/dev/null \
      || git rev-parse HEAD)"
  fi
  timeout 5s git diff --shortstat "$DIFF_BASE" 2>/dev/null
) > "$SHORTSTAT_TMP" 2>/dev/null || true

if [[ -s "$SHORTSTAT_TMP" ]]; then
  LINES=$(grep -oE '[0-9]+ (insertion|deletion)' "$SHORTSTAT_TMP" \
    | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
fi

if (( LINES < SKIP_LINES_THRESHOLD )); then
  echo "### Phase 1.6: skipped (small diff: $LINES lines changed)"
  exit 0
fi

# ---- Signal 1: AGENTS.md floor ------------------------------------------
AGENTS_BYTES=0
[[ -f "$REPO_ROOT/AGENTS.md" ]] && AGENTS_BYTES=$(wc -c < "$REPO_ROOT/AGENTS.md")
AGENTS_FLOOR=$((AGENTS_BYTES * TURN_COUNT_PROXY))

# ---- Signal 2: skill-payload sum (R6 self-exclusion via compound_entry_ts)
#
# R6 self-exclusion modes (per architecture review):
#   1. Normal (compound invoked via Skill tool): the PreToolUse Skill hook
#      records soleur:compound's entry timestamp; we filter envelopes to
#      ts < compound_entry_ts. Tight closed loop.
#   2. Direct script invocation (operator runs `bash …/token-efficiency-
#      report.sh`): no compound entry exists. cts falls through to
#      9999-12-31 (fail-open). All session subagents counted; documented
#      below — caller knows they're outside compound and accepts double-
#      counting compound's own children if compound was somehow run.
#   3. Repeat compound invocation in one session: `sort | tail -1` picks
#      the LATEST entry. Envelopes between first and second compound
#      runs are counted as "session work" — slight overcount, acceptable
#      because the alternative (head -1) excludes legitimate work between
#      runs.
SKILL_INVOCATIONS="$REPO_ROOT/.claude/.skill-invocations.jsonl"
COMPOUND_ENTRY_TS=""
if [[ -f "$SKILL_INVOCATIONS" && -n "$SESSION_ID" ]]; then
  COMPOUND_ENTRY_TS=$(jq -r --arg s "$SESSION_ID" \
    'select(.session_id == $s and .skill == "soleur:compound") | .ts' \
    "$SKILL_INVOCATIONS" 2>/dev/null | sort | tail -1)
fi

PAYLOAD_TOTAL=0
LARGEST_SKILL=""
LARGEST_SKILL_BYTES=0
if [[ -f "$SKILL_INVOCATIONS" && -n "$SESSION_ID" ]]; then
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    # Validate skill-id shape (per security + code-quality review):
    # rejects path-traversal sequences (`../`), shell metacharacters, and
    # `find -path` glob chars (`*`, `?`). Allows lowercase alphanumerics +
    # hyphens with optional `<plugin>:<skill>` namespace.
    [[ "$skill" =~ ^[a-z0-9_-]+(:[a-z0-9_-]+)?$ ]] || continue
    skill_md=""
    case "$skill" in
      soleur:*) skill_md="$REPO_ROOT/plugins/soleur/skills/${skill#soleur:}/SKILL.md" ;;
      *:*)
        plugin="${skill%%:*}"
        sub="${skill#*:}"
        skill_md="$REPO_ROOT/plugins/${plugin}/skills/${sub}/SKILL.md"
        ;;
      *)
        skill_md=$(find "$REPO_ROOT/plugins" -maxdepth 4 \
          -path "*/skills/${skill}/SKILL.md" -type f 2>/dev/null | head -1)
        ;;
    esac
    if [[ -n "$skill_md" && -f "$skill_md" ]]; then
      bytes=$(wc -c < "$skill_md")
      PAYLOAD_TOTAL=$((PAYLOAD_TOTAL + bytes))
      if (( bytes > LARGEST_SKILL_BYTES )); then
        LARGEST_SKILL="$skill"
        LARGEST_SKILL_BYTES=$bytes
      fi
    fi
  done < <(timeout 5s jq -r --arg s "$SESSION_ID" \
    'select(.schema == 1 and .session_id == $s) | .skill' \
    "$SKILL_INVOCATIONS" 2>/dev/null \
    | sort -u)
fi

# ---- Signal 3: subagent envelopes (R6: ts < compound_entry_ts) ----------
# Single jq pass + awk reduction (per performance review) — avoids two
# full-file scans of .session-tokens.jsonl. Adds `select(.schema == 1)`
# gate (per data-integrity review) so a future schema-2 line with renamed
# fields silently drops out of the count rather than corrupting it.
SESSION_TOKENS="$REPO_ROOT/.claude/.session-tokens.jsonl"
MAX_ENVELOPE=0
SUM_ENVELOPES=0
TOP_OFFENDER=""
if [[ -f "$SESSION_TOKENS" && -n "$SESSION_ID" ]]; then
  cts="${COMPOUND_ENTRY_TS:-9999-12-31T23:59:59Z}"
  # IFS=$'\t' so a TOP_OFFENDER with spaces (subagent_type can contain them)
  # doesn't shift fields — same defensive pattern used by the hook reader.
  IFS=$'\t' read -r MAX_ENVELOPE TOP_OFFENDER SUM_ENVELOPES < <(
    timeout 5s jq -r --arg s "$SESSION_ID" --arg cts "$cts" \
      'select(.schema == 1 and .session_id == $s and .ts < $cts)
       | [(.total_tokens // 0), (.subagent_type // "")] | @tsv' \
      "$SESSION_TOKENS" 2>/dev/null \
      | awk -F'\t' 'BEGIN{m=0;s=0;t=""} {s+=$1; if($1>m){m=$1;t=$2}} END{printf "%d\t%s\t%d\n", m, t, s}'
  ) || true
  MAX_ENVELOPE="${MAX_ENVELOPE:-0}"
  SUM_ENVELOPES="${SUM_ENVELOPES:-0}"
fi

# ---- Compute ratio (always; emit gated by flag) -------------------------
RATIO_X1000=0
if (( SUM_ENVELOPES > 0 && LINES > 0 )); then
  RATIO_X1000=$((SUM_ENVELOPES * 1000 / LINES))
fi

# ---- Outlier detection — emit incidents.sh warn -------------------------
# Lib resolution: REPO_ROOT first (production + most fixtures), then the
# upstream repo via `git rev-parse` from this script's location (covers
# fixture-mode tests that run from a throwaway repo without the lib).
# Avoids the 5-segment relative-path trap flagged by pattern review.
INCIDENTS_LIB="$REPO_ROOT/.claude/hooks/lib/incidents.sh"
if [[ ! -f "$INCIDENTS_LIB" ]]; then
  SELF_REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null \
    && git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$SELF_REPO" ]] && INCIDENTS_LIB="$SELF_REPO/.claude/hooks/lib/incidents.sh"
fi
# shellcheck source=/dev/null
[[ -f "$INCIDENTS_LIB" ]] && source "$INCIDENTS_LIB"

if (( MAX_ENVELOPE > SUBAGENT_OVERSHOOT_TOKENS )); then
  emit_incident te-subagent-overshoot warn \
    "subagent envelope > 100k tokens" \
    "subagent_type=$TOP_OFFENDER total_tokens=$MAX_ENVELOPE"
fi

if (( PAYLOAD_TOTAL > SKILL_PAYLOAD_FLOOR_BYTES )); then
  emit_incident te-skill-payload-floor warn \
    "skill payload sum > 200k chars" \
    "largest_skill=$LARGEST_SKILL largest_bytes=$LARGEST_SKILL_BYTES total=$PAYLOAD_TOTAL"
fi

if (( RATIO_EMIT_ENABLED == 1 )) && (( RATIO_X1000 > RATIO_THRESHOLD_X1000 )); then
  emit_incident te-agents-md-turn-cost warn \
    "session ratio > 2k tokens/line" \
    "ratio_x1000=$RATIO_X1000 sum_envelopes=$SUM_ENVELOPES lines=$LINES"
fi

# ---- Render top-3 cost table + mitigations ------------------------------
# Pipe (label, value-bytes-or-tokens, raw-magnitude) lines into sort to
# rank by raw magnitude. Magnitudes: AGENTS_FLOOR is bytes×turns; payload
# is bytes; envelopes are tokens. Apples-to-oranges by intent — these are
# the three competing candidates for the session's top cost line.
LINE_AGENTS="AGENTS.md floor (×${TURN_COUNT_PROXY}t):${AGENTS_FLOOR}"
LINE_PAYLOAD="Skill payload sum:${PAYLOAD_TOTAL}"
LINE_SUBAGENTS="Subagent envelopes (sum):${SUM_ENVELOPES}"

cat <<MD
### Phase 1.6: token-efficiency report

Lines changed: ${LINES}. Largest subagent: ${TOP_OFFENDER:-n/a} (${MAX_ENVELOPE} tokens).
Largest skill payload: ${LARGEST_SKILL:-n/a} (${LARGEST_SKILL_BYTES} bytes).

| Rank | Line item | Magnitude |
|-----:|-----------|----------:|
$(printf '%s\n%s\n%s\n' "$LINE_AGENTS" "$LINE_PAYLOAD" "$LINE_SUBAGENTS" \
  | awk -F: 'BEGIN{i=1} {print i++"|"$1"|"$2}' \
  | sort -t'|' -k3 -nr \
  | awk -F'|' '{printf "| %s | %s | %s |\n", NR, $2, $3}')

MD

# Mitigation suggestions matched to triggered outliers.
if (( MAX_ENVELOPE > SUBAGENT_OVERSHOOT_TOKENS )); then
  echo "- **Subagent overshoot**: ${TOP_OFFENDER} consumed ${MAX_ENVELOPE} tokens. Consider tighter prompt scope or splitting the work across smaller subagents."
fi
if (( PAYLOAD_TOTAL > SKILL_PAYLOAD_FLOOR_BYTES )); then
  echo "- **Skill payload floor**: ${LARGEST_SKILL} contributed ${LARGEST_SKILL_BYTES} bytes to a session-total of ${PAYLOAD_TOTAL}. Audit ≥10k-byte SKILL.md files for trim opportunities (per #3493 catalog)."
fi
if (( RATIO_EMIT_ENABLED == 1 )) && (( RATIO_X1000 > RATIO_THRESHOLD_X1000 )); then
  echo "- **Session ratio**: ${RATIO_X1000}/1000 tokens/line exceeds 2k. Investigate AGENTS.md size or per-turn cost (see #3497 tuning)."
fi
if (( MAX_ENVELOPE <= SUBAGENT_OVERSHOOT_TOKENS )) \
   && (( PAYLOAD_TOTAL <= SKILL_PAYLOAD_FLOOR_BYTES )) \
   && ! { (( RATIO_EMIT_ENABLED == 1 )) && (( RATIO_X1000 > RATIO_THRESHOLD_X1000 )); }; then
  echo "- No outliers triggered. Session within thresholds."
fi

exit 0
