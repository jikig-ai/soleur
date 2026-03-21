---
title: "Linearize Multi-Step LLM Prompts to Prevent Deferred Instruction Failures"
date: 2026-03-16
category: prompt-engineering
tags: [ci-cd, claude-code-action, sequential-execution, prompt-structure]
symptoms: "LLM agent executes a deferred NOTE immediately instead of waiting, or forgets it entirely by the time the target step arrives"
module: scheduled-workflows
synced_to: knowledge-base/project/constitution.md
---

# Learning: Linearize Multi-Step LLM Prompts to Prevent Deferred Instruction Failures

## Problem

When writing multi-step LLM prompt instructions (e.g., for CI workflows via claude-code-action), placing a deferred instruction inside an earlier step -- a "NOTE: do this later" pattern -- creates unreliable execution. LLM agents executing sequential prompts frequently either (a) execute deferred instructions immediately at the point of reading, or (b) forget them entirely by the time the target step arrives.

### Concrete Example

The content generator plan proposed this structure inside STEP 1:

```
STEP 1 — Select topic from queue:
  ...
  If ALL items already have a generated_date:
    STEP 1b — Discover new topic via growth plan:
    ...
    NOTE: After STEP 4 validation succeeds (and before STEP 6), also
    append the discovered topic to seo-refresh-queue.md.
```

The NOTE asks the agent to remember an action from STEP 1, skip past STEP 2/3/4, and execute it between STEP 4 and STEP 6 -- 50+ lines and several tool invocations later. This is a temporal forward-reference: the instruction appears in the prompt at position N but must execute at position N+4.

### Why This Fails

1. **Working memory decay.** LLM context windows are large but attention is not uniform. Instructions encountered early and tagged as "later" compete with the immediate instructions of STEP 2, 3, 4. By STEP 5, the agent has processed hundreds of tokens of unrelated instructions and tool outputs.

2. **Eager execution bias.** LLMs are completion-oriented. When they encounter an actionable instruction ("append the discovered topic to the queue"), the default behavior is to act on it. The "NOTE: After STEP 4" qualifier is a weak signal competing against a strong action verb.

3. **No persistent scratchpad.** Unlike a human who can write "TODO: do X after step 4" on a sticky note, an LLM agent's "memory" of deferred work exists only as attention weights over prior context -- there is no reliable deferred execution mechanism.

## Solution

**Linearize all instructions in chronological execution order.** Move every deferred instruction to the step where it actually executes, using conditional blocks to handle path-dependent behavior.

### The Fix

The implemented workflow replaced the NOTE with a dedicated STEP 5 at the correct execution point:

```
STEP 5 — Record topic in queue:
If STEP 1b was used (topic was auto-discovered via growth plan):
  Append the discovered topic to seo-refresh-queue.md under a
  "## Auto-Discovered Topics" section...

If a queue item was used (normal path):
  Edit seo-refresh-queue.md and add "generated_date: <today>" annotation
  to the queue item that was just written.
```

This is a conditional block at the correct position -- no forward-references, no deferred instructions. Both code paths (fallback and normal) are handled where they execute.

## Best Practices for Multi-Step LLM Prompts

### 1. Chronological Ordering Rule

Every instruction must appear at the step where it executes, not where it is conceptually related. If an instruction is triggered by a condition in STEP 1 but executes after STEP 4, it belongs in STEP 5 with a conditional check ("If STEP 1b was used").

**Anti-pattern:** `STEP 1: ... NOTE: remember to do X after STEP 4`
**Correct pattern:** `STEP 5: If <condition from STEP 1>, do X`

### 2. When to Use Conditional Blocks vs. Deferred Instructions

Use **conditional blocks** (always):

- When an earlier step sets a condition that affects a later step
- When different execution paths converge at a common step
- When the deferred action has side effects (file writes, API calls, git operations)

Use **deferred instructions** (never in LLM prompts):

- This pattern has no reliable use case in LLM sequential prompts. Even for simple "remember this value" scenarios, the conditional block pattern is more reliable because it places the instruction at the point of execution.

### 3. State Propagation Without Forward-References

When STEP 1 makes a decision that STEP 5 needs to know about, use one of these patterns:

**Pattern A -- Conditional check at execution point (preferred):**

```
STEP 5: If STEP 1b was used (topic was auto-discovered), do X.
        If a queue item was used (normal path), do Y.
```

**Pattern B -- Explicit state variable (for complex flows):**

```
STEP 1: ... Set TOPIC_SOURCE to "growth-plan" or "seo-queue".
STEP 5: If TOPIC_SOURCE is "growth-plan", do X. Otherwise, do Y.
```

Both patterns keep the instruction at the execution point. Pattern B is useful when the condition is complex or referenced by multiple later steps.

### 4. Prompt Structure Review Checklist

When reviewing multi-step LLM prompts (workflow files, skill instructions, agent prompts), check for these anti-patterns:

- [ ] **Forward-reference scan:** Search for "NOTE:", "IMPORTANT:", "Remember:", "After STEP", "Before STEP", "Later,". Any instruction that references a step number higher than its own is a deferred instruction that should be relocated.
- [ ] **Temporal word scan:** Search for "after", "before", "later", "eventually", "once STEP N completes". These signal out-of-order placement.
- [ ] **Nesting depth check:** Instructions nested 2+ levels inside a conditional block of a different step are likely misplaced. If STEP 1 has a conditional that contains instructions for STEP 5, extract them.
- [ ] **Execution order trace:** Read the prompt linearly and ask "can the agent execute each instruction the moment it reads it?" If not, the instruction is deferred and should be moved.
- [ ] **Convergence point check:** When two paths (e.g., queue-sourced vs. auto-discovered) eventually need different handling at the same step, verify that step has explicit conditional blocks for both paths -- not just a NOTE in one path.
- [ ] **Side-effect placement:** Every instruction that writes to a file, calls an API, or creates an issue must appear at the step where the write/call/create should happen, not at the step where the decision to do it is made.

## Prevention

- Add the chronological ordering rule to constitution.md under "Code Style > Always" for LLM prompt instructions
- When writing multi-step prompts, draft in execution order first, then review for forward-references
- During plan review, flag any "NOTE: do X after STEP N" as a linearization defect before implementation begins
- The compound review checklist should include a forward-reference scan for any PR that modifies workflow prompt blocks

## Related Learnings

- `2026-03-16-scheduled-skill-wrapping-pattern.md` -- The parent feature where this pattern was discovered
- `2026-03-12-llm-as-script-pattern-for-ci-file-generation.md` -- LLM prompt structure for CI workflows
- `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md` -- All persistence inside agent prompt (related: instructions must be self-contained)

## Tags

category: prompt-engineering
module: scheduled-workflows, ci-cd
