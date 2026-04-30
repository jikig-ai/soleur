---
title: "guardrails stash guard test coverage gap"
date: 2026-04-30
category: test-failures
module: hooks
tags: [guardrails, hooks, test-coverage, git-stash, worktrees]
issue: "#2688"
---

# Learning: guardrails:block-stash-in-worktrees — test coverage gap for chained and pop variants

## Problem

The `guardrails:block-stash-in-worktrees` hook failed to fire during the one-shot agent run that produced PR #2683. The existing test (`tests/hooks/test_hook_emissions.sh`) covered only bare `git stash` — it had no cases for `git stash pop` or the chained pattern that actually appeared in PR #2683: `git stash && bun test ... 2>&1 | head -n 20 ; git stash pop`. The misleading comment "must be a worktree path" also implied that CWD was the discriminating factor, when in fact the hook is unconditional — CWD is irrelevant to whether stash is blocked.

## Root Cause

The hook regex `(^|&&|\|\||;)\s*git\s+stash` is correct and matches all variants, including the chained PR #2683 pattern. The hook itself was not the bug. The gap was in the test file:

1. Only one stash variant was tested (`git stash` bare), leaving `git stash pop` and chained patterns uncovered.
2. The likely actual failure mode for PR #2683 was version skew: the one-shot worktree branch may have predated the stash guard's addition to `guardrails.sh`, or the subagent context bypassed hook registration — not a regex defect.
3. Because the test didn't exercise `pop` or chained forms, any future regression in those patterns would have been invisible until it re-appeared in production.

## Solution

Three test cases replace the single existing case in `tests/hooks/test_hook_emissions.sh`:

1. **Bare command** (`git stash`) — existing case, updated comment to remove the misleading CWD requirement.
2. **Pop sub-command** (`git stash pop`) — new case covering the cleanup half of the stash pattern.
3. **Chained PR #2683 pattern** (`git stash && bun test ... ; git stash pop`) — new case that exactly reproduces the compound command from the incident.

## Key Insight

Hook tests must cover **every grammatical form** the hook's regex is designed to catch, not just the canonical form. A regex with alternation operators (`^|&&|\|\||;`) or sub-command matching is not proven by a test of the base case alone.

Generalizable rule: when a hook blocks a class of commands, the test suite should enumerate: (a) the bare command, (b) every significant sub-command, and (c) at least one chained/compound form representative of real agent behavior. If a compound form appeared in a production incident, include it verbatim — copy the exact string from the incident record with a `(PR #NNNN pattern)` label.

## Session Errors

- **worktree-manager.sh first attempt failed (exit 128)** — Recovery: re-ran the same command, succeeded on second attempt. Prevention: this is a known bare-repo initialization quirk; retry is safe.

## Prevention

When adding or auditing a `guardrails.sh` block rule:

1. For each regex alternation branch (`^`, `&&`, `||`, `;`, sub-commands), write one positive assertion in `test_hook_emissions.sh`.
2. If the issue record contains a verbatim command that triggered the incident, include it as a named test case (`_check "... (PR #NNNN pattern)"`) so the incident is permanently traceable to a test.
3. Do not rely on comment accuracy in tests — ensure the comment and the payload agree on what is actually load-bearing for the guard.

## Related

- `AGENTS.md` rule `hr-never-git-stash-in-worktrees`
- `tests/hooks/test_hook_emissions.sh`
- GitHub issue #2688
