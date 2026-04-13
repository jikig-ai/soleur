---
title: "CodeQL to Issues: Invalid Workflow Trigger and Polling Alternative"
date: 2026-04-13
category: integration-issues
tags: [github-actions, codeql, code-scanning, workflow-triggers, ci]
---

# Learning: CodeQL to Issues — Invalid Workflow Trigger and Polling Alternative

## Problem

The `codeql-to-issues.yml` workflow was failing on every push with "This run likely failed
because of a workflow file issue" and zero jobs executed. The failure was pre-existing (7/8
workflows passing) and affected all branches. The workflow used `on: code_scanning_alert:
types: [created]` as its trigger.

## Root Cause

`code_scanning_alert` is **not** a valid GitHub Actions workflow trigger. It is a webhook-only
event. GitHub Actions supports approximately 33 valid `on:` event triggers (documented at
<https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs>).
`code_scanning_alert` does not appear in that list.

When an `on:` block references an unknown event, GitHub Actions cannot parse the workflow file
and creates a failed run entry with zero jobs on every push. This was introduced in PR #2029
without validating the event name against the official trigger list.

## Solution

Replace the invalid `on: code_scanning_alert` trigger with a polling approach:

```yaml
on:
  schedule:
    - cron: '0 6 * * *'   # daily at 06:00 UTC
  workflow_dispatch:       # manual trigger
```

Change the implementation from event-driven (react to each alert as it fires) to polling-based
(query the code scanning API for all currently open alerts). Apply false-positive filtering:

- Only process alerts with `critical` or `high` severity — skip `medium` and `low`.
- Only process `open` state alerts — skip `dismissed` and `fixed`.
- Deduplicate by searching existing GitHub issues before creating a new one.

## Session Errors

1. **`git fetch origin main:main` failed** — local `main` was checked out in another worktree,
   making the ref locked for fast-forward.
   **Prevention:** Use `origin/main` directly (`git show origin/main:<path>`) when local `main`
   may be locked in a parallel worktree.

2. **`git show main:<path>` returned stale data** — the local `main` ref was behind `origin`
   because the fetch had failed.
   **Prevention:** After any fetch failure, always use the `origin/main` ref rather than the
   local `main` ref to read files.

3. **First worktree was created from stale local `main`** — worktree-manager used the locked
   local `main`, so the worktree started from an outdated base. It was auto-cleaned.
   **Prevention:** worktree-manager should fall back to `origin/main` when local `main`
   fast-forward fails.

4. **`gh pr view --json merged` failed** — `merged` is not a valid JSON field for `gh pr view`.
   **Prevention:** Use `mergedAt` (returns a timestamp or null) instead of `merged`. Verify
   field names with `gh pr view --help` before scripting.

## Key Insight

Not all GitHub webhook events are valid GitHub Actions workflow triggers. Always verify an
event name against the official Actions trigger list before adding it to an `on:` block. When
a webhook event has no corresponding Actions trigger, schedule-based polling (`cron`) plus
`workflow_dispatch` is a robust alternative: it trades real-time response for simplicity and
debuggability, and deduplication logic in the job body prevents duplicate issues.
