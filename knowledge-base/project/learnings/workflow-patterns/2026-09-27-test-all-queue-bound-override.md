---
title: Bound the advisory test-all queue for a waiting local hook
date: 2026-09-27
category: workflow-patterns
module: test-all-contention
---

## Problem

A commit hook can wait behind other worktrees for the default one-hour
`test-all` queue window. Interrupting it discards the current verification run
without saving time for later attempts.

## Prevention

When a local hook is demonstrably queued and a fresh `--capacity` probe shows
adequate resources, pass a bounded `TC_QUEUE_TIMEOUT` to the next commit
attempt. The runner still executes the affected suites after the bound, emits
its contended warning, and any failed suite must be isolated and rerun before
its result is accepted.
