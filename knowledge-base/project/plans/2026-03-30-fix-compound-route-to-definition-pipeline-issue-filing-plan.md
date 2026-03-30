---
title: "fix(compound): route-to-definition should file issues in pipeline mode"
type: fix
date: 2026-03-30
---

# fix(compound): Route-to-Definition Should File Issues in Pipeline Mode

## Problem

During pipeline execution (one-shot), compound's Route Learning to Definition phase (Step 8 of compound-capture) identified a concrete improvement but skipped it with "minor improvement, skipping in pipeline mode." The current headless mode instruction in `compound/SKILL.md` line 263 says "auto-accept the LLM-proposed edit without prompting," but in practice the model rationalizes skipping edits it judges as minor when running in a pipeline context.

Auto-accepting edits in headless mode is risky -- the model may propose low-quality edits that get silently applied to definition files without review. The safer behavior for pipeline mode is to file a GitHub issue with the proposed edit, ensuring nothing is silently dropped and nothing is blindly applied.

Evidence: Session #1291 one-shot pipeline (2026-03-30). Compound identified that `/review` should document the inline fallback pattern when subagents fail. The improvement was noted in conversation but never tracked. See [#1299](https://github.com/jikig-ai/soleur/issues/1299).

## Proposed Fix

Change the pipeline/headless behavior in two files:

### File 1: `plugins/soleur/skills/compound/SKILL.md`

**Section:** "Route Learning to Definition" (around line 263)

**Current behavior (line 263):**

> Headless mode: If `HEADLESS_MODE=true`, auto-accept the LLM-proposed edit without prompting.

**New behavior:**

Replace with instructions to file a GitHub issue when `HEADLESS_MODE=true`:

1. Generate the proposed edit (same as current behavior in 8.3)
2. If the proposed edit is actionable (non-empty, targets a real file), create a GitHub issue via `gh issue create` with:
   - Title: `compound: route-to-definition proposal for <target-file-basename>`
   - Body: the proposed edit text, target file path, and source learning file path
   - Milestone: "Post-MVP / Later"
   - Label: (none required -- operational issue)
3. If the proposed edit is not actionable (empty, target file missing), skip silently
4. Do NOT apply the edit directly in headless mode

### File 2: `plugins/soleur/skills/compound-capture/SKILL.md`

**Section:** Step 8.2 and Step 8.4

Add explicit headless mode handling to both sub-steps:

**Step 8.2 (Select Target):**

Add after the existing "If multiple detected" paragraph:

> **Headless mode:** If `HEADLESS_MODE=true` and multiple components detected, select the component most relevant to the learning content using LLM judgment. If one component detected, use it. Do not prompt.

**Step 8.4 (Confirm):**

Add a headless mode paragraph replacing the AskUserQuestion flow:

> **Headless mode:** If `HEADLESS_MODE=true`, do not apply the edit directly. Instead, create a GitHub issue to track the proposed edit:
>
> ```bash
> gh issue create --title "compound: route-to-definition proposal for <target-basename>" --body "<proposed-edit-text-and-context>" --milestone "Post-MVP / Later"
> ```
>
> Log the created issue URL. Then update the learning file's `synced_to` frontmatter with `<definition-name>-issue-<number>` to prevent re-proposing. Proceed to the decision menu.

## Acceptance Criteria

- [ ] Compound's Route Learning to Definition creates a GitHub issue when `HEADLESS_MODE=true` and the proposed edit is actionable
- [ ] Issue includes: proposed edit text, target file path, source learning file path
- [ ] Issue is milestoned to "Post-MVP / Later"
- [ ] Headless mode does NOT apply the edit directly to definition files
- [ ] Interactive mode behavior is unchanged (Accept/Skip/Edit via AskUserQuestion)
- [ ] Step 8.2 has explicit headless mode target selection logic

## Test Scenarios

- Given compound runs in headless mode with an actionable route-to-definition proposal, when Step 8.4 executes, then a GitHub issue is created with the proposal details and "Post-MVP / Later" milestone
- Given compound runs in headless mode with no active components detected, when Step 8.1 executes, then routing is skipped silently (existing behavior preserved)
- Given compound runs in interactive mode, when Step 8.4 executes, then AskUserQuestion presents Accept/Skip/Edit options (existing behavior preserved)
- Given compound runs in headless mode with multiple components, when Step 8.2 executes, then the most relevant component is auto-selected without prompting

## Context

### Files to Modify

1. `plugins/soleur/skills/compound/SKILL.md` -- Update headless mode instruction in "Route Learning to Definition" section
2. `plugins/soleur/skills/compound-capture/SKILL.md` -- Add headless mode handling to Steps 8.2 and 8.4

### Why Issue Filing Over Auto-Accept

The current "auto-accept" approach has two failure modes:

1. **Silent skip:** The model judges the edit as minor and skips it entirely (observed in #1291), losing the insight
2. **Silent apply:** The model applies a low-quality edit without review, degrading definition files

Filing an issue avoids both: the insight is tracked (not lost) and requires human review before application (not blindly applied). This aligns with the project's "deferred work must be tracked" principle from AGENTS.md.

### Why "Post-MVP / Later" Milestone

Route-to-definition proposals are operational improvements to skill/agent definitions. They are not user-facing features tied to a specific roadmap phase. "Post-MVP / Later" is the correct default per AGENTS.md: "Default to 'Post-MVP / Later' for operational issues."

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/workflow fix.

## References

- Issue: [#1299](https://github.com/jikig-ai/soleur/issues/1299)
- Evidence session: #1291 one-shot pipeline (2026-03-30)
- Related learning: `2026-03-03-skill-handoff-contradicts-pipeline-continuation.md` (pipeline continuation patterns)
