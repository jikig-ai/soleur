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
| review | "review PR", "check this code", PR number reference | `soleur:review` |
| default | Everything else — features, exploration, questions, generation, vague scope | `soleur:brainstorm` |

If intent is clear, invoke the skill directly via the **Skill tool** with the original user input as `args`. No confirmation step.

If intent is truly ambiguous, use the **AskUserQuestion tool** with 3 options: Brainstorm (Recommended), Fix (one-shot), Review.
