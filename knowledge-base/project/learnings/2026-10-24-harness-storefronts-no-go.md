---
title: "Always-on teammate listings are a no-go; the marketplace pattern is already learned"
date: 2026-10-24
category: workflow-patterns
tags: [brainstorm, no-go, grok-bot, openai-dots, gemini, marketplace]
---

# Learning: Always-on teammate listings are a no-go

## Problem

A brainstorm asked whether Soleur should be published as a Grok Bot, an OpenAI Dot, or "Gemini Duets" so a customer could run it as an always-on teammate. Those products hold the customer's logins on a vendor computer. Soleur's review gates assume an interactive coding session.

## Solution

The operator chose to record the no-go and stop. The record is `knowledge-base/project/brainstorms/2026-10-24-harness-storefronts-brainstorm.md` and `knowledge-base/project/specs/feat-harness-storefronts/spec.md` (issue #11035, draft PR #11033). No listing, no new adapter, and no publisher account.

The product pattern was already written down. Do not open a new skill for it.

- `knowledge-base/project/learnings/2026-05-15-evaluating-anthropic-first-party-plugin-marketplaces.md`
- `knowledge-base/project/learnings/2026-03-10-verify-external-platforms-before-strategizing.md`
- ADR-274 rejects a Cursor marketplace listing as a separate contract.

"Gemini Duets" is not a product name that search returned on 2026-10-24. Claude Duet is a different vendor. The name stays unresolved and the no-go covers the Gemini enterprise agent, the unverified app hub, and using Claude Duet as a substitute.

## Key Insight

A coding-agent adapter (Grok Build, Codex, Antigravity) is not a listing on the vendor's always-on teammate. Verify the live product name before a strategy, then keep the decision in the brainstorm when the answer is a no-go.

## Session Errors

1. **Brainstorm SKILL.md first read exceeded the token cap** (limit 400 lines, 29791 tokens against a 25000 cap). Recovery: read the file in 200-line chunks. **Prevention:** start a multi-thousand-line SKILL.md on a short chunk. The tool error already names the cap. One-off. No new rule.

2. **The CLO subagent was still running after the first 300 second wait.** Recovery: a second wait returned exit 0 at about 329 seconds. The draft ruling stands. **Prevention:** a slow leader is unfinished work, not a failed verdict. One-off. No new rule.

3. **`GROK_PLUGIN_ROOT` was unset at session start.** Recovery: export it to `plugins/soleur` before the session gates. On Grok Build, `source=none` until that export is expected. **Prevention:** the gates already report `source=grok-env` once the root is set. One-off for this session. No new rule.

4. **`git status` at the workspace root failed with "this operation must be run in a work tree"** after compaction. Recovery: run git from `.worktrees/feat-harness-storefronts`. **Prevention:** writes stay in the feature worktree. One-off. No new rule.

## Tags

category: workflow-patterns
module: brainstorm
