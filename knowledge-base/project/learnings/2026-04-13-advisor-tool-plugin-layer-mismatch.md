# Learning: Claude API Advisor Tool Cannot Work at Plugin Level

## Problem

Investigated adopting the Claude API `advisor_20260301` server-side tool for Soleur to reduce token consumption. The advisor tool lets a cheap executor model (Sonnet/Haiku) consult Opus for hard reasoning within a single API request, reducing costs by 12-85%.

## Solution

The advisor tool is a **Messages API construct** — it goes into the `tools` parameter of a `messages.create()` call. Claude Code plugins spawn subagents via the Task/Agent tool, which translates into API calls internally. The plugin has **zero control** over the underlying `tools` array in those API calls.

Two distinct surfaces exist:

- **Plugin (Claude Code):** Cannot use advisor. Would require Claude Code runtime changes (tool passthrough on Task/Agent calls, plugin spec `advisor` config). Neither exists.
- **Web platform (app.soleur.ai):** Can use advisor directly via the `query()` call in `agent-runner.ts`, since the platform controls the full API request.

For plugin-side token reduction, the available levers are:

1. Context-aware gating (spawn agents only when their expertise matches the change)
2. Per-agent `model:` frontmatter overrides (blunt — one model per agent, not per-call)
3. Reducing fan-out degree (fewer parallel agents per pipeline)

## Key Insight

Before investigating API features for cost optimization in a plugin, verify which abstraction layer the plugin operates at. Claude Code plugins sit above the Messages API — they cannot inject tools, modify request parameters, or control model routing at the API level. Cost optimization at the plugin level must use the levers the plugin spec provides (`model:` frontmatter, conditional agent spawning), not API-level features.

## Session Errors

**Worktree disappeared after creation** — Created `feat-advisor-strategy` worktree, got success confirmation, but the path was gone when later accessed. Recreated successfully. Root cause unclear — possible race condition or cleanup interference. **Prevention:** Verify worktree existence with `ls` immediately after creation before proceeding with downstream operations.

## Tags

category: integration-issues
module: plugin-architecture
