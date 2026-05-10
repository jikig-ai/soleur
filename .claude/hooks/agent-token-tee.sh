#!/usr/bin/env bash
# Agent (Task) token-envelope telemetry hook (issue #3494).
#
# Wired as a PostToolUse hook on the `Task` matcher in .claude/settings.json
# (the matcher "Task" matches the internal tool_name "Agent" — see learning
# 2026-05-10-claude-code-posttooluse-task-hook-input-shape.md).
# Appends one JSONL record per Agent invocation to .claude/.session-tokens.jsonl
# so compound Phase 1.6 can sum subagent envelopes for outlier detection.
#
# Empirically verified hook input shape (Claude Code 2.1.138, transcript
# inspection 2026-05-10):
#     {
#       "session_id": "<uuid>",
#       "hook_event_name": "PostToolUse",
#       "tool_name": "Agent",
#       "tool_input": { "subagent_type": "<type>", ... },
#       "tool_response": {
#         "status": "completed",
#         "agentType": "<type>",
#         "totalTokens": <int>,            # rolled-up — includes nested-Task tokens
#         "totalToolUseCount": <int>,
#         "totalDurationMs": <int>,
#         "usage": { ... per-iteration breakdown ... }
#       },
#       "duration_ms": <int>               # wall-clock incl. hook overhead
#     }
#
# Field-path divergences from the spec/plan text are documented in the learning.
# Production hook reads totalTokens / totalToolUseCount / totalDurationMs (camelCase,
# top-level of tool_response). The `usage` block is NOT used here — it carries
# per-iteration breakdown, not the rolled-up session number.
#
# Storage: gitignored .claude/.session-tokens.jsonl, mirroring .skill-invocations.jsonl.
#
# Kill-switch: SOLEUR_DISABLE_AGENT_TOKEN_TEE=1 short-circuits at the top.
#
# Fire-and-forget: every jq invocation has 2>/dev/null + return-0 fallback;
# flock -w 5 timeout fallback per plan Sharp Edge #9; never blocks tool dispatch.

# Kill-switch: short-circuit before any work.
[[ "${SOLEUR_DISABLE_AGENT_TOKEN_TEE:-}" == "1" ]] && exit 0

# `set -u` catches typos in variable names that would otherwise silently
# produce empty fields and drop envelopes. `-e` and `-o pipefail` are
# intentionally NOT set: this hook is fire-and-forget per the PostToolUse
# contract, and a single jq failure must not block tool dispatch — every
# critical pipe has its own `2>/dev/null || exit 0` fallback.
set -u

# Repo-root resolution (canonicalize via cd -P / pwd -P so symlinked .claude/
# does not produce two disjoint flock inodes — same precedent as
# skill-invocation-logger.sh).
_repo_root() {
  if [[ -n "${AGENT_TOKEN_TEE_REPO_ROOT:-}" ]]; then
    echo "$AGENT_TOKEN_TEE_REPO_ROOT"
    return
  fi
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)
}

INPUT="$(cat)"

# Read all relevant fields in one jq pass with defensive fallbacks.
# Output: TAB-separated tool_name, session_id, subagent_type, total_tokens,
# tool_uses, duration_ms. Empty fields collapse to "" / "0".
# IFS=$'\t' is REQUIRED — `subagent_type` may contain spaces (e.g.,
# "soleur:engineering:review:security-sentinel" is space-free, but the model
# can supply arbitrary strings); default IFS would split on spaces and shift
# all subsequent fields.
IFS=$'\t' read -r TOOL_NAME SESSION_ID SUBAGENT_TYPE TOTAL_TOKENS TOOL_USES DURATION_MS < <(
  echo "$INPUT" | jq -r '[
    (.tool_name // ""),
    (.session_id // ""),
    (.tool_input.subagent_type // .tool_response.agentType // ""),
    (.tool_response.totalTokens // 0),
    (.tool_response.totalToolUseCount // 0),
    (.tool_response.totalDurationMs // .duration_ms // 0)
  ] | @tsv' 2>/dev/null
) || exit 0

# Match guard: only fire on Agent tool. Hook matcher should already filter
# but we double-check (cheap) so a stray non-Agent input fails silently.
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

# Sanitize SUBAGENT_TYPE before storing. The model controls this string; we
# strip control chars (0x00-0x1f, 0x7f) and Unicode line/paragraph separators
# (U+2028/U+2029 — see cq-regex-unicode-separators-escape-only) and cap length
# at 64 chars to prevent log-viewer-rendered phantom JSONL entries if this
# telemetry is ever piped to a UI/Sentry surface.
SUBAGENT_TYPE="$(printf '%s' "$SUBAGENT_TYPE" \
  | tr -d '\000-\037\177' \
  | sed 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g')"
SUBAGENT_TYPE="${SUBAGENT_TYPE:0:64}"

# Skip when totalTokens is 0 or absent — per R1 mitigation, treat zero-token
# envelopes as Claude Code shape drift, not a real zero-cost subagent. Better
# to undercount than to silently emit fake-zero envelopes that mask drift.
[[ -z "$TOTAL_TOKENS" ]] && exit 0
[[ "$TOTAL_TOKENS" -eq 0 ]] 2>/dev/null && exit 0

repo_root="$(_repo_root)" || exit 0
file="$repo_root/.claude/.session-tokens.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$file")" 2>/dev/null || exit 0
[[ -f "$file" ]] || : > "$file" 2>/dev/null || exit 0

line="$(jq -nc \
  --arg ts "$ts" \
  --arg sid "$SESSION_ID" \
  --arg sub "$SUBAGENT_TYPE" \
  --argjson tt "$TOTAL_TOKENS" \
  --argjson tu "$TOOL_USES" \
  --argjson dm "$DURATION_MS" \
  --argjson schema 1 \
  '{schema:$schema, ts:$ts, session_id:$sid, subagent_type:$sub, total_tokens:$tt, tool_uses:$tu, duration_ms:$dm, hook_event:"PostToolUse"}' \
  2>/dev/null)" || exit 0

# Append under flock with 5s timeout (plan Sharp Edge #9). On contention
# timeout, log to stderr and exit 0 — never block tool dispatch.
(
  if ! flock -w 5 -x 9; then
    echo "agent-token-tee: flock timeout, dropping envelope (sid=$SESSION_ID)" >&2
    exit 0
  fi
  printf '%s\n' "$line" >&9
) 9>>"$file" 2>/dev/null || true

exit 0
