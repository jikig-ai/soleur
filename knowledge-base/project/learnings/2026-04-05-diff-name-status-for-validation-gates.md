# Learning: Use --name-status not --name-only for diff-based validation gates

## Problem

The preflight lockfile consistency check used `git diff --name-only` to detect changed lockfiles, then FAILed when only one lockfile in a dual-lockfile directory appeared in the diff. This created a false positive when a PR *adds* a new lockfile (e.g., adding `package-lock.json` alongside an existing `bun.lock`) — the check penalized the exact fix AGENTS.md prescribes.

## Solution

Use `git diff --name-status` instead of `--name-only`. This returns status letters (M=modified, A=added, D=deleted) alongside paths. Only **modified** (M) lockfiles trigger the consistency check. Added (A) or deleted (D) lockfiles are one-time structural changes that do not require sibling updates.

## Key Insight

When writing diff-based validation gates (preflight checks, CI guards, pre-commit hooks), always distinguish between modification types. `--name-only` treats all changes equally, which causes false positives on structural changes (adding/removing files). `--name-status` provides the granularity needed to write correct rules.

## Session Errors

**Skill description budget exceeded (1801/1800)** — Adding 3 words to the preflight description exceeded the 1800-word skill budget. Recovery: shortened "lockfile consistency" to "lockfiles". Prevention: check word count mentally before editing skill descriptions near budget ceiling.

**False positive on new lockfile addition** — Caught by agent-native-reviewer during /review phase. Recovery: rewrote check to use `--name-status` with M-only trigger. Prevention: when writing diff-based checks, always consider the A/M/D distinction in the design phase, not just during review.

## Tags

category: logic-errors
module: plugins/soleur/skills/preflight
