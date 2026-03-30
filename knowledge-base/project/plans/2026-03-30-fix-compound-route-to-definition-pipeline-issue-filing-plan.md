---
title: "fix(compound): route-to-definition should file issues in pipeline mode"
type: fix
date: 2026-03-30
---

# fix(compound): Route-to-Definition Should File Issues in Pipeline Mode

## Enhancement Summary

**Deepened on:** 2026-03-30
**Sections enhanced:** 4 (Proposed Fix, Test Scenarios, Context, Edge Cases)
**Research sources:** 6 learnings (headless-mode-skill-bypass, pipeline-continuation-stalls, skill-enforced-convention-pattern, skill-defense-in-depth-gate, heredoc-yaml-credential-masking, milestone-enforcement-workflow-edits)

### Key Improvements

1. Added precise edit locations with line numbers and before/after text for both target files
2. Added edge case handling for `gh issue create` failures and body formatting
3. Added `synced_to` frontmatter convention alignment with existing codebase patterns
4. Added guard against shell variable expansion in SKILL.md instructions (constitution rule)

### New Considerations Discovered

- The `gh issue create` body must avoid shell variable expansion in SKILL.md prose (use angle-bracket placeholders per constitution "Never" rule)
- Issue body formatting in automation requires `--body-file` pattern to avoid heredoc parsing problems (learning: 2026-03-21)
- The `--milestone` flag in `gh issue create` is guardrail-enforced (Guard 5 in guardrails.sh) -- the plan must include it or the PreToolUse hook will block the command

## Problem

During pipeline execution (one-shot), compound's Route Learning to Definition phase (Step 8 of compound-capture) identified a concrete improvement but skipped it with "minor improvement, skipping in pipeline mode." The current headless mode instruction in `compound/SKILL.md` line 263 says "auto-accept the LLM-proposed edit without prompting," but in practice the model rationalizes skipping edits it judges as minor when running in a pipeline context.

Auto-accepting edits in headless mode is risky -- the model may propose low-quality edits that get silently applied to definition files without review. The safer behavior for pipeline mode is to file a GitHub issue with the proposed edit, ensuring nothing is silently dropped and nothing is blindly applied.

Evidence: Session #1291 one-shot pipeline (2026-03-30). Compound identified that `/review` should document the inline fallback pattern when subagents fail. The improvement was noted in conversation but never tracked. See [#1299](https://github.com/jikig-ai/soleur/issues/1299).

### Research Insights

**Relevant learnings:**

- **Headless mode convention** (`2026-03-03-headless-mode-skill-bypass-convention.md`): Each skill handles headless independently with sensible defaults per prompt. Safety constraints still run in headless mode -- only user confirmation prompts are bypassed. This validates the approach of filing an issue (safety-preserving) rather than auto-accepting (safety-compromising) or skipping (insight-losing).
- **Pipeline continuation stalls** (`2026-03-03-pipeline-continuation-stalls.md`): Conclusive-sounding output can be interpreted as a turn boundary. The issue-filing step must NOT use stop-like language after creating the issue -- it must proceed to the decision menu without sounding terminal.
- **Skill-enforced convention** (`2026-03-19-skill-enforced-convention-pattern.md`): Three enforcement tiers exist -- PreToolUse hooks (syntactic), skill instructions (semantic), prose rules (advisory). This fix operates at the skill instruction tier since it requires LLM judgment to assess edit quality.

## Proposed Fix

Change the pipeline/headless behavior in two files:

### File 1: `plugins/soleur/skills/compound/SKILL.md`

**Section:** "Route Learning to Definition" (line 263)

**Current text:**

```markdown
3. **Headless mode:** If `HEADLESS_MODE=true`, auto-accept the LLM-proposed edit without prompting.
```

**Replacement text:**

```markdown
3. **Headless mode:** If `HEADLESS_MODE=true`, do not apply the edit directly. Instead, file a GitHub issue to track the proposal. Use `gh issue create` with the title `compound: route-to-definition proposal for <target-file-basename>`, a body containing the proposed edit text and target file path and source learning file path, and `--milestone "Post-MVP / Later"`. If the proposed edit is not actionable (empty or target file missing), skip silently. Do not prompt.
```

### File 2: `plugins/soleur/skills/compound-capture/SKILL.md`

**Section:** Step 8.2 (Select Target) -- after line 295 ("If no components detected, skip to the decision menu.")

**Add after existing content:**

```markdown
**Headless mode:** If `HEADLESS_MODE=true` and multiple components detected, select the component most relevant to the learning content using LLM judgment. If one component detected, use it. Do not prompt.
```

**Section:** Step 8.4 (Confirm) -- replace the entire section content. Current text (lines 320-332):

```markdown
#### 8.4 Confirm

Use **AskUserQuestion** with options:
- **Accept** -- Apply the edit to the definition file
- **Skip** -- Do not modify the definition; the learning is still captured in knowledge-base/project/learnings/
- **Edit** -- Modify the bullet text, then re-display for confirmation

If accepted, write the edit to the definition file. Then update the learning file's `synced_to` frontmatter to prevent `/soleur:sync` from re-proposing this pair:

- If `synced_to` array exists in frontmatter: append the definition name
- If frontmatter exists but `synced_to` is absent: add `synced_to: [definition-name]`
- If no YAML frontmatter block exists: prepend a minimal `---` block with only `synced_to: [definition-name]`

Do NOT commit -- the edits are staged for the normal workflow completion protocol.
```

**Replacement text:**

```markdown
#### 8.4 Confirm

**Headless mode:** If `HEADLESS_MODE=true`, do not apply the edit directly. Instead, create a GitHub issue to track the proposed edit. Write the issue body to a temporary file, then create the issue:

1. Write the body to `/tmp/compound-rtd-body.md` containing: the proposed edit text (as a fenced code block), the target file path, and the source learning file path
2. Run: `gh issue create --title "compound: route-to-definition proposal for <target-basename>" --body-file /tmp/compound-rtd-body.md --milestone "Post-MVP / Later"`
3. If `gh issue create` fails (network error, auth failure), log the error and continue to the decision menu -- do not block the pipeline on issue creation failure
4. If successful, log the created issue URL
5. Update the learning file's `synced_to` frontmatter with `<definition-name>-issue-<number>` to prevent re-proposing
6. Proceed to the decision menu

**Interactive mode:** Use **AskUserQuestion** with options:

- **Accept** -- Apply the edit to the definition file
- **Skip** -- Do not modify the definition; the learning is still captured in knowledge-base/project/learnings/
- **Edit** -- Modify the bullet text, then re-display for confirmation

If accepted, write the edit to the definition file. Then update the learning file's `synced_to` frontmatter to prevent `/soleur:sync` from re-proposing this pair:

- If `synced_to` array exists in frontmatter: append the definition name
- If frontmatter exists but `synced_to` is absent: add `synced_to: [definition-name]`
- If no YAML frontmatter block exists: prepend a minimal `---` block with only `synced_to: [definition-name]`

Do NOT commit -- the edits are staged for the normal workflow completion protocol.
```

### Research Insights for Implementation

**Issue body formatting (`2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`):**

The `--body-file` pattern is safer than inline `--body` for multi-line content. The SKILL.md instruction uses `--body-file /tmp/compound-rtd-body.md` to avoid shell escaping issues with the proposed edit text (which often contains code fences, backticks, and special characters).

**Milestone enforcement (`2026-03-26-milestone-enforcement-workflow-edits.md`):**

Guard 5 in `guardrails.sh` blocks `gh issue create` without `--milestone`. The plan explicitly includes `--milestone "Post-MVP / Later"` in every `gh issue create` command to satisfy this guardrail. The PreToolUse hook checks for the flag syntactically.

**Shell variable expansion prohibition (constitution "Never" rule):**

SKILL.md files must not contain `${VAR}` or `$()` -- use angle-bracket prose placeholders instead. All `gh issue create` templates in this plan use `<target-basename>`, `<definition-name>`, and `<number>` placeholders, not shell variables.

## Acceptance Criteria

- [ ] Compound's Route Learning to Definition creates a GitHub issue when `HEADLESS_MODE=true` and the proposed edit is actionable
- [ ] Issue includes: proposed edit text, target file path, source learning file path
- [ ] Issue is milestoned to "Post-MVP / Later"
- [ ] Headless mode does NOT apply the edit directly to definition files
- [ ] Interactive mode behavior is unchanged (Accept/Skip/Edit via AskUserQuestion)
- [ ] Step 8.2 has explicit headless mode target selection logic
- [ ] Issue creation failure does not block the pipeline (graceful degradation)

## Test Scenarios

- Given compound runs in headless mode with an actionable route-to-definition proposal, when Step 8.4 executes, then a GitHub issue is created with the proposal details and "Post-MVP / Later" milestone
- Given compound runs in headless mode with no active components detected, when Step 8.1 executes, then routing is skipped silently (existing behavior preserved)
- Given compound runs in interactive mode, when Step 8.4 executes, then AskUserQuestion presents Accept/Skip/Edit options (existing behavior preserved)
- Given compound runs in headless mode with multiple components, when Step 8.2 executes, then the most relevant component is auto-selected without prompting
- Given `gh issue create` fails (network error, auth failure) in headless mode, when Step 8.4 handles the failure, then compound logs the error and proceeds to the decision menu without blocking

### Research Insights for Test Scenarios

**Edge case: `gh issue create` failure in pipeline.** The pipeline runs in automated environments where GitHub auth tokens may expire or network connectivity may be intermittent. The graceful degradation test scenario (last item above) ensures the pipeline is not blocked by transient issue creation failures. The learning from `2026-03-03-pipeline-continuation-stalls.md` confirms that any blocking step in a pipeline that can fail silently is a stall risk.

**Edge case: duplicate issue creation.** If compound runs twice on the same learning (e.g., due to a retry), the `synced_to` frontmatter check prevents duplicate issue creation. The plan's `synced_to` update with `<definition-name>-issue-<number>` is sufficient for deduplication since the sync check happens in Step 8.1 before reaching 8.4.

## Context

### Files to Modify

1. `plugins/soleur/skills/compound/SKILL.md` -- Update headless mode instruction in "Route Learning to Definition" section (line 263). Single line replacement.
2. `plugins/soleur/skills/compound-capture/SKILL.md` -- Add headless mode handling to Steps 8.2 (after line 295) and 8.4 (replace lines 320-332). Two edits in one file.

### Why Issue Filing Over Auto-Accept

The current "auto-accept" approach has two failure modes:

1. **Silent skip:** The model judges the edit as minor and skips it entirely (observed in #1291), losing the insight
2. **Silent apply:** The model applies a low-quality edit without review, degrading definition files

Filing an issue avoids both: the insight is tracked (not lost) and requires human review before application (not blindly applied). This aligns with the project's "deferred work must be tracked" principle from AGENTS.md.

### Why "Post-MVP / Later" Milestone

Route-to-definition proposals are operational improvements to skill/agent definitions. They are not user-facing features tied to a specific roadmap phase. "Post-MVP / Later" is the correct default per AGENTS.md: "Default to 'Post-MVP / Later' for operational issues."

### Sharp Edges

1. **Do not use `--body` inline for issue creation.** The proposed edit text contains code fences and special characters that break shell quoting. Always use `--body-file` with a temporary file.
2. **Do not omit `--milestone`.** Guard 5 in guardrails.sh will block the command. Always include `--milestone "Post-MVP / Later"`.
3. **Do not use stop-like language after issue creation.** The compound skill runs mid-pipeline (one-shot). After filing the issue, the instruction must say "proceed to the decision menu" not "done" or "complete."
4. **Verify the edit with a re-read.** After modifying the SKILL.md files, re-read to confirm the headless/interactive branches are correctly structured and do not contradict each other.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/workflow fix.

## References

- Issue: [#1299](https://github.com/jikig-ai/soleur/issues/1299)
- Evidence session: #1291 one-shot pipeline (2026-03-30)
- Related learning: `2026-03-03-skill-handoff-contradicts-pipeline-continuation.md` (pipeline continuation patterns)
- Related learning: `2026-03-03-headless-mode-skill-bypass-convention.md` (headless mode convention)
- Related learning: `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md` (issue body formatting)
- Related learning: `2026-03-26-milestone-enforcement-workflow-edits.md` (milestone guardrail)
- Related learning: `2026-03-19-skill-enforced-convention-pattern.md` (enforcement tiers)
- Related learning: `2026-03-27-skill-defense-in-depth-gate-pattern.md` (defense-in-depth pattern)
