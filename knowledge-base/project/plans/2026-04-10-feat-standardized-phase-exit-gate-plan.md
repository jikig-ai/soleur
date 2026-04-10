---
title: "feat: standardized phase exit gate with compound/commit/clear prompt"
type: feat
date: 2026-04-10
issue: "#1931"
---

# feat: Standardized Phase Exit Gate

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 6 (Tasks 1-4, Pipeline Compatibility, Risks)
**Research sources:** 5 learnings, 4 SKILL.md files, constitution.md

### Key Improvements

1. Scoped `git add` in brainstorm exit gate to feature-specific directories (avoids staging unrelated changes)
2. Added precise pipeline detection mechanism for review skill (conversation marker + invocation chain)
3. Added compound ordering constraint: compound MUST run before commit, not after (constitution line 96)
4. Added continuation marker contract for review pipeline mode (`## Review Phase Complete`)
5. Identified that brainstorm never runs in pipeline (one-shot skips to plan) -- exit gate fires unconditionally

### New Considerations Discovered

- Constitution line 98 constrains exit gate phrasing: "Skills invoked mid-pipeline must never use stop/return/done language." The `/clear` recommendation must be advisory, not imperative.
- Ship Phase 2 already checks for recent compound output via `git log --since="1 week ago" -- knowledge-base/project/learnings/`. Double compound is a no-op, not a conflict.
- Review SKILL.md has zero pipeline detection today -- it is the highest-risk change in this feature.

## Summary

Add a standardized exit sequence to each workflow skill (brainstorm, plan, work, review) that runs compound + commit + push before handoff, then displays a `/clear` recommendation. Also verify each skill's entry reads all needed state from disk, not conversation context.

## Problem Statement

Each workflow phase accumulates significant context (agent results, dialogue, research). By the time the next phase starts, the context window is partially consumed by the previous phase's conversation. Skills read artifacts from disk on entry, so conversation context from the prior phase is redundant weight. Without a standardized exit gate, some skills commit but skip compound, others skip both, and none recommend `/clear` to free context headroom.

Source: Workflow observation during #1063 brainstorm -- context was heavy after 6 parallel domain assessments and multiple dialogue rounds.

### Research Insights: Context Window Pressure

Per the context compaction learning (2026-02-22), the plugin's baseline metadata is ~13k tokens (skills + agents). Multi-phase pipelines (brainstorm -> plan -> work -> compound -> ship) regularly hit the compaction threshold. The `/clear` recommendation directly addresses this by encouraging users to shed accumulated context between phases. Each skill already reads its needed state from disk, making conversation context from prior phases pure overhead.

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

- **work**: Already has pipeline detection ("If invoked by one-shot" at line 425 of SKILL.md). The exit gate wraps the existing direct-invocation path only. One-shot path emits `## Work Phase Complete` marker.
- **review**: Needs pipeline detection (currently has NONE). If invoked by work's Phase 4 chain or by one-shot (step 4), skip the exit gate. Detection: check if the conversation contains `skill: soleur:work` or `soleur:one-shot` invocation earlier.
- **brainstorm**: Never runs inside a pipeline. One-shot routes directly to plan, skipping brainstorm entirely (brainstorm Phase 0 offers one-shot as an escape hatch, but one-shot never invokes brainstorm). Exit gate always fires.
- **plan**: Has existing pipeline detection via `$ARGUMENTS` file path check (line 99 of SKILL.md). When running as a one-shot subagent, it returns via a structured return contract. The exit gate does not fire.

### Research Insight: Pipeline Handoff Language

Per constitution line 98 and learnings 2026-03-02 and 2026-03-03, skills invoked mid-pipeline must never use stop/return/done language in their handoff. The exit gate's `/clear` recommendation must be phrased as advisory text that does NOT imply end-of-turn. Specifically:

- Do NOT write: "Run `/clear` and stop." (implies turn boundary)
- Do NOT write: "Announce to the user that context is heavy." (triggers turn-ending behavior)
- DO write: "Display: ..." followed by the next instruction (advisory, non-blocking)

### Compound Ordering Constraint

Per constitution line 96: "Run code review and compound before committing -- the commit is the gate, not the PR; compound must never be placed after `git push` or CI because compound produces a commit that invalidates CI and creates an infinite loop."

This means the exit gate sequence MUST be: compound first, then commit+push. Compound itself may produce a commit (learning file), so the exit gate commit covers both the skill's artifacts AND compound's output.

### Constraint: `/clear` Is User-Only

`/clear` is a built-in Claude Code CLI command. It cannot be invoked programmatically by tools, skills, or hooks. The exit gate can only RECOMMEND it -- the user must type it themselves.

## Implementation Plan

### Task 1: Add Exit Gate to brainstorm/SKILL.md

**File:** `plugins/soleur/skills/brainstorm/SKILL.md`

**Location:** Phase 4: Handoff -- insert the exit gate sequence BEFORE the AskUserQuestion options.

**Changes:**

1. Before the "Context headroom notice" line (which already exists at line 303), insert compound invocation:

   ```text
   **Exit gate sequence:**

   1. Run `skill: soleur:compound` to capture learnings from the brainstorm session.
      If compound finds nothing to capture, it will skip gracefully.
   2. Commit and push any remaining uncommitted artifacts. Scope git add to
      feature-specific directories only (do NOT use `git add -A knowledge-base/`
      which could stage unrelated changes from other worktrees or manual edits):
      ```bash
      git add knowledge-base/project/brainstorms/ knowledge-base/project/specs/feat-<name>/
      git status --short
      ```

      If there are staged changes, commit with `git commit -m "docs: brainstorm artifacts for feat-<name>"` and `git push`.
      If push fails (no network), warn and continue.

   ```

2. The existing "Context headroom notice" line already says: "All artifacts are on disk. Starting a new session for `/soleur:plan` will give you maximum context headroom." Replace the full line with:

   ```text
   "All artifacts are on disk. Run `/clear` then `/soleur:plan` for maximum context headroom."
   ```

**Note:** Brainstorm already commits in Phase 3.6. The exit gate commit is a safety net for any artifacts created after Phase 3.6 (e.g., deferred issue creation in Phase 3.6 step 7, or domain assessments that added content). Compound runs BEFORE the commit per constitution line 96 (compound may produce a learning file that should be included in the commit).

### Research Insight: Brainstorm Is Never Pipeline-Invoked

One-shot (SKILL.md line 8-9) starts at step 0 and goes directly to plan -- it never invokes brainstorm. Brainstorm's Phase 0 offers one-shot as an escape hatch (line 55-59), but the reverse does not happen. Therefore the exit gate fires unconditionally -- no pipeline detection needed.

### Task 2: Add Exit Gate to plan/SKILL.md

**File:** `plugins/soleur/skills/plan/SKILL.md`

**Location:** Between the "Plan Review" section and the "Post-Generation Options" section (around line 435).

**Changes:**

1. Plan already has pipeline detection via `$ARGUMENTS` file path check (line 99 of SKILL.md: "If `$ARGUMENTS` contains a file path..."). However, the one-shot subagent invocation path is more nuanced -- the plan subagent receives arguments via a Task delegation with a return contract (one-shot SKILL.md lines 33-64). The exit gate should check:
   - If the conversation contains a Task delegation with `RETURN CONTRACT` text, this is a subagent -- skip exit gate
   - If `$ARGUMENTS` is a plain text description (direct user invocation) -- run exit gate

2. For direct invocation, insert AFTER "Plan Review" and BEFORE "Post-Generation Options":

   ```text
   ## Exit Gate (direct invocation only)

   **Pipeline detection:** If this skill is running inside a Task subagent (the conversation
   contains a `RETURN CONTRACT` section from a Task delegation), skip the exit gate entirely.
   Return the plan file path per the return contract. The calling pipeline handles compound
   and lifecycle progression.

   **If invoked directly by the user:**

   1. Run `skill: soleur:compound` to capture learnings from the planning session.
      If compound finds nothing to capture, it will skip gracefully.
   2. Verify all plan artifacts are committed and pushed. The Save Tasks section already
      committed the plan file and tasks.md. Run `git status --short` to check for any
      remaining uncommitted changes. If found:
      ```bash
      git add knowledge-base/project/plans/ knowledge-base/project/specs/feat-<name>/
      git commit -m "docs: plan artifacts for feat-<name>"
      git push
      ```

      If push fails (no network), warn and continue.
   3. Display: "All artifacts are on disk. Run `/clear` then `/soleur:work` for maximum
      context headroom."

   ```

3. Update the Post-Generation Options question text to reinforce the `/clear` recommendation:

   Current: `"Plan reviewed and ready at..."`
   Updated: `"Plan reviewed and ready at... Context is saved to disk -- run /clear before /soleur:work for maximum headroom."`

### Research Insight: Plan's Existing Commit

The plan's "Save Tasks to Knowledge Base" section (around line 403-413) already runs `git add` + `git commit` + `git push` for plan artifacts. The exit gate's commit step is a safety net that catches any changes from the plan review process (reviewers may propose edits applied after the initial commit). The exit gate commit uses `git status --short` as a guard -- if the save section already committed everything, the exit gate finds nothing to commit and moves on.

### Task 3: Add Exit Gate to work/SKILL.md

**File:** `plugins/soleur/skills/work/SKILL.md`

**Location:** Phase 4: Handoff -- the direct-invocation path (lines 427-433).

**Changes:**

1. Work's Phase 4 direct-invocation path (line 427) already runs:
   - Step 1: `skill: soleur:review`
   - Step 2: `skill: soleur:resolve-todo-parallel`
   - Step 3: `skill: soleur:compound`
   - Step 4: `skill: soleur:ship`

   This chain IS the exit gate for work. Compound runs (step 3), ship handles commit+push+PR (step 4). The only missing piece is the `/clear` recommendation.

2. **Chosen approach:** Add a non-blocking advisory line after compound (step 3) and before ship (step 4):

   ```text
   3.5. Display: "Tip: After shipping, run `/clear` to reclaim context headroom for the next task."
   ```

   This is advisory, non-blocking, and does NOT break the automatic chain. The model outputs the tip as a single line and immediately proceeds to ship. It does NOT use "announce", "stop", or "return" language (per constitution line 98 and learnings 2026-03-02).

3. The one-shot path (line 425) remains unchanged -- it emits `## Work Phase Complete` marker and continues to one-shot step 4. No exit gate fires in pipeline mode.

### Research Insight: Work Already Has the Full Exit Gate

Work is the only skill that already runs all three exit gate components (compound, commit, push) via its Phase 4 chain. The change for work is minimal -- just the `/clear` advisory. This confirms the plan's design: the exit gate is about consistency across skills, not adding new capabilities to work.

### Research Insight: Do NOT Insert a Blocking Prompt

Per learning 2026-03-02: "any phrasing that implies user-facing output is interpreted as a terminal action." The advisory line MUST be followed by the next instruction (`skill: soleur:ship`) in the same paragraph or section. Do not place it in its own AskUserQuestion block or suggest the user should decide whether to `/clear` before ship runs.

### Task 4: Add Exit Gate to review/SKILL.md

**File:** `plugins/soleur/skills/review/SKILL.md`

**Location:** After the Summary Report in Step 5 (Findings Synthesis), at the end of the "Step 3: Summary Report" section (after the severity breakdown and before "### 7. End-to-End Testing").

**Changes:**

1. Add pipeline detection. Review currently has ZERO pipeline awareness -- this is the highest-risk edit. The detection mechanism mirrors work's pattern (line 425 of work/SKILL.md):

   ```text
   ### 6. Exit Gate

   **Pipeline detection:** If the conversation contains `skill: soleur:work` output earlier (indicating review was invoked by work's Phase 4 chain) or `soleur:one-shot` output (indicating review was invoked by one-shot step 4), skip the exit gate. The calling pipeline handles compound, commit, and lifecycle progression.

   **If invoked directly by the user** (no work or one-shot orchestrator in the conversation):
   ```

   The detection is conversation-based, not argument-based, because work invokes review via the Skill tool without special arguments. The presence of prior work/one-shot output is the reliable signal.

2. For direct invocation (user ran `/soleur:review` standalone), add:

   ```text
   **Exit gate sequence (direct invocation only):**

   1. Run `skill: soleur:compound` to capture learnings from the review session.
      If compound finds nothing to capture, it will skip gracefully.
   2. Commit any local artifacts. GitHub issues are already created remotely,
      but local files may have been modified (plan updates, todo resolutions).
      Run `git status --short`. If there are changes:
      ```bash
      git add <changed files>
      git commit -m "docs: review artifacts for feat-<name>"
      git push
      ```

      If push fails (no network), warn and continue.
   3. Display: "Review complete. All findings are tracked as GitHub issues.
      Run `/clear` then `/soleur:work` or `/soleur:ship` for maximum context headroom."

   ```

3. Add a note after the pipeline detection block: "When review is invoked by work or one-shot, the calling pipeline handles compound and commit. Do not duplicate these steps."

### Research Insight: Review Handoff Language

Per the skill handoff learnings (2026-03-02, 2026-03-03), the exit gate text must NOT use "announce", "return control", or "stop" language. The display instruction is advisory. After displaying the `/clear` recommendation, present the End-to-End Testing option (Phase 7) as normal. The exit gate does not replace the existing flow -- it inserts before it.

### Edge Case: Review Creates No Local Files

Review's primary output is GitHub issues (created via `gh issue create`). These are remote-only. The `git status --short` check in the exit gate may find nothing to commit, which is the expected case. The commit step must handle the empty case gracefully (check before committing, do not error on "nothing to commit").

### Task 5: Verify Entry Robustness (Audit Only)

Verify each skill's entry reads all needed state from disk. Based on the Current State Analysis above, all four skills already load from disk. The only minor gap:

- **review**: Does not load `constitution.md` on entry. This is acceptable -- review operates on code diffs and PR metadata, not project conventions. The review agents load their own conventions. No change needed.

**No code changes for this task** -- just verification that the current entry behavior is robust. Document the audit finding in the plan.

### Task 6: Update constitution.md

Add the exit gate convention to `knowledge-base/project/constitution.md` under Architecture > Always section. Insert after line 98 (the "Skills invoked mid-pipeline must never use stop/return/done language" rule) since the new rule is a companion to it:

```text
- Workflow skills (brainstorm, plan, work, review) must run compound + commit + push before presenting handoff options to the user -- skip the exit gate when invoked by a pipeline orchestrator (one-shot, ship); display a `/clear` recommendation at handoff to encourage context headroom recovery between phases
```

This goes in constitution.md (not AGENTS.md) because:

- It is a structural convention enforced by skill instructions, not a hard rule that the agent would violate without being told every turn
- It is on-demand context (loaded by skills when they start), not always-loaded context
- AGENTS.md already has the compound-before-commit rule (line 96 equivalent); constitution.md gets the broader exit gate pattern

### Research Insight: Rule Relationship to Existing Rules

The new rule complements three existing constitution rules:

1. **Line 96:** "Run code review and compound before committing" -- the exit gate operationalizes this per-skill
2. **Line 98:** "Skills invoked mid-pipeline must never use stop/return/done language" -- the exit gate's pipeline detection implements this
3. **Line 90:** "Lifecycle workflows with hooks must cover every state transition" -- the exit gate closes the handoff gap between phases

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
| Double compound (exit gate + ship) | Low -- redundant work | Ship Phase 2 checks `git log --since="1 week ago" -- knowledge-base/project/learnings/`; deduplication built-in |
| Exit gate commit conflicts with prior commits | Low | Exit gate uses `git status --short` check first; only commits if changes exist |
| Review exit gate fires in pipeline mode | High -- review currently has zero pipeline detection | Conversation-based detection (check for prior work/one-shot output); test Scenario 7 specifically |
| Exit gate `/clear` text triggers turn-ending | Medium -- model stops before next step | Use advisory phrasing per constitution line 98; no "announce", "stop", "return" language |
| Scoped `git add` misses new directories | Low -- artifacts not committed | List explicit paths for each skill (brainstorms/, specs/, plans/); git add is idempotent on already-committed files |

## Implementation Order

1. Task 5 (audit entry robustness -- verification only)
2. Task 1 (brainstorm exit gate -- simplest, no pipeline concern)
3. Task 4 (review exit gate -- add pipeline detection)
4. Task 2 (plan exit gate -- pipeline detection for subagent mode)
5. Task 3 (work exit gate -- minimal change, advisory only)
6. Task 6 (constitution update -- after all skills are consistent)
