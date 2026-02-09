# Agent Instructions

This repository contains the Soleur Claude Code plugin -- an orchestration engine that provides agents, commands, skills, and a knowledge base for structured software development workflows.

## Working Agreement

- **Branching:** Create a feature branch for any non-trivial change. If already on the correct branch for the task, keep using it; do not create additional branches or worktrees unless explicitly requested.
- **Safety:** Do not delete or overwrite user data. Avoid destructive commands.
- **ASCII-first:** Use ASCII unless the file already contains Unicode.

## Browser Automation

Use `agent-browser` for web automation. Run `agent-browser --help` for all commands.

Core workflow:

1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes

## Worktree Awareness

When working with git worktrees, ALWAYS make edits in the worktree directory, NOT the main repo directory. Before editing any file, verify the correct worktree path.

- Run `pwd` to check the current directory before writing files.
- If in `.worktrees/<name>`, proceed with edits there.
- If in the main repo root while a worktree is active for the task, warn and offer to switch.
- Never write brainstorm, spec, or plan files to main when a feature worktree exists.

## Workflow Completion Protocol

After completing implementation work, follow this checklist before creating a PR:

1. Run `/soleur:compound` to capture learnings (ask user first).
2. Commit all artifacts (brainstorms, specs, plans, learnings).
3. Update `plugins/soleur/README.md` if new commands, skills, or agents were added.
4. Bump version per plugin `AGENTS.md` rules.
5. Push and create PR.

Use the `/ship` skill to automate this checklist.

## Interaction Style

When the user gives a brainstorm or planning request, do NOT launch parallel research tasks or ask excessive clarifying questions before the user has confirmed the direction.

- Present a concise summary first (2-3 sentences), then ask if they want to go deeper.
- Bad: Immediately spawning 5 research agents without user confirmation.
- Good: "Here's my initial take: [summary]. Want me to research deeper?"

## Plugin Versioning

When modifying files under `plugins/soleur/`, always check `plugins/soleur/AGENTS.md` for the versioning triad before committing. Version bumps are mandatory for feature changes.

- New skill/command/agent: MINOR bump (1.6.0 -> 1.7.0).
- Bug fix or docs update: PATCH bump (1.6.0 -> 1.6.1).
- Breaking change: MAJOR bump (1.6.0 -> 2.0.0).
- All three files must be updated together: `plugin.json`, `CHANGELOG.md`, `README.md`.
