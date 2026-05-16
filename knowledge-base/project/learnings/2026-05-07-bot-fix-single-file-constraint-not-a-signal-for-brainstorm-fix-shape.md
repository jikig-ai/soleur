---
title: Bot-fix's single-file constraint is not a signal for brainstorm fix-shape selection
date: 2026-05-07
category: best-practices
module: compound,brainstorm,fix-issue
tags: [bot-fix, brainstorm, scope-out, user-brand-critical, fix-shape]
---

# Learning: Bot-fix's single-file constraint is not a signal for brainstorm fix-shape selection

## Problem

Issue #3269 was opened as a `deferred-scope-out` from the PR #3263 multi-agent review. The issue body listed three contested fix shapes: (a) system-prompt notice, (b) WS event, (c) MCP tool. The `claude[bot]` automated `fix-issue` skill attempted (a), then bailed with:

> "The fix requires changes to multiple files. Implementing option (a) (system-prompt notice) needs `agent-prefill-guard.ts` to return a `contextResetNotice`, plus `cc-dispatcher.ts` (~line 619) and `agent-runner.ts` (~lines 584-590) to consume that notice and inject it into `args.systemPrompt`. Touching more than one file violates the single-file constraint for automated fixes."

When `/soleur:go` routed the same issue to brainstorm, there was a temptation to anchor on the bot's framing — "(a) is the right shape, just needed multi-file" — and route to `/soleur:one-shot` for the cheapest implementation. **That framing is wrong.** The bot's signal is about its own implementation envelope (single-file constraint), not about whether the chosen fix shape closes the user-brand-critical gap.

## Solution

When a brainstorm starts from a `deferred-scope-out` issue with a `bot-fix/attempted` label or comment trail, **disregard the bot's fix-shape choice as a recommendation**. The bot's selection optimized one variable (single-file scope) that is orthogonal to the brainstorm's job (picking the smallest fix that meets the brand-survival threshold).

Workflow:

1. Read the bot-fix comment to learn **what it tried**, not **what it endorsed**.
2. Run the user-impact framing question (`hr-weigh-every-decision-against-target-user-impact`) on the original issue body, not on the bot's framing of it.
3. Spawn user-brand-critical leaders (CPO + CLO + CTO when threshold is `single-user incident`) and let them weigh fix shapes against brand-survival, not against implementation cost.
4. If the leaders converge on a different shape than the bot attempted, that is the signal — not the bot's "this needs multi-file."

In the #3269 case: CPO + CLO + CTO independently converged on **(a)+(b) in one PR** (system-prompt notice + WS context_reset event). The bot picked (a) alone because (a) was the cheapest single component, but (a) alone is asymmetric notification (model knows, user doesn't), which fails the `single-user incident` threshold for an autonomous-agent product with destructive tools. The bot's "needs multi-file" comment was correct but irrelevant — the brainstorm conclusion was that **(a) alone, even if it had been single-file, was insufficient.**

## Key Insight

Two systems are in play with non-overlapping objectives:

- **`fix-issue` (bot)** optimizes for "ship a small, mechanically-safe fix in one file."
- **`brainstorm` + leaders** optimize for "pick the smallest fix that meets the brand-survival threshold."

When these conflict, brainstorm wins. The bot's bail-out is a **handoff signal** ("a human or brainstorm should look at this"), not a **fix-shape endorsement** ("(a) is the right call, just bigger than I can do"). Treat the bot comment as `read-only context`, never as a `recommended approach` field.

This generalizes beyond #3269: any time `fix-issue` bails out of a `deferred-scope-out` issue with a fix-shape pre-selection, the brainstorm must re-derive the shape from leader consensus. The bot's pre-selection is a useful starting prompt only — never a default.

## Session Errors

1. **`gh pr create` GraphQL rate-limit (recovered)** — Recovery: retried direct `gh pr create` ~10 min after the worktree-manager `draft-pr` rate-limited. Prevention: `worktree-manager.sh draft-pr` could detect GraphQL rate-limit specifically and emit a deferred-retry hint with the exact `gh pr create` command operator can run later, instead of the current silent "Branch is pushed to remote" warning that obscures whether the PR was created.

2. **Wrong assumption about spec-templates layout (recovered)** — Recovery: `find plugins/soleur/skills/spec-templates -type f` showed only `SKILL.md`; templates are inline. Prevention: none needed (one-time discovery cost; not a workflow gap).

3. **Wrong assumption about ADR location (recovered)** — Recovery: `find knowledge-base -type d -name "adr*" -o -name "architecture*"` revealed `knowledge-base/engineering/architecture/`. Prevention: none needed (the architecture skill's SKILL.md documents the path; a one-time grep would have caught it).

## Cross-references

- Parent issue: #3269 — surface prefill-guard fires to model + user (context-reset signal)
- Bot-fix attempt comment: https://github.com/jikig-ai/soleur/issues/3269#issuecomment-4395333534
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-prefill-guard-context-reset-signal-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-prefill-guard-context-reset-signal/spec.md`
- ADR-025: WS lifecycle-notice event family
- Related rule: `hr-weigh-every-decision-against-target-user-impact`
- Related rule: `hr-when-triaging-a-batch-of-issues-never` (also names `fix-issue` as not authoritative for triage decisions)

## Tags

category: best-practices
module: compound,brainstorm,fix-issue
