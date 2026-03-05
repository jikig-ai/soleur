---
title: GitHub issue auto-close requires keyword syntax, not parenthetical references
date: 2026-02-22
updated: 2026-03-05
category: workflow-patterns
tags: [github, pr, issue-tracking, automation]
symptoms:
  - Issue remains open after PR is merged
  - PR title references issue number but uses parentheses instead of closing keyword
---

# GitHub Issue Auto-Close Requires Keyword Syntax

## Problem

PR #237 was merged with the title:

```
feat: add test-fix-loop skill for autonomous test-fix iteration (v2.26.0) (#216) (#237)
```

Issue #216 remained open after merge because `(#216)` in the title is not recognized by GitHub as a closing reference. GitHub treats parenthetical `(#NNN)` as a plain cross-reference, not a close action.

This recurred with PR #444 and issue #377 on 2026-03-05.

## Root Cause

GitHub only auto-closes issues when the PR **body** (not title) contains a keyword followed by the issue reference. Valid closing keywords:

- `Closes #216`
- `Fixes #216`
- `Resolves #216`

These must appear in the PR **description/body**, not the title. Title references like `(#216)` create links but do not trigger auto-close.

## Fix

The `/ship` and `/merge-pr` skills now include automatic issue detection and `Closes #N` in PR bodies:

1. `/ship` Phase 6 detects associated issues from branch name patterns, commit messages, and conversation context
2. PR body templates include `Closes #N` when an issue is detected
3. `/merge-pr` Phase 4 applies the same detection before creating PRs
4. Multiple issues are listed as `Closes #N, Closes #M`

## Prevention

- The `/ship` skill's "Detect Associated Issue" step checks branch names (e.g., `fix/123-desc`), commit messages (`#N` references), and user context before every PR creation or edit
- PR body templates in both `/ship` and `/merge-pr` include the `Closes #N` line conditionally
- The conventional commit title can still reference the issue parenthetically for traceability, but the body contains the keyword for auto-close
