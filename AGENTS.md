# Agent Instructions

This repository contains the Soleur Claude Code plugin -- an orchestration engine that provides agents, commands, skills, and a knowledge base for structured software development workflows.

## Working Agreement

- **Branching:** HARD RULE: Never commit directly to main. Create a feature branch for every change. If already on the correct branch for the task, keep using it; do not create additional branches or worktrees unless explicitly requested.
- **Safety:** Do not delete or overwrite user data. Avoid destructive commands. Specific prohibitions:
  - Never `rm -rf` on the current working directory, a worktree path (`.worktrees/`), or the repository root.
  - Never `gh pr merge --delete-branch` while a worktree exists for that branch -- remove the worktree first, then merge.
- **ASCII-first:** Use ASCII unless the file already contains Unicode.

## Browser Automation

Use `agent-browser` for web automation. Run `agent-browser --help` for all commands.

Core workflow:

1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes

## Worktree Awareness

HARD RULE: When a worktree is active for the current task, ALL file edits and git operations MUST happen in the worktree directory. Editing files in the main repo while a worktree exists is a blocking error -- stop immediately and switch.

Before EVERY file write or git command:

1. Run `pwd` to verify the current directory.
2. If in `.worktrees/<name>`, proceed.
3. If in the main repo root while a worktree is active, STOP. Do not write the file. Warn the user and switch to the worktree path before continuing.

This applies to ALL files -- code, brainstorms, specs, plans, learnings, configs. No exceptions.

## Diagnostic-First Rule

Before implementing a fix for any bug or error, verify the root cause first. Do not assume the first hypothesis is correct.

1. Reproduce the error or read the exact error output.
2. Run the simplest possible diagnostic to confirm the cause.
3. Only after confirming the root cause, propose and implement the fix.

FAILURE MODE TO AVOID: Seeing an error message and immediately changing code based on a guess. This has led to fixes that mask the real problem or break unrelated functionality. Check the simple things first (expired keys, wrong branch, missing config) before pursuing complex debugging.

## Workflow Completion Protocol

MANDATORY checklist after completing implementation work. Every step MUST be completed in order. Do not skip steps. Do not propose committing until steps 1-2 are done.

1. **Review** -- Run code review on unstaged changes. Do not skip this.
2. **Compound** -- Run `/soleur:compound` to capture learnings. Ask the user first, but do not silently skip it.
3. **Stage ALL artifacts** -- Brainstorms, specs, plans, learnings, AND code. Historically missed: forgetting to stage non-code files. Run `git status` and verify nothing is left behind.
4. **README** -- If any new command, skill, or agent was added, update `plugins/soleur/README.md`. Check, don't assume.
5. **Version bump** -- If files under `plugins/soleur/` changed, bump the version. See Plugin Versioning below.
6. **Commit** -- This is the gate. Everything above must be done first.
7. **Push and create PR** -- Do not stop after committing. Push and open the PR in the same step.
8. **Post-merge cleanup** -- After the PR is merged: remove the worktree with `worktree-manager.sh cleanup-merged`, delete stale local branches. See `/ship` Phase 8 for the full procedure.

FAILURE MODE TO AVOID: Committing code, then forgetting to push, forgetting to create the PR, or forgetting to include spec/plan files. If you catch yourself about to skip a step, stop and complete it.

Use the `/ship` skill to automate this checklist.

## Interaction Style

HARD RULE: When the user gives a brainstorm or planning request, do NOT spawn any Task agents or launch parallel research before the user has confirmed the direction. Zero agents until the user says go.

1. Present a concise summary first (2-3 sentences).
2. Ask if they want to go deeper.
3. Only AFTER user confirmation, launch research agents.

FAILURE MODE TO AVOID: The user says "let's brainstorm X" and you immediately spawn 5 research agents. This has caused session rewinds multiple times. Wait for confirmation.

## Communication Style

- Challenge reasoning instead of validating by default -- explain the counter-argument, then let the user decide.
- Stop excessive validation. If something looks wrong, say so directly.
- Avoid flattery or unnecessary praise. Acknowledge good work briefly, then move on.

## Feature Lifecycle

The full lifecycle for a feature is: brainstorm, plan, implement, review, ship. Small fixes can skip brainstorm and plan, but for non-trivial work follow this sequence:

1. **Brainstorm** (`/soleur:brainstorm`) -- Explore the problem space. Output: `knowledge-base/brainstorms/`.
2. **Plan** (`/soleur:plan`) -- Design the implementation. Output: `knowledge-base/plans/`.
3. **Implement** (`/soleur:work`) -- Build it on a feature branch.
4. **Review** (`/soleur:review`) -- Code review before shipping.
5. **Ship** (`/ship`) -- Automates the Workflow Completion Protocol above.

## Plugin Versioning

HARD RULE: If ANY file under `plugins/soleur/` was modified, you MUST bump the version before committing. No exceptions. This is the most frequently missed step historically.

Before committing, self-check:
1. Did I modify files under `plugins/soleur/`? If yes, continue. If no, skip this section.
2. Read `plugins/soleur/plugin.json` to get the current version.
3. Determine bump type:
   - New skill/command/agent: MINOR bump (1.6.0 -> 1.7.0).
   - Bug fix or docs update: PATCH bump (1.6.0 -> 1.6.1).
   - Breaking change: MAJOR bump (1.6.0 -> 2.0.0).
4. Update ALL THREE files together -- `plugin.json`, `CHANGELOG.md`, `README.md`. Missing any one of these is a failed version bump.

FAILURE MODE TO AVOID: Committing plugin changes without bumping the version, or updating `plugin.json` but forgetting `CHANGELOG.md`.
