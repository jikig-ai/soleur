---
title: "Pre-commit full-gate lock contention must remain attributable"
date: 2026-09-21
category: workflow-patterns
---

## Observation

The Codex rollout commit hook reached the full `test-all.sh` gate, emitted the contention banners and waited on the global advisory lock while unrelated long-running suites held it. The hook was interrupted after 120 seconds; focused migration and Codex suites had already passed.

## Rule

Treat a lock wait as an environmental verification gap, never as a green or red result. Preserve the hook's contention evidence, run the changed-surface suites independently, and disclose that the full gate remains outstanding before shipping. Do not stop a sibling test process to free the lock.

## Evidence

The interrupted run identified two sibling `test-all.sh` processes in a separate worktree and two sibling suites, then printed `LOCK_WAITING` and `LOCK_WAIT_HEARTBEAT`. Targeted verification passed 21 files and 197 tests.
