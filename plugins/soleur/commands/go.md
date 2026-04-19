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

When routing to `soleur:drain-labeled-backlog`, extract the label value from the user's message. If the user used a bare name (e.g., "security"), resolve it to the namespaced form by running `gh label list --limit 100 | grep -i <name>` before invoking (rule `cq-gh-issue-label-verify-name`). Pass the resolved label via `--label <resolved>` in the skill arguments.

If intent is truly ambiguous, use the **AskUserQuestion tool** with 4 options: Brainstorm (Recommended), Fix (one-shot), Drain (labeled backlog), Review.
