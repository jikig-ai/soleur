---
title: "Recheck main after resync before review or push"
date: 2026-09-30
category: workflow-patterns
module: git-worktrees
---

## Problem

`origin/main` advanced after a feature worktree had been fetched and merged. A
later ancestry check then correctly refused the push because the feature head
did not contain the newer main commit.

## Prevention

Fetch `origin main` immediately before the final ancestry check and review
setup. If main advanced during the session, merge the new head, recheck
ancestry, then push and review that exact feature SHA.
