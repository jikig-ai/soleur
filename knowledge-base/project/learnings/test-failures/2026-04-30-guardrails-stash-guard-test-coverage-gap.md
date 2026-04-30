---
title: "guardrails stash guard test coverage gap"
date: 2026-04-30
category: test-failures
module: hooks
tags: [guardrails, hooks, test-coverage, git-stash, worktrees]
issue: "#2688"
---

# Learning: guardrails:block-stash-in-worktrees — test coverage gap for chained and pop variants

## Scope

This learning documents a **test-coverage gap** discovered while investigating issue #2688 (the bypass that produced PR #2683). It does **not** identify the root cause of the PR #2683 bypass — that mechanism remains unverified. See "Open Question" below.

## Problem

The `guardrails:block-stash-in-worktrees` hook failed to fire during the one-shot agent run that produced PR #2683. The existing test (`tests/hooks/test_hook_emissions.sh`) covered only bare `git stash` — it had no cases for `git stash pop`, the `&&`-chained pattern that actually appeared in PR #2683, the `||` alternation branch, or any negative case proving the guard does not over-fire. The misleading comment "must be a worktree path" also implied that CWD was the discriminating factor, when in fact the hook is unconditional — CWD is irrelevant to whether stash is blocked.

## What This Fix Addresses

The hook regex `(^|&&|\|\||;)\s*git\s+stash` is correct and matches all variants, including the chained PR #2683 pattern (verified: `bash tests/hooks/test_hook_emissions.sh` passes with the new cases). The hook itself was not the bug. The fix is purely test-side:

1. Only one stash variant was tested (`git stash` bare), leaving `git stash pop`, `&&`-chained, and `||`-chained patterns uncovered.
2. No `_check_silent` companion existed — a regex that degenerated to "always emit on `git`" would have passed every positive case.
3. Because the test didn't exercise `pop` or chained forms, any future regression in those patterns would have been invisible until it re-appeared in production.

## Open Question (Unverified)

Why did the hook not fire during PR #2683? Hypotheses, in priority order:

1. **Version skew** — the one-shot worktree branch may have predated the stash guard's addition to `guardrails.sh`. Provable in seconds: `git log --oneline -- .claude/hooks/guardrails.sh` against PR #2683's branch SHA.
2. **Hook registration drift** — `.claude/settings.json` in the worktree may not have wired `guardrails.sh` into `PreToolUse.Bash`.
3. **Subagent context bypass** — the `/soleur:one-shot` Task delegation may invoke Bash via a path that skips PreToolUse hooks.
4. **`set -euo pipefail` short-circuit** — a hook preamble error (jq parse, var bind) could exit 0 before the stash check.

Issue #2688 remains open as the tracker for proving (or refuting) these hypotheses. This PR uses `Ref #2688`, not `Closes`.

## Solution (Test-Side Only)

Five cases replace the single existing case in `tests/hooks/test_hook_emissions.sh`:

1. **Bare command** (`git stash`) — existing case, updated comment to remove the misleading CWD requirement.
2. **Pop sub-command** (`git stash pop`) — covers the cleanup half of the stash pattern.
3. **`&&` chain (PR #2683 pattern)** — exactly reproduces the compound command from the incident.
4. **`||` chain** — covers the otherwise-untested alternation branch.
5. **Negative `_check_silent`** — proves the guard does not over-fire on substrings like `gitstash` or `rg stash`.

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
