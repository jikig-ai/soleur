---
name: one-shot
description: "This skill should be used when running the full autonomous engineering workflow from plan to merged PR."
---

Run these steps in order. Do not do anything else.

**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), create a worktree for the feature branch. Do NOT use `git pull` or `git checkout -b` -- both fail on bare repos (`core.bare=true`).

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-one-shot-<slugified-arguments>
```

Then `cd` into the worktree path printed by the script. Parallel agents on the same repo cause silent merge conflicts when both work on main.

**Step 0c: Create draft PR.** After creating the feature branch, create a draft PR from inside the worktree (the script errors with "Cannot run from bare repo root" otherwise, and the Bash tool does NOT persist CWD across calls — use a single `cd && bash` to be explicit):

```bash
cd <worktree-path> && bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
```

If this fails (no network, or "No commits between main and <branch>"), print a warning but continue. The branch exists locally and the `/ship` phase will create the PR after implementation commits exist.

**Steps 1-2: Plan + Deepen (Isolated Subagent)**

Spawn a Task general-purpose subagent to run plan and deepen-plan. This creates a compaction boundary -- the subagent's context is discarded after it returns, freeing headroom for implementation.

```text
Task general-purpose: "You are running the planning phase of a one-shot pipeline.

WORKING DIRECTORY: [insert pwd output]
BRANCH: [insert current branch name]
ARGUMENTS: $ARGUMENTS

STEPS:
1. Use the Skill tool: skill: soleur:plan, args: "$ARGUMENTS"
2. After plan is created, use the Skill tool: skill: soleur:deepen-plan, args: "<plan_file_path>"

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

Do NOT proceed beyond deepen-plan. Do NOT start work.

CRITICAL: You MUST output the ## Session Summary section in EXACTLY the format above. Place it as the last thing in your output."
```

**Parse subagent output and write session-state.md:**

After the subagent returns, check for a `## Session Summary` heading in the output.

**If present (success):**

1. Extract the plan file path from `### Plan File`
2. Detect the feature branch: run `git branch --show-current`
3. Write the parsed content to `knowledge-base/project/specs/feat-<name>/session-state.md` (create if needed):

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
2. Use the **Skill tool**: `skill: soleur:plan`, args: "$ARGUMENTS" and then `skill: soleur:deepen-plan` inline (no compaction benefit, but pipeline continues)
3. Continue to step 3.

**Steps 3-8: Implementation, Review, and Ship**

3. Use the **Skill tool**: `skill: soleur:work`, args: "<plan_file_path>". Work handles implementation only (Phases 0-3). It does NOT invoke ship -- one-shot controls the full lifecycle below.

> **CONTINUATION GATE**: When work outputs `## Work Phase Complete`, that is your signal to continue. Do NOT end your turn. Do NOT treat "Implementation complete" or similar phrases as a stopping point. Immediately proceed to step 4 in the same response.

4. Use the **Skill tool**: `skill: soleur:review`
5. **Resolve ALL review findings (P1, P2, and P3).** Technical debt compounds — fix everything now, not later. List open GitHub issues from this review session:

   ```bash
   gh issue list --label code-review --state open --search "PR #<current_pr_number>" --json number,title,body,labels
   ```

   The `--search` flag scopes results to issues from this review session (the review skill's issue template includes `PR #<number>` in the body). If zero issues match, proceed immediately to Step 5.5.

   For each matching issue (regardless of priority), spawn a parallel `pr-comment-resolver` agent. Pass the issue body's `## Problem`, `## Proposed Fix`, and `Location:` fields as the agent's input. After all agents return, commit fixes and close each resolved issue:

   ```bash
   gh issue close <number> --comment "Fixed in <commit-sha>"
   ```

   Do NOT end your turn after this step. Proceed to Step 5.5.

5.5. Use the **Skill tool**: `skill: soleur:qa`, args: "<plan_file_path>". QA verifies features work end-to-end by executing the plan's Test Scenarios (browser flows via Playwright MCP, API verification via Doppler + curl). If QA fails, fix the issues and re-run QA before proceeding. If the plan has no Test Scenarios section, QA skips gracefully.
6. Use the **Skill tool**: `skill: soleur:compound`
7. Use the **Skill tool**: `skill: soleur:ship`. Ship handles compound re-check (Phase 2), documentation verification (Phase 3), tests (Phase 4), semver label assignment, push, PR creation, CI, merge, and cleanup.
8. Output `<promise>DONE</promise>` when PR is merged and release workflows pass

CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop.

Start with step 0b now.
