---
title: Brainstorm domain-leader recommendations can be overridden by later-arriving research findings — Phase 0.5/1.1 needs explicit reconciliation
date: 2026-05-15
category: process
component: plugins/soleur/skills/brainstorm
tags:
  - brainstorm
  - subagent-sequencing
  - leader-assessment
  - research-reconciliation
  - keyword-scanner
related:
  - plugins/soleur/skills/brainstorm/SKILL.md
  - knowledge-base/project/brainstorms/2026-05-15-goal-primitive-operator-escape-hatch-brainstorm.md
---

# Learning: Brainstorm leader-research sequencing and prior-art CWD

## Problem

During the `/goal`-primitive brainstorm (`2026-05-15-goal-primitive-operator-escape-hatch-brainstorm.md`), three failure modes surfaced in the brainstorm skill's Phase 0.1, 0.5, and 1.1 phases. None broke the session, but each shaped the path the brainstorm took and would have produced a worse outcome if not caught.

### Mode 1 — Leader assessments arrive before research synthesis and get overridden

Phase 0.5 (domain leaders) and Phase 1.1 (research agents) are spawned together in one `run_in_background` batch. Leaders return fast (CTO 35s, CPO 23s, CLO 28s). Research returns slow (learnings-researcher 124s, repo-research-analyst 215s).

In this brainstorm:

- **CTO recommended `test-fix-loop` as the pilot retrofit candidate** at t=35s with strong justification ("cleanest verifiable end-state, highest runaway-spend risk today").
- **Learnings-researcher at t=124s contradicted this** with evidence: `test-fix-loop/SKILL.md:48-104` already uses deterministic exit-code gates; `/goal`'s transcript-only evaluator would *duplicate* at higher cost and worse fidelity.
- **Repo-research-analyst at t=215s confirmed** Soleur's existing `plugins/soleur/hooks/stop-hook.sh` (316 LOC, ralph-loop heritage) is already the structural equivalent of `/goal` plus Jaccard / hash-repetition / idle-classifier hardening — falsifying the entire "wire it into 6 skills" premise.

The brainstorm parent had to reconcile post-hoc. Without explicit reconciliation, a more compliant model would have weaved the CTO's recommendation into the dialogue alongside the later-arriving research as if they were complementary — when they were in fact contradictory.

### Mode 2 — Stale prior-art `find` from the bare repo working tree

I ran the Phase 1.1 prior-art `find` from the bare repo root, *before* `cd`-ing into the freshly-created worktree. The find surfaced several promising learning paths:

- `2026-05-07-one-shot-stops-on-review-summary-as-pseudo-handoff.md`
- `2026-04-27-autoloop-pr-quality-failure-modes.md`
- `2026-04-02-one-shot-dead-resolve-todo-parallel-step.md`
- `2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md`

I referenced these in the research-agent prompts as established prior art to summarize. Both research agents independently reported them MISSING when operating from inside the worktree. The bare-root working tree had drifted from `origin/main` (these files exist in some other worktree, or were renamed/archived between when the bare-root was last refreshed and `origin/main` HEAD).

No false content made it into the brainstorm doc — both agents correctly reported MISSING rather than fabricating — but the prompts wasted prompt budget on instructions to "summarize a learning that doesn't exist at this revision."

### Mode 3 — Phase 0.1 keyword-scanner ambiguity on `token`

The framing-gate keyword scanner does substring match. The list includes literal `token`. The picked option label "Runaway turn/token spend" matched on the LLM-token sense, not the auth-token sense the rule was designed for. `USER_BRAND_CRITICAL=true` fired and the triad (CPO + CLO + CTO) spawned for an LLM-token billing concern.

The trigger was *correct* in this case — runaway LLM-token spend IS a brand-survival concern (single-user incident: operator's API bill spikes). The CLO returned an honest "no material legal exposure under current OSS distribution" without manufacturing concerns. The over-trigger paid for itself.

## Solution

### For Mode 1 (leader-research reconciliation)

Add an explicit reconciliation step between Phase 0.5 leader assessments and Phase 1.1 research findings. Two viable shapes:

- **Synchronous reconciliation (preferred):** the brainstorm parent waits for *both* leader and research batches to complete, then runs a single reconciliation pass surfacing contradictions before Phase 1.2 (collaborative dialogue) begins.
- **Leader-amendment prompt:** after research returns, re-prompt the leader(s) whose recommendations are contradicted by research, asking "given these research findings: <findings>, does your recommendation change?" Cost: 1 extra leader turn per contradiction.

The current skill text says "weave each leader's assessment into the brainstorm dialogue alongside repo research findings" — *weave* is too soft. Contradictions need to be named and resolved before approaches are proposed.

### For Mode 2 (prior-art `find` CWD)

The brainstorm skill's Phase 1.1 "Pre-research: check existing KB artifacts first" block should specify: run `find` *from inside the worktree* after Phase 3 worktree creation (or after the early-create at Phase 0 if `WORKTREE_CREATED_EARLY=true`). The bare-root checkout is not guaranteed to match `origin/main` and surfacing stale paths to research agents wastes prompt budget on summarize-a-missing-file instructions.

### For Mode 3 (keyword scanner)

Accept the over-trigger as defensible. The `token` literal correctly fires on both auth-token AND llm-token-spend senses; both ARE brand-survival concerns. No workflow change recommended. If future false-positives accumulate (e.g., a brainstorm where `token` matches a phrase unrelated to any brand-survival vector), revisit by splitting into `auth-token | api-token | service-token | llm-token-spend` or adding a confirmation prompt when only `token` matched and no other keyword.

## Key Insight

**Subagent sequencing within a phase shapes the recommendation that survives.** When leaders and research are spawned in the same parallel batch and the brainstorm parent processes results as they arrive, fast-returning leaders set the initial framing and slow-returning research has to dislodge it. This is structurally biased toward leader-shaped outcomes even when research evidence is stronger. The fix is not "stop parallelizing" — fan-out is cheap and right — but to add an explicit reconciliation pass before dialogue begins. *The expensive question is not how many agents to spawn; it is which agent's recommendation gets reconciled away under contradiction.*

The prior-art `find` mode is a smaller corollary of the same lesson: research-input quality depends on running from the same revision as the research-output consumers. CWD discipline matters for the agent collaboration model.

## Session Errors

1. **Prior-art `find` from bare-repo CWD surfaced paths missing from the worktree.** Recovery: research agents correctly reported MISSING; no false content propagated. Prevention: run prior-art `find` from inside the worktree (`cd .worktrees/feat-<name> && find knowledge-base/...`) after Phase 0/Phase 3 worktree creation.
2. **CTO assessment recommended `test-fix-loop` as pilot retrofit; learnings-researcher later contradicted with existing-exit-code-gate evidence.** Recovery: brainstorm parent surfaced contradiction to user and re-scoped to escape-hatch framing. Prevention: explicit reconciliation pass between Phase 0.5 leaders and Phase 1.1 research before Phase 1.2 dialogue begins.
3. **Phase 0.1 `token` keyword over-trigger on LLM-token-spend sense.** Recovery: triad fired, CLO returned honest thin-exposure assessment. Prevention: accept as defensible — runaway LLM-token spend IS brand-survival relevant. Revisit only if false-positives accumulate.

## Tags

category: process
module: brainstorm
