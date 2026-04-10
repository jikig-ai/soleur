---
title: "feat: standardized phase exit gate with compound/commit/clear prompt"
type: feat
date: 2026-04-10
issue: "#1931"
---

# feat: Standardized Phase Exit Gate

## Summary

Add a standardized exit sequence to each workflow skill (brainstorm, plan, work, review) that runs compound + commit + push before handoff, then displays a `/clear` recommendation. Also verify each skill's entry reads all needed state from disk, not conversation context.

## Problem Statement

Each workflow phase accumulates significant context (agent results, dialogue, research). By the time the next phase starts, the context window is partially consumed by the previous phase's conversation. Skills read artifacts from disk on entry, so conversation context from the prior phase is redundant weight. Without a standardized exit gate, some skills commit but skip compound, others skip both, and none recommend `/clear` to free context headroom.

Source: Workflow observation during #1063 brainstorm -- context was heavy after 6 parallel domain assessments and multiple dialogue rounds.

## Current State Analysis

### Exit Behavior (what happens at handoff)

| Skill | Compound | Commit + Push | `/clear` Recommendation | Pipeline-Aware |
|-------|----------|---------------|------------------------|----------------|
| brainstorm | No | Yes (Phase 3.6) | No | N/A (never in pipeline) |
| plan | No | Yes (Save Tasks section) | No | Yes (pipeline detection for subagent) |
| work | Yes (Phase 4, direct mode) | Yes (Phase 4, direct mode) | No | Yes (one-shot emits marker) |
| review | No | No | No | No |

### Entry Behavior (what it reads from disk)

| Skill | Reads CLAUDE.md | Reads Constitution | Reads Prior Artifacts | Reads Spec/Tasks | Gap |
|-------|----------------|-------------------|-----------------------|-------------------|-----|
| brainstorm | Yes (Phase 0) | No (not needed) | No (first phase) | No (first phase) | None |
| plan | Yes (Phase 0) | Yes (Phase 0) | Yes (brainstorm in Phase 0.5) | Yes (spec in Phase 0) | None |
| work | Yes (Phase 0) | Yes (Phase 0) | Yes (plan in Phase 1) | Yes (tasks in Phase 0) | None |
| review | Yes (Phase 0) | No | PR metadata via `gh` | No | Minor: does not load constitution |

## Proposed Changes

### Design Principle: Exit Gate Sequence

Each skill's handoff section gets a standardized exit gate that runs BEFORE presenting next-step options. The sequence is:

1. **Compound** -- run `skill: soleur:compound` to capture learnings (skip if nothing to capture)
2. **Commit + Push** -- ensure all artifacts are committed and pushed to remote
3. **Context Headroom Notice** -- display: "All artifacts are on disk. Starting a new session for `/soleur:<next-phase>` gives maximum context headroom. Run `/clear` then invoke the next skill."

### Pipeline Compatibility (Critical Constraint)

The exit gate MUST NOT fire when the skill is invoked by a pipeline orchestrator (one-shot, ship). Pipeline orchestrators handle compound/commit/push themselves. Detection mechanism:

- **work**: Already has pipeline detection ("If invoked by one-shot"). The exit gate wraps the existing direct-invocation path only.
- **review**: Needs pipeline detection. If invoked by one-shot or work's Phase 4 chain, skip the exit gate.
- **brainstorm**: Never runs inside a pipeline. Exit gate always fires.
- **plan**: When running as a one-shot subagent (detected by Task context or plan file path argument), skip the interactive exit gate. The subagent returns the plan file path via its return contract.

### Constraint: `/clear` Is User-Only

`/clear` is a built-in Claude Code CLI command. It cannot be invoked programmatically by tools, skills, or hooks. The exit gate can only RECOMMEND it -- the user must type it themselves.

## Implementation Plan

### Task 1: Add Exit Gate to brainstorm/SKILL.md

**File:** `plugins/soleur/skills/brainstorm/SKILL.md`

**Location:** Phase 4: Handoff -- insert the exit gate sequence BEFORE the AskUserQuestion options.

**Changes:**

1. Before the "Context headroom notice" line (which already exists at line ~304), insert compound invocation:

   ```text
   **Exit gate sequence:**

   1. Run `skill: soleur:compound` to capture learnings from the brainstorm session.
      If compound finds nothing to capture, it will skip gracefully.
   2. Commit and push any remaining uncommitted artifacts:
      ```bash
      git add -A knowledge-base/
      git status --short
      ```
      If there are changes, commit with `git commit -m "docs: brainstorm artifacts for feat-<name>"` and `git push`.
      If push fails (no network), warn and continue.
   ```

2. The existing "Context headroom notice" line already says: "All artifacts are on disk. Starting a new session for `/soleur:plan` will give you maximum context headroom." Enhance it to explicitly recommend `/clear`:

   ```text
   "All artifacts are on disk. Run `/clear` then `/soleur:plan` for maximum context headroom."
   ```

**Note:** Brainstorm already commits in Phase 3.6. The exit gate commit is a safety net for any artifacts created after Phase 3.6 (e.g., deferred issue creation in Phase 3.6 step 7, or domain assessments that added content).

### Task 2: Add Exit Gate to plan/SKILL.md

**File:** `plugins/soleur/skills/plan/SKILL.md`

**Location:** Post-Generation Options section -- insert exit gate BEFORE the AskUserQuestion.

**Changes:**

1. Add pipeline detection. If the plan skill is running inside a one-shot subagent (the conversation contains a Task delegation with a return contract), skip the exit gate and return the plan file path per the return contract.

2. For direct invocation, insert before the Post-Generation Options AskUserQuestion:

   ```text
   **Exit gate sequence (direct invocation only):**

   1. Run `skill: soleur:compound` to capture learnings from the planning session.
      If compound finds nothing to capture, it will skip gracefully.
   2. Verify all plan artifacts are committed and pushed (plan file + tasks.md were
      already committed in the Save Tasks section). Run `git status --short` to check
      for any uncommitted changes. If found, commit and push.
   3. Display: "All artifacts are on disk. Run `/clear` then `/soleur:work` for maximum
      context headroom."
   ```

3. Update the Post-Generation Options question text to include the `/clear` recommendation in the preamble.

**Pipeline mode:** When plan is invoked as a subagent (one-shot Steps 1-2), it already returns via a structured return contract. The exit gate does not fire. The subagent commits plan artifacts as part of its normal flow.

### Task 3: Add Exit Gate to work/SKILL.md

**File:** `plugins/soleur/skills/work/SKILL.md`

**Location:** Phase 4: Handoff -- the direct-invocation path.

**Changes:**

1. Work's Phase 4 direct-invocation path already runs review + resolve-todo + compound + ship. This IS the exit gate. The missing piece is the `/clear` recommendation.

2. After the compound step (step 3 in Phase 4's direct-invocation sequence) and before the ship step (step 4), add:

   ```text
   3.5. Display: "Implementation and review complete. All artifacts are on disk.
        If context is heavy, run `/clear` then `/soleur:ship` for maximum headroom.
        Otherwise, ship will run next automatically."
   ```

   However, this creates a problem: it would break the automatic flow from compound to ship. The user would need to explicitly continue.

   **Better approach:** Add the `/clear` recommendation ONLY if the user declines to proceed immediately. Since work's Phase 4 already chains review -> compound -> ship automatically, the `/clear` prompt should appear only if one of these steps fails or the user interrupts.

   **Revised approach:** After compound completes (step 3), if the session has consumed significant context (heuristic: conversation has had context compaction), display the `/clear` recommendation as an advisory note but continue to ship automatically. The note would say: "Context headroom is low. After this session, consider running `/clear` before your next task."

   **Simplest correct approach:** Keep the current automatic chain (review -> compound -> ship) intact. Add a single line after compound completes: "Tip: After shipping, run `/clear` to reclaim context headroom for the next task." This is advisory, non-blocking, and applies to the post-ship state.

3. The one-shot path remains unchanged (emits `## Work Phase Complete` marker).

### Task 4: Add Exit Gate to review/SKILL.md

**File:** `plugins/soleur/skills/review/SKILL.md`

**Location:** After Step 5 (Findings Synthesis and GitHub Issue Creation), at the end of the skill.

**Changes:**

1. Add pipeline detection. If review was invoked by work's Phase 4 chain or by one-shot (step 4), skip the exit gate. Detection: check if the conversation contains `skill: soleur:work` invocation earlier, or one-shot markers.

2. For direct invocation (user ran `/soleur:review` standalone), add after the Summary Report:

   ```text
   **Exit gate sequence (direct invocation only):**

   1. Run `skill: soleur:compound` to capture learnings from the review session.
      If compound finds nothing to capture, it will skip gracefully.
   2. Commit review artifacts (GitHub issues are already created remotely).
      Run `git status --short`. If local changes exist, commit and push.
   3. Display: "Review complete. All findings are tracked as GitHub issues.
      Run `/clear` then `/soleur:work` or `/soleur:ship` for maximum context headroom."
   ```

3. Add a note that when review is invoked by work or one-shot, the calling pipeline handles compound and commit.

### Task 5: Verify Entry Robustness (Audit Only)

Verify each skill's entry reads all needed state from disk. Based on the Current State Analysis above, all four skills already load from disk. The only minor gap:

- **review**: Does not load `constitution.md` on entry. This is acceptable -- review operates on code diffs and PR metadata, not project conventions. The review agents load their own conventions. No change needed.

**No code changes for this task** -- just verification that the current entry behavior is robust. Document the audit finding in the plan.

### Task 6: Update AGENTS.md (if needed)

If the exit gate pattern warrants a new rule or convention, add it to AGENTS.md or constitution.md. Candidate rule:

```text
- Workflow skills (brainstorm, plan, work, review) must run compound + commit + push
  before presenting handoff options to the user. Skip the exit gate when invoked by a
  pipeline orchestrator (one-shot, ship). Display a `/clear` recommendation at handoff.
```

This would go in constitution.md under Architecture > Always, since it is a structural convention enforced by skill instructions (not a hook).

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Automatic `/clear` via hook | Fully automated, no user action needed | `/clear` is a built-in CLI command, cannot be invoked programmatically | Rejected |
| Exit gate in every skill | Consistent | Breaks pipeline mode for work/review | Rejected without pipeline detection |
| Exit gate with pipeline detection | Correct in all modes | Slightly more complex skill instructions | **Chosen** |
| PostToolUse hook that detects skill completion | Centralized enforcement | Hooks run on tool calls, not on skill completion | Rejected -- wrong abstraction layer |

## Non-Goals

- Automating `/clear` -- it is a user-invoked CLI command by design
- Modifying one-shot pipeline -- it already handles compound/commit/push correctly
- Adding compound to review when called by work -- work's Phase 4 already handles compound
- Restructuring the skill handoff architecture -- this is a targeted addition to existing patterns

## Acceptance Criteria

- [ ] Each workflow skill (brainstorm, plan, work, review) runs compound before handoff in direct invocation mode
- [ ] Each skill commits and pushes all artifacts before presenting next-step options
- [ ] Each skill displays a `/clear` recommendation at handoff
- [ ] Exit gate does NOT fire when a skill is invoked by a pipeline orchestrator (one-shot, ship)
- [ ] Each skill's entry reads all needed state from disk (verified by audit -- no changes needed)
- [ ] No regression in one-shot pipeline (work emits `## Work Phase Complete` correctly, plan returns via subagent contract)
- [ ] Compound does not block if it finds nothing to capture

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a plugin-architecture change affecting skill instructions only. No infrastructure, no user-facing UI, no external services. The CTO concern is pipeline compatibility -- the exit gate must not break one-shot's continuation markers or work's automatic review-compound-ship chain. This is addressed by the pipeline detection mechanism in each skill.

## Test Scenarios

### Scenario 1: brainstorm direct invocation

- Run `/soleur:brainstorm` with a feature description
- Complete brainstorm through Phase 4
- Verify: compound runs, artifacts commit+push, `/clear` recommendation displays
- Verify: AskUserQuestion options still appear after exit gate

### Scenario 2: plan direct invocation

- Run `/soleur:plan` with a feature description
- Complete plan through Post-Generation Options
- Verify: compound runs, artifacts commit+push, `/clear` recommendation displays
- Verify: post-generation options still work

### Scenario 3: plan in one-shot subagent

- Run `/soleur:one-shot`
- Verify: plan subagent does NOT run compound or display `/clear`
- Verify: plan subagent returns plan file path via return contract

### Scenario 4: work direct invocation

- Run `/soleur:work` with a plan file
- Complete work through Phase 4
- Verify: existing review-compound-ship chain still works
- Verify: `/clear` advisory appears after compound

### Scenario 5: work in one-shot

- Run `/soleur:one-shot`
- Verify: work emits `## Work Phase Complete` marker
- Verify: one-shot continues to step 4 (review) without interruption

### Scenario 6: review direct invocation

- Run `/soleur:review` standalone
- Complete review through findings synthesis
- Verify: compound runs, `/clear` recommendation displays
- Verify: GitHub issues still created correctly

### Scenario 7: review in pipeline (via work Phase 4)

- Run `/soleur:work` which chains to review
- Verify: review does NOT run its own compound or display `/clear`
- Verify: work's Phase 4 handles compound after review completes

## Files to Modify

| File | Change Type | Description |
|------|------------|-------------|
| `plugins/soleur/skills/brainstorm/SKILL.md` | Edit | Add compound invocation and `/clear` recommendation to Phase 4 |
| `plugins/soleur/skills/plan/SKILL.md` | Edit | Add exit gate with pipeline detection to Post-Generation Options |
| `plugins/soleur/skills/work/SKILL.md` | Edit | Add `/clear` advisory after compound in Phase 4 direct path |
| `plugins/soleur/skills/review/SKILL.md` | Edit | Add exit gate with pipeline detection after findings synthesis |
| `knowledge-base/project/constitution.md` | Edit | Add exit gate convention to Architecture > Always |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Exit gate breaks one-shot pipeline | High -- pipeline stalls | Pipeline detection in each skill; test Scenario 3, 5, 7 |
| Compound takes too long at handoff | Medium -- user impatience | Compound skips gracefully if nothing to capture |
| Double compound (exit gate + ship) | Low -- redundant work | Ship Phase 2 already checks for recent compound; deduplication built-in |
| Exit gate commit conflicts with prior commits | Low | Exit gate uses `git status --short` check first; only commits if changes exist |

## Implementation Order

1. Task 5 (audit entry robustness -- verification only)
2. Task 1 (brainstorm exit gate -- simplest, no pipeline concern)
3. Task 4 (review exit gate -- add pipeline detection)
4. Task 2 (plan exit gate -- pipeline detection for subagent mode)
5. Task 3 (work exit gate -- minimal change, advisory only)
6. Task 6 (constitution update -- after all skills are consistent)
