---
module: System
date: 2026-04-12
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "One-shot pipeline stops after work skill outputs ## Work Phase Complete"
  - "Steps 4-10 (review, QA, compound, ship) are skipped"
root_cause: logic_error
resolution_type: workflow_improvement
severity: high
tags: [one-shot, pipeline, work-skill, handoff, contradictory-instructions]
synced_to: [work]
---

# Troubleshooting: Contradictory One-Shot Handoff Instructions Stop Pipeline

## Problem

The work skill's Phase 4 one-shot handoff contained contradictory instructions that caused the agent to stop after outputting `## Work Phase Complete` instead of continuing the pipeline. Steps 4-10 (review, QA, compound, ship, test-browser, feature-video) were skipped.

## Environment

- Module: System (skill orchestration)
- Affected Component: `plugins/soleur/skills/work/SKILL.md` Phase 4
- Date: 2026-04-12

## Symptoms

- One-shot pipeline stops after work skill outputs `## Work Phase Complete`
- Steps 4-10 (review, QA, compound, ship) are skipped
- Agent interprets the marker as a stopping point despite continuation gate

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt once the user reported the stop.

## Session Errors

**setup-ralph-loop.sh wrong path** -- Tried `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` which doesn't exist.

- **Recovery:** Found correct path at `./plugins/soleur/scripts/setup-ralph-loop.sh`
- **Prevention:** The one-shot SKILL.md already has the correct path; the error was in interpreting the skill instructions.

**Dev server startup failure** -- Supabase env vars missing from Doppler dev config.

- **Recovery:** QA skipped browser scenarios per graceful degradation rules.
- **Prevention:** Add `SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_URL` to Doppler dev config, or document this as a known limitation for local QA.

**git add from wrong directory** -- Ran `git add apps/web-platform/test/chat-input.test.tsx` from the `apps/web-platform/` subdirectory instead of the worktree root.

- **Recovery:** Re-ran from the worktree root.
- **Prevention:** Always run git commands from the worktree root, not subdirectories.

## Solution

Rewrote two lines in `plugins/soleur/skills/work/SKILL.md`:

**Before (broken):**

```markdown
**If invoked by one-shot** (the conversation contains `soleur:one-shot` skill output earlier):
Do not invoke ship, review, or compound — the orchestrator handles those. Output exactly
`## Work Phase Complete` (this is a continuation marker, NOT a turn-ending statement) and
then **immediately continue executing the next numbered step in the one-shot sequence**
(step 4: review). Do NOT end your turn after outputting this marker.
```

**After (fixed):**

```markdown
**If invoked by one-shot** (the conversation contains `soleur:one-shot` skill output earlier):
Output exactly `## Work Phase Complete` and then **immediately invoke** `skill: soleur:review`
(step 4 of the one-shot sequence). Do NOT end your turn after outputting the marker — you ARE
the orchestrator, so you must continue executing one-shot steps 4 through 10 in order. The
marker is a progress signal, not a stopping point.
```

Also updated the Quality Checklist afterword from "the orchestrator handles" to "the same agent continues executing one-shot steps 4-10".

## Why This Works

The root cause was a **contradictory prohibition**: sentence 1 said "Do not invoke review" while sentence 2 said "immediately continue to review step." The agent followed the prohibition (sentence 1) and stopped.

The fix removes the prohibition entirely and replaces it with an explicit invocation instruction. It also clarifies identity: "you ARE the orchestrator" eliminates the ambiguity about whether "the orchestrator" is a separate entity.

This is the third instance of the "pipeline stops at skill boundary" failure class:

1. 2026-03-02: "Announce to the user" as implicit stop signal
2. 2026-03-03: "and stop" as halt language
3. 2026-04-12: Contradictory prohibition ("do not invoke" + "immediately continue to invoke")

The underlying principle is the same: **any instruction that gives the agent a reason to NOT continue will cause it to stop at a skill boundary in a pipeline context**.

## Prevention

- Never use prohibitions ("do not invoke X") in pipeline handoff instructions -- use explicit invocations ("invoke X now")
- When a skill is callable from both standalone and pipeline contexts, the pipeline path must contain only affirmative instructions (do X), never negative ones (do not X)
- Test pipeline-invokable skill handoffs by running the full one-shot pipeline, not just the skill in isolation

## Related Issues

- See also: [2026-03-03-and-stop-halt-language-breaks-pipeline.md](../2026-03-03-and-stop-halt-language-breaks-pipeline.md)
- See also: [2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md](../2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md)
