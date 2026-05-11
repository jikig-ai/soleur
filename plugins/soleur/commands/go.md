---
name: go
description: Unified entry point that classifies intent and routes to the right workflow skill
argument-hint: "[what you want to do]"
---

# Soleur Go

Unified entry point for all Soleur workflows. Classify the user's intent and route to the correct skill.

## User Input

<user_input> #$ARGUMENTS </user_input>

**If the user input above is empty**, ask: "What would you like to do? Describe what you need and I'll route you to the right workflow."

Do not proceed until there is input from the user.

## Step 0: Session-Start Preamble

Before any other work, run the session-start gates from AGENTS.md (`wg-at-session-start-run-bash-plugins-soleur` + `wg-at-session-start-after-cleanup-merged`):

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && \
  git worktree list && \
  git show main:.mcp.json > .mcp.json 2>/dev/null || true
```

The script works from either the bare root or any worktree. The `.mcp.json` refresh is harmless inside a worktree (file gets overwritten on next session-start from the new CWD). Skip silently on first error — do not block routing on session-start hygiene.

See `knowledge-base/project/learnings/2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record.md` Session Errors #1-#2 for the gap this closes.

## Step 1: Worktree Context

Run `pwd`. If the path contains `.worktrees/`, extract the feature name and mention it:

"You're in worktree **feat-[name]**. Want to continue working on this, or start something new?"

If the user wants to continue the current feature, delegate to `soleur:work` via the **Skill tool** with the user input as arguments. Then stop.

## Step 2: Classify and Route

Analyze the user input and classify intent using semantic assessment:

| Intent | Trigger Signals | Routes To |
|--------|----------------|-----------|
| fix | The user describes broken behavior, errors, regressions, or something that needs fixing | `soleur:one-shot` |
| drain | "fix all issues labeled X", "drain the Y backlog", "close all label:Z", "clean up the X backlog" | `soleur:drain-labeled-backlog` |
| review | "review PR", "check this code", PR number reference | `soleur:review` |
| default | Everything else — features, exploration, questions, generation, vague scope | `soleur:brainstorm` |

If intent is clear, invoke the skill directly via the **Skill tool** with the original user input as `args`. No confirmation step.

When routing to `soleur:drain-labeled-backlog`, extract the label value from the user's message. If the user used a bare name (e.g., "security"), resolve it to the namespaced form by running `gh label list --limit 100 | grep -i <name>` before invoking — `gh` rejects an invalid `--label` with a clear error, so verify against the live label set. Pass the resolved label via `--label <resolved>` in the skill arguments.

If intent is truly ambiguous, use the **AskUserQuestion tool** with 4 options: Brainstorm (Recommended), Fix (one-shot), Drain (labeled backlog), Review.
