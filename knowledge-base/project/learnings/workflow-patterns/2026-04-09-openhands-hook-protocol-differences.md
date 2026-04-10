---
title: "OpenHands hook protocol differences from Claude Code"
date: 2026-04-09
issue: 1778
category: workflow-patterns
tags: [openhands, hooks, porting, protocol]
---

# OpenHands Hook Protocol Differences

## Context

Ported 5 Claude Code hooks to OpenHands `.openhands/hooks.json` format for #1778.

## Key Protocol Differences

### Blocking mechanism

- **Claude Code:** Output JSON with `hookSpecificOutput.permissionDecision: "deny"`, exit 0.
- **OpenHands:** Output JSON with `{"decision":"deny","reason":"..."}`, exit 2. Either exit code 2 OR `decision: "deny"` triggers blocking.

### Input format

- **Claude Code:** `tool_input.command` for Bash, `tool_input.file_path` for Write/Edit, `.cwd` for working directory.
- **OpenHands:** `tool_input.command` for terminal (same), `tool_input.path` for file_editor (not `file_path`), `working_dir` top-level field.

### Tool names

| Claude Code | OpenHands |
|---|---|
| Bash | terminal |
| Write\|Edit | file_editor |
| TodoWrite | task_tracker |

### Stop hook differences

- Claude Code passes `last_assistant_message` in stdin JSON for stuck/repetition detection.
- OpenHands passes `metadata.reason` (the agent's stop reason). Content is shorter and less suitable for similarity analysis but sufficient for basic idle detection.

### Environment variables

OpenHands injects `OPENHANDS_PROJECT_DIR`, `OPENHANDS_SESSION_ID`, `OPENHANDS_EVENT_TYPE`, `OPENHANDS_TOOL_NAME` into hook environment.

### Config format

- Claude Code: `.claude/settings.json` → `hooks.PreToolUse[].matcher` with PascalCase event types.
- OpenHands: `.openhands/hooks.json` → `pre_tool_use[].matcher` with snake_case keys. PascalCase is also accepted via `_normalize_hooks_input`.

## Gotcha

The worktree-write-guard must allow writes to `.openhands/` in addition to `.claude/` — otherwise the OpenHands hooks directory itself gets blocked by the guard.
