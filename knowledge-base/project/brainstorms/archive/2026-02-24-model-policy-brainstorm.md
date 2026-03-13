# Brainstorm: Model Selection Policy for Soleur

**Date:** 2026-02-24
**Status:** Complete

## What We're Building

A formal model selection policy for all Soleur agents, with three concrete changes:

1. **Fix the haiku exception** -- Change `learnings-researcher` from `model: haiku` to `model: inherit` so it respects the user's session model
2. **Document the model policy** -- Add a "Model Selection Policy" section to AGENTS.md establishing `model: inherit` as the standard for all agents
3. **Update agent-native-architecture references** -- Change tiered model recommendations in teaching materials to recommend Opus 4.6 as the default
4. **Make effort explicit** -- Add `"effortLevel": "high"` to `.claude/settings.json` so the project always runs at max reasoning effort
5. **Compliance checklist update** -- Add `model: inherit` verification to the Agent Compliance Checklist in AGENTS.md

## Why This Approach

- `model: inherit` already means Opus 4.6 when the session runs Opus -- 59 of 60 agents already use this
- Per-agent effort control does not exist in the Claude Code plugin spec (effort is session-level only)
- Making `inherit` the policy preserves user agency: users can switch to Sonnet for cost-sensitive work without fighting hardcoded opus overrides
- The one exception (`learnings-researcher` on haiku) was a premature optimization -- keyword searching still benefits from the session model's capabilities
- `effortLevel: high` is already the default, but making it explicit removes ambiguity and prevents accidental lowering

## Key Decisions

- **Default model:** `model: inherit` for all agents, no exceptions
- **Override policy:** Explicit model overrides require justification in the agent body text (currently no justified use cases exist)
- **Effort control:** Session-level via `effortLevel` in settings, not per-agent (not possible in current spec)
- **Reference docs:** Update agent-native-architecture skill references to recommend Opus 4.6 instead of tiered haiku/sonnet/opus
- **Policy location:** AGENTS.md only (not constitution) -- practical and discoverable for developers

## Research Findings

### Current State (60 agents)

| Model Setting | Count | Agents |
|--------------|-------|--------|
| `inherit` | 59 | All except learnings-researcher |
| `haiku` | 1 | learnings-researcher |
| `sonnet` | 0 | -- |
| `opus` | 0 | -- |

### Plugin Spec Capabilities

Per-agent frontmatter supports: `model`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `permissionMode`, `memory`, `background`, `isolation`.

Not supported per-agent: `effortLevel`, `temperature`, `max_tokens`.

### Effort Configuration

| Method | Scope | Setting |
|--------|-------|---------|
| `/model` slider | Mid-session | Left/right arrows |
| `CLAUDE_CODE_EFFORT_LEVEL` env var | Before session | `low`/`medium`/`high` |
| `.claude/settings.json` | Project/user | `"effortLevel": "high"` |

Only supported on Opus 4.6. Default is `high`.

## Open Questions

None -- scope is well-defined and all decisions are made.
