# Auto Mode as Default Permission Mode

**Date:** 2026-03-24
**Status:** Decided

## What We're Building

Set Claude Code's `defaultMode` to `"auto"` in `.claude/settings.json` so that all Soleur CLI users get auto mode by default. Auto mode uses a classifier model to decide whether each tool call is safe to run without prompting, replacing the standard permission-prompt-on-first-use behavior.

## Why This Approach

- Auto mode is the safer alternative to `--dangerously-skip-permissions` — it provides autonomous operation with built-in safety checks
- The existing PreToolUse hooks (guardrails.sh, pre-merge-rebase.sh, worktree-write-guard.sh) fire unconditionally regardless of permission mode, maintaining all current safety guardrails
- The existing `permissions.allow` rules are evaluated before the classifier, guaranteeing zero friction on core workflow commands (git commits, worktree manager)
- Single-line change with immediate benefit — no new code, no new patterns

## Key Decisions

1. **Scope: CLI users only.** Web platform, Telegram bridge, and GitHub Actions are out of scope. Each has its own permission model that already works.
2. **Keep existing allow rules.** The 5 `permissions.allow` entries stay for defense-in-depth. They guarantee core commands pass without hitting the classifier.
3. **Keep existing hooks.** All 3 PreToolUse hooks remain unchanged. Hooks fire before permission mode evaluation and cannot be bypassed by auto mode.
4. **No autoMode.environment config.** The `autoMode` configuration block is deliberately not read from shared project settings (`.claude/settings.json`) by Claude Code's design. Users who want to customize trusted infrastructure do so in their own `~/.claude/settings.json` or `.claude/settings.local.json`.
5. **No template file.** No `.claude/settings.local.json.example` needed — users can discover auto mode configuration through Claude Code's own docs.

## Open Questions

None — scope is fully decided.
