#!/usr/bin/env bash
# Skill-invocation telemetry hook (Track C3 of #3122).
#
# Wired as a PreToolUse hook on the `Skill` matcher in .claude/settings.json.
# Appends one JSONL record per Skill tool call to .claude/.skill-invocations.jsonl
# so the monthly skill-freshness aggregator can surface idle skills.
#
# Empirically verified hook input shape (transcript inspection 2026-05-04):
#     {
#       "tool_name": "Skill",
#       "tool_input": {
#         "skill": "soleur:plan",
#         "args": "..."
#       }
#     }
# We extract `tool_input.skill` (e.g. "soleur:plan", "soleur:work").
#
# Storage: gitignored .claude/.skill-invocations.jsonl, mirroring the
# .claude/.rule-incidents.jsonl precedent. The skill-freshness aggregator
# (scripts/skill-freshness-aggregate.sh) reads this file in CI runs.
#
# Kill-switch: SOLEUR_DISABLE_SKILL_LOGGER=1 short-circuits at the top.
#
# Fire-and-forget: every jq invocation has 2>/dev/null + return-0 fallback.
# Never blocks tool dispatch — exits 0 unconditionally.
#
# See knowledge-base/project/plans/2026-05-04-feat-scheduled-audits-skill-freshness-plan.md

# Kill-switch: short-circuit before any work.
[[ "${SOLEUR_DISABLE_SKILL_LOGGER:-}" == "1" ]] && exit 0

# Repo-root resolution. Canonicalize via `cd -P + pwd -P` so a symlinked
# .claude/ does NOT produce two disjoint flock inodes (per learning
# 2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md).
_repo_root() {
  if [[ -n "${SKILL_LOGGER_REPO_ROOT:-}" ]]; then
    echo "$SKILL_LOGGER_REPO_ROOT"
    return
  fi
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)
}

# Read hook input JSON from stdin. Guard against invalid JSON via 2>/dev/null
# (per learning 2026-03-18-stop-hook-jq-invalid-json-guard.md).
INPUT="$(cat)"
SKILL="$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"

# Skip silently if no skill name (malformed input or non-Skill tool call
# slipping through the matcher — both fail-soft).
[[ -z "$SKILL" ]] && exit 0

repo_root="$(_repo_root)" || exit 0
file="$repo_root/.claude/.skill-invocations.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Create parent + file (flock requires the file to exist).
mkdir -p "$(dirname "$file")" 2>/dev/null || exit 0
[[ -f "$file" ]] || : > "$file" 2>/dev/null || exit 0

# Build line via jq -nc (single-line JSON), fail-soft.
line="$(jq -nc \
  --arg ts "$ts" \
  --arg s "$SKILL" \
  --arg sid "$SESSION_ID" \
  --argjson schema 1 \
  '{schema:$schema, ts:$ts, skill:$s, session_id:$sid, hook_event:"PreToolUse"}' \
  2>/dev/null)" || exit 0

# Append under flock so concurrent worktrees / sub-agents do not interleave.
(
  flock -x 9
  printf '%s\n' "$line" >&9
) 9>>"$file" 2>/dev/null || true

exit 0
