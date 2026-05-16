---
category: best-practices
module: harness
issue: null
related_pr: 3917
tags: [bash, cwd, tooling, harness, work-skill]
---

# Learning: Bash tool CWD persists across calls; work-skill prose is stale

## Problem

During the `/soleur:one-shot` run for PR #3917 (Next.js dep bump), a second Bash call `cd apps/web-platform && npm install --package-lock-only` failed with:

```
/bin/bash: line 1: cd: apps/web-platform: No such file or directory
```

The preceding call `cd apps/web-platform && bun install` had completed successfully ~60s earlier. The follow-up `cd apps/web-platform` resolved relative to the persisted CWD (`.worktrees/<branch>/apps/web-platform/`), where no sub-directory `apps/web-platform` exists.

## Root Cause

The current Claude Code harness preserves working directory between Bash tool calls. The system prompt is authoritative: **"The working directory persists between commands, but shell state does not."**

The work skill (`plugins/soleur/skills/work/SKILL.md`) contains a contradicting claim:

> "The Bash tool does NOT persist CWD across calls; a prior `cd /tmp/... && git clone ...` leaves subsequent commands running against the bare repo root..."

This prose is stale — it appears to describe an earlier harness behavior. Following the defensive `cd <relative>` prefix it implicitly encourages now produces relative-path failures.

## Solution

Dropped the redundant `cd` prefix on the next call and re-ran the command from the persisted CWD. Both `bun.lock` and `package-lock.json` regenerated cleanly to `next@15.5.18`.

## Key Insight

CWD persistence is **harness-version-specific**. Treat the system-prompt note as authoritative for the current session. When a prior `cd <dir>` succeeded in the same Bash tool session, either:

- **Anchor with an absolute path**: `cd /abs/path && cmd` — survives both persisted and non-persisted harnesses.
- **Omit `cd` and run from the persisted state**: simpler when you know the prior call landed where you want.

Avoid `cd <relative>` as a defensive prefix — it is the failure mode when CWD already persisted.

## Session Errors

- **`cd apps/web-platform: No such file or directory`** — Recovery: re-ran `npm install --package-lock-only` without the `cd` prefix. Prevention: prefer absolute paths in Bash chains; trust the system-prompt CWD-persistence note over older skill prose.

## Tags

category: best-practices
module: harness
