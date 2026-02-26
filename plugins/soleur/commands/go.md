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

## Step 2: Classify Intent

Analyze the user input and classify into one of these intents:

| Intent | Trigger Signals | Delegates To |
|--------|----------------|--------------|
| explore | Questions, "brainstorm", "think about", "let's explore", vague scope, no clear deliverable | `soleur:brainstorm` skill |
| build | Bug fix, feature request, issue reference (#N), clear requirements, "fix", "add", "implement", "build" | `soleur:one-shot` skill |
| review | "review PR", "check this code", "review #N", PR number reference | `soleur:review` skill |

If the input does not clearly match one intent, use the **AskUserQuestion tool** to present all three options and let the user choose. Do not guess on ambiguous input.

## Step 3: Confirm Route

Use the **AskUserQuestion tool** to propose the classified intent:

**Question:** "I'll route this as **[intent]**. Sound right?"

**Options:**
1. The proposed intent (add "(Recommended)" to the label)
2. The other two intents as alternatives

## Step 4: Delegate

After confirmation, invoke the selected skill using the **Skill tool** with the full user input as arguments.

- explore: `skill: soleur:brainstorm`
- build: `skill: soleur:one-shot`
- review: `skill: soleur:review`

Pass the original user input text as the `args` parameter. Do not strip or modify the input.
