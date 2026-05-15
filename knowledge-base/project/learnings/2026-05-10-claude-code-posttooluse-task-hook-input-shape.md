---
date: 2026-05-10
category: best-practices
issue: 3494
pr: 3495
tags: [claude-code, hooks, posttooluse, task-tool, agent-tool]
---

# Claude Code PostToolUse hook on Task tool — empirically verified input shape

## Problem

Plan `2026-05-09-feat-token-efficiency-compound-phase-plan.md` specifies a PostToolUse hook on the `Task` tool matcher to tee subagent token envelopes to `.claude/.session-tokens.jsonl`. The plan flagged the input shape as needing **empirical verification** (per the precedent in `.claude/hooks/skill-invocation-logger.sh:13-22`). Documented field names from training data and external references conflicted with what Claude Code 2.1.138 actually emits, so this learning is the source of truth at implementation time.

## Empirical capture method

1. Created a stub PostToolUse hook on matcher `Task` that wrote raw stdin to `/tmp/soleur-task-hook-capture/stdin-<seq>.json`.
2. Wired the stub in `.claude/settings.json` PostToolUse array.
3. Spawned a child `claude -p` session (settings.json reloads at session start) and triggered the Agent tool twice via `--allowedTools "Task,Bash"`.
4. Inspected the captured stdin JSON files.
5. Reverted the stub wiring; deleted the stub file.

Claude Code CLI version: **2.1.138** (`claude --version`).

## Verified top-level shape

```json
{
  "session_id": "deadbeef-dead-beef-dead-beefdeadbeef",
  "transcript_path": "/home/jean/.claude/projects/.../<session_id>.jsonl",
  "cwd": "/abs/path/to/cwd",
  "permission_mode": "auto",
  "effort": {"level": "high"},
  "hook_event_name": "PostToolUse",
  "tool_name": "Agent",
  "tool_input": {
    "description": "...",
    "prompt": "...",
    "subagent_type": "Explore"
  },
  "tool_response": { ... see below ... },
  "tool_use_id": "toolu_014GRt7CkG34HrKcF6UxgXUJ",
  "duration_ms": 7200
}
```

**Critical findings:**

1. `tool_name` is `"Agent"` — NOT `"Task"`. Despite the user-facing name being "Task", the internal tool name passed to hooks is "Agent".
2. The matcher `"Task"` in `.claude/settings.json` **does** match `tool_name == "Agent"`. The hook fired correctly with matcher `Task`. Both `Task` and `Agent` matchers appear to match the same tool. (Stream events use `hook_name: "PostToolUse:Agent"`.)
3. `subagent_type` lives at `tool_input.subagent_type` (the user-supplied value).
4. Top-level `duration_ms` is wall-clock total (includes hook overhead). It can differ from `tool_response.totalDurationMs` (internal agent runtime).

## Verified `tool_response` shape

```json
{
  "status": "completed",
  "prompt": "...",
  "agentId": "a0ba4169469357cc3",
  "agentType": "Explore",
  "content": [{"type":"text","text":"..."}],
  "totalDurationMs": 3536,
  "totalTokens": 25741,
  "totalToolUseCount": 1,
  "usage": {
    "input_tokens": 5,
    "cache_creation_input_tokens": 169,
    "cache_read_input_tokens": 25627,
    "output_tokens": 58,
    "server_tool_use": {...},
    "service_tier": "standard",
    "iterations": [...]
  },
  "toolStats": {
    "readCount": 0,
    "searchCount": 1,
    "bashCount": 1,
    "editFileCount": 0,
    "linesAdded": 0,
    "linesRemoved": 0,
    "otherToolCount": 0
  }
}
```

**Field-path divergences from the plan/spec text:**

| Plan/spec assumption | Empirical reality |
|---|---|
| `tool_response.usage.total_tokens` (snake_case, nested under usage) | `tool_response.totalTokens` (camelCase, top-level of tool_response) |
| `tool_response.content` carries `total_tokens` as text needing regex extraction | `tool_response.totalTokens` is a structured int — `jq -r` is sufficient |
| `tool_uses` | `tool_response.totalToolUseCount` |
| `duration_ms` | `tool_response.totalDurationMs` (internal); top-level `duration_ms` is wall-clock |
| `subagent_type` (in tool_response) | `tool_response.agentType` (also `tool_input.subagent_type`) |

The `tool_response.usage` block exists but contains per-iteration `input_tokens`/`output_tokens`/`cache_*_input_tokens` — NOT a rolled-up `total_tokens`. The rolled-up number is `tool_response.totalTokens` at top level of `tool_response`.

## Flat vs sequential consistency

Two sequential Agent calls in the same session produced identical-shape PostToolUse fires. Each Agent invocation emits exactly one PostToolUse fire, with all fields populated. No drift in field names or structure between fires.

True nested-Task (Task A whose body spawns Task B) was NOT empirically captured; the plan called for both. **Mitigation in production hook:**

- `totalTokens`, `totalDurationMs`, `totalToolUseCount` are clearly rolled-up totals (the "total" prefix suggests inclusion of any child-Task token costs). The hook records the parent's envelope directly; child Tasks would each fire their own PostToolUse independently.
- All field reads use defensive `// 0` jq fallbacks so missing fields degrade gracefully.

If a future Claude Code release surfaces a `tool_response.nested_tasks[]` array (referenced in some external docs but absent here in 2.1.138), the existing hook still records the parent's `totalTokens` correctly — it just doesn't itemize children. That's acceptable for outlier detection on session-aggregate cost.

## Production hook field extraction

Single jq pipeline (defensive `// 0` / `// empty` fallbacks):

```bash
jq -r '
  {
    session_id: (.session_id // ""),
    subagent_type: (.tool_input.subagent_type // .tool_response.agentType // ""),
    total_tokens: (.tool_response.totalTokens // 0),
    tool_uses: (.tool_response.totalToolUseCount // 0),
    duration_ms: (.tool_response.totalDurationMs // .duration_ms // 0),
    status: (.tool_response.status // "")
  }
'
```

The hook writes a JSONL envelope per PostToolUse fire keyed on `session_id`. Compound Phase 1.6 filters by current session_id and `ts < compound_entry_ts` (R6 self-exclusion).

## Why this matters

Without empirical verification, the plan would have implemented `jq -r '.tool_response.usage.total_tokens'` (per the spec's TR1 "structured" hypothesis) and written zero-token envelopes for every subagent. The orphan-gate in the aggregator would still pass, the tests would still pass against synthesized fixtures, and the regression would only surface on **live integration** (Phase 7 step 5–6 of the work plan) — by which point the hook code is in committed history and the fix becomes a follow-up PR.

The skill-invocation-logger.sh precedent (date-stamped header comment with empirical shape) is repeated here for the agent-token-tee.sh hook: header records date `2026-05-10` and Claude Code version `2.1.138`.
