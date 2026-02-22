---
name: soleur:one-shot
description: Full autonomous engineering workflow from plan to PR with video
argument-hint: "[feature description or issue reference]"
---

Run these steps in order. Do not do anything else.

**Step 0a: Activate Ralph Loop.** Run this command via the Bash tool:

```bash
bash ./plugins/soleur/scripts/setup-ralph-loop.sh "finish all slash commands" --completion-promise "DONE"
```

**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), pull latest and create a feature branch named `feat/one-shot-<slugified-arguments>` before proceeding. Parallel agents on the same repo cause silent merge conflicts when both work on main.

**Steps 1-2: Plan + Deepen (Isolated Subagent)**

Spawn a Task general-purpose subagent to run plan and deepen-plan. This creates a compaction boundary -- the subagent's context is discarded after it returns, freeing headroom for implementation.

```text
Task general-purpose: "You are running the planning phase of a one-shot pipeline.

WORKING DIRECTORY: [insert pwd output]
BRANCH: [insert current branch name]
ARGUMENTS: $ARGUMENTS

STEPS:
1. Run /soleur:plan $ARGUMENTS
2. After plan is created, run /deepen-plan <plan_file_path>

RETURN CONTRACT:
When both steps are done, output a summary in this exact format:

## Session Summary

### Plan File
<absolute path to the plan .md file>

### Errors
<list any errors encountered during planning, or 'None'>

### Decisions
<key decisions made during planning, 3-5 bullet points>

### Components Invoked
<list of commands/skills/agents invoked>

Do NOT proceed beyond deepen-plan. Do NOT start /soleur:work."
```

**Parse subagent output and write session-state.md:**

After the subagent returns, check for a `## Session Summary` heading in the output.

**If present (success):**
1. Extract the plan file path from `### Plan File`
2. Detect the feature branch: run `git branch --show-current`
3. Write the parsed content to `knowledge-base/specs/feat-<name>/session-state.md` (create if needed):

```markdown
# Session State

## Plan Phase
- Plan file: <path from subagent>
- Status: complete

### Errors
<errors from subagent output>

### Decisions
<decisions from subagent output>

### Components Invoked
<components from subagent output>
```

4. Continue to step 3 using the extracted plan file path.

**If absent or subagent failed (fallback):**
1. Write to session-state.md: `## Plan Phase\n- Status: fallback (subagent failed)\n`
2. Run `/soleur:plan $ARGUMENTS` and `/deepen-plan` inline (no compaction benefit, but pipeline continues)
3. Continue to step 3.

**Steps 3-9: Implementation through Ship**

3. `/soleur:work <plan_file_path>`
4. `/soleur:review`
5. `/resolve-todo-parallel`
6. `/soleur:compound`
7. `/test-browser`
8. `/feature-video`
9. Output `<promise>DONE</promise>` when video is in PR

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

Start with step 0a now.
