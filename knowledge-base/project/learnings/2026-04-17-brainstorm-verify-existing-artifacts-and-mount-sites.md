---
date: 2026-04-17
category: process
module: brainstorm
tags: [brainstorm, verification, pre-research, grep-first]
issues: ["#1691", "#2464"]
---

# Learning: Verify claims by grep; check existing KB artifacts before spawning research

## Problem

During the 2026-04-17 brainstorm for restoring the BYOK usage dashboard
(#1691, PR #2464), two process errors showed up before the scope questions
were even settled:

1. **False-negative mount claim.** The initial Explore agent reported that
   the chat cost badge was "not confirmed to be rendered in UI (no grep
   match for cost badge component)." I propagated that into the user-facing
   synthesis message. A later repo-research-analyst agent found the badge
   was in fact mounted at `apps/web-platform/components/chat/chat-surface.tsx`
   lines 408-423, 462-466, and 467-481. The Explore agent had grepped for a
   generic phrase ("cost badge") that doesn't appear in the code — the
   correct grep was for the consuming state identifier
   `usageData.totalCostUsd`, which is all over the file.

2. **Skipped existing-artifact check.** A prior brainstorm
   (`2026-04-10-byok-cost-tracking-brainstorm.md`) and spec
   (`specs/feat-byok-cost-tracking/spec.md`) had already decided scope for
   this exact feature. The CPO and repo-research agents both rediscovered
   these artifacts mid-session. A 5-second `ls` over
   `knowledge-base/project/brainstorms/` and `specs/` for keywords ("BYOK",
   "cost", "usage") as the first action of Phase 1.1 would have pre-loaded
   the prior decisions before spawning research agents.

Neither error blocked the session — both were caught by deeper agents or
during my synthesis. But both added latency and produced a user-facing
message with a wrong assertion that had to be corrected.

## Solution

For future brainstorm sessions:

- **Grep the consuming symbol, not the feature description.** When asking
  "is X mounted/wired/enabled?", derive the specific identifier that the
  code must use to consume X (a variable name, a hook, a state field, an
  imported component) and grep for that. Absence of a generic phrase is
  not absence of functionality.

- **Check existing KB artifacts first.** Before spawning Phase 1.1 research
  agents, run one quick pass:

  ```bash
  find knowledge-base/project/brainstorms knowledge-base/project/specs \
    -maxdepth 3 -iname "*<keyword>*" 2>/dev/null | head -n 20
  ```

  If prior brainstorms/specs exist for the topic, read them and frame the
  research agents' prompts as "given these prior decisions, what's changed
  and what gaps remain?" rather than "research this topic cold."

## Key Insight

A brainstorm's quality is bounded by how well Phase 1.1 reads what's already
on disk. Two cheap local greps before spawning remote-feeling agents catch
the two failure modes that waste the most session time: wrong "not present"
claims, and ignoring your own prior work.

## Session Errors

- **False-negative on mounted feature** — Explore agent claimed chat cost
  badge was not mounted because it grepped "cost badge" (no code match).
  Actually mounted in `chat-surface.tsx` via `usageData.totalCostUsd`.
  Recovery: deeper research agent found the mount sites; I corrected the
  synthesis message. Prevention: brainstorm skill instruction edit to
  require grepping the consuming symbol (specific identifier) when making
  "is X mounted" claims, not the user-facing feature name.

- **Skipped existing brainstorm/spec check** — Prior 2026-04-10 brainstorm
  and feat-byok-cost-tracking spec existed but I spawned research without
  checking for them. Agents rediscovered them mid-session. Recovery: spec
  surfaced via research, current brainstorm references it as precursor.
  Prevention: brainstorm skill Phase 1.1 edit to add a pre-research `find`
  over `knowledge-base/project/brainstorms/` and `specs/` for topic
  keywords as the first action.

## Tags

category: process
module: brainstorm
