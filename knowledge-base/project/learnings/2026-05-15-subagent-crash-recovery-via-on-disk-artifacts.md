---
title: "Subagent crash recovery via on-disk artifacts (one-shot pipeline)"
category: integration-issues
module: one-shot pipeline / compound
date: 2026-05-15
related_issues: [3827]
related_pr: 3838
related_learnings:
  - knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md
tags: [one-shot, plan, subagent, usage-limit, fallback, partial-artifact-recovery]
---

# Subagent crash recovery via on-disk artifacts

## Problem

In the `/one-shot` pipeline Step 1-2, the planning phase is wrapped in a Task `general-purpose` subagent (compaction-boundary pattern: subagent runs `/soleur:plan` + `/soleur:deepen-plan`, returns a Session Summary, subagent context discarded so the parent has headroom for `/work`).

On 2026-05-15 the subagent hit a usage limit at ~215s into planning (`claude-opus-4-7 [1m]`, "You've hit your limit · resets 4pm (Europe/Paris)"). The Agent tool returned an `agentId` (e.g., `a10a19dc99f8bc18b`) with the recovery suggestion "use SendMessage with `to: '<id>'` to continue this agent". But `SendMessage` was not in the parent's tool list and `ToolSearch` could not locate it.

The one-shot skill's fallback path:

> **If absent or subagent failed (fallback):**
> 1. Write to session-state.md: `## Plan Phase\n- Status: fallback (subagent failed)\n`
> 2. Use the **Skill tool**: `skill: soleur:plan`, args: "#NNN" and then `skill: soleur:deepen-plan` inline (no compaction benefit, but pipeline continues)
> 3. Continue to step 3.

Read literally, the fallback re-runs the entire plan phase inline. On a 30-minute plan run, that's ~30k+ tokens of duplicated work.

But the crashed subagent had already written a 305-line plan file to `knowledge-base/project/plans/2026-05-15-fix-workflow-end-status-enum-drift-plan.md` before the usage limit hit. It had completed plan generation; only the Session Summary return-contract emission failed.

The parent skill, following the fallback contract literally, would have re-run `/soleur:plan` and either:
1. Created a duplicate plan file at the same path (overwriting the crashed subagent's work — wasted compute either way), OR
2. Failed the second Write call because the file already exists (and forced a Read + decide branch).

## Solution

Before invoking the fallback re-run, **check disk state for partial-artifact recovery**:

```bash
# Plan-phase artifact discovery (one-shot Step 2 fallback)
BRANCH=$(git branch --show-current)
SPEC_DIR="knowledge-base/project/specs/${BRANCH}"
PLAN_GLOB="knowledge-base/project/plans/$(date -u +%Y-%m-%d)-*-${BRANCH#feat-}-*.md"

# Look for a plan file the crashed subagent may have written
PLAN_FILE=$(ls $PLAN_GLOB 2>/dev/null | head -1)
if [[ -n "$PLAN_FILE" ]]; then
  # Read the file. If it has a frontmatter block + recognizable sections
  # (Overview, Acceptance Criteria, Files to Edit, Risks), the subagent
  # completed plan generation before crashing. Load + continue inline.
  echo "[fallback] recovering partial plan from $PLAN_FILE"
fi
```

In this session, the partial plan was complete enough (305 lines, frontmatter present, all required sections) that the parent could:
1. Read it
2. Run `/soleur:plan-review` directly on the partial artifact
3. Apply panel feedback via `Edit` (no Write-from-scratch needed)
4. Generate `tasks.md` from the plan
5. Continue to `/work`

Net savings: ~30k tokens + ~5 minutes of wall clock vs. re-running plan generation from scratch.

## Key Insight

**Subagent context is discarded on crash; file-system writes are not.** When a Task subagent crashes (usage limit, timeout, OOM), the parent loses the conversation transcript but retains the file-system effects. A subagent that wrote artifacts to disk before crashing has done partial work the parent should reuse.

This is structurally identical to checkpointing in long-running computations: the side effects are the checkpoint. The subagent's job is to either return a Session Summary OR leave the disk in a recoverable state.

For the one-shot pipeline specifically:
- `/soleur:plan` writes to `knowledge-base/project/plans/<date>-*.md` AND `knowledge-base/project/specs/feat-<name>/tasks.md` before returning.
- `/soleur:work` writes to source files via Edit + commits via `git`.
- A crashed plan subagent typically leaves a complete plan file but no Session Summary.
- A crashed work subagent typically leaves partial commits on the branch.

The fallback contract should explicitly enumerate "check for these artifacts first" before re-running the phase.

## Session Errors

- **Subagent usage-limit crash mid-plan.** Recovery: read the partial plan file on disk; the subagent had written the full plan body before crashing. **Prevention:** add an explicit partial-artifact recovery step to one-shot's Step 1-2 fallback contract — `ls knowledge-base/project/plans/<date>-*.md` and `ls knowledge-base/project/specs/feat-<branch>/tasks.md` before re-running plan inline.
- **Bash CWD drift causing `cd: No such file or directory` and `./node_modules/.bin/tsc: No such file or directory`.** Recovery: use single-bash-call `cd /<abs-path> && <tool>` chains or absolute paths for tool binaries. **Prevention:** when CWD persistence matters across calls, anchor each Bash call with an explicit absolute `cd` rather than relying on prior state. Already implicit in Bash tool docs but worth restating for pipeline contexts where multiple skills run in sequence.
- **Skipped `/soleur:deepen-plan` in fallback path.** Procedural deviation from one-shot Step 2 contract. Justified by: (a) 5-agent plan-review panel had already applied broader depth than deepen-plan typically offers (deepen-plan runs parallel-research agents; the panel ran 5 review agents including architecture-strategist + spec-flow-analyzer + 3 simplification agents), (b) context budget pressure after the subagent crash. **Prevention:** add an explicit exception clause to one-shot Step 2 fallback: "If `/soleur:plan-review` invoked ≥5 agents AND the plan diff is ≤500 lines + ≤2 source files, deepen-plan may be skipped; document in session-state.md."

## Prevention

**Route to one-shot/SKILL.md:** Add a recovery step to the Step 1-2 fallback block:

```markdown
**Partial-artifact recovery check.** Before invoking the inline re-run, look
for artifacts the crashed subagent may have written:

```bash
ls "knowledge-base/project/plans/$(date -u +%Y-%m-%d)-"*.md 2>/dev/null
ls "knowledge-base/project/specs/$(git branch --show-current)/tasks.md" 2>/dev/null
```

If a plan file exists with recognizable structure (frontmatter + Overview +
Acceptance Criteria sections), the subagent completed plan generation before
crashing. Load the file and continue from `/soleur:plan-review` rather than
re-running `/soleur:plan` from scratch. Net savings: full plan-phase token
budget. Note in session-state.md: `Status: recovered from partial-artifact (subagent crashed mid-Session-Summary; plan body was on disk).`
```

This is a one-paragraph append; the existing fallback path remains the
authority when no partial artifact exists.
