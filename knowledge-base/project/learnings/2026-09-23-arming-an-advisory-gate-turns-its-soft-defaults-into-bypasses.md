---
title: "Arming an advisory gate turns its soft defaults into bypasses"
date: 2026-09-23
category: workflow-patterns
module: ci / encryption-posture
tags: [ci, required-checks, guards, mutation-testing]
issue: 6907
pr: 8619
---

# Learning: when a gate goes from advisory to blocking, re-read every lenient branch

## Problem

#6907 armed the encryption-posture ledger sweep by adding it to the `needs:` of the required
`test` aggregator. The change itself was three lines, and its first test suite pinned the
wiring by spelling: the needs entry, an env substring, a substring of the sweep command.
A 7-agent review found the gate could be defeated or turned against the repo in ways a green
suite could not see.

## Solution

1. **Soft defaults became bypasses.** Code written for an advisory gate degrades gently on
   purpose: a missing ledger printed "not yet seeded -> PASS". Blocking, that is `git rm` as a
   one-line bypass. It now fails.
2. **Clocks became freezes.** Eight exceptions expire on one date. Advisory, an expiry was a
   red row nobody had to act on; blocking, it reds every human PR on that day. The sweep now
   warns 14 days ahead.
3. **Wiring pinned by behaviour, not spelling.** A 26-mutation harness (step-level `if`,
   `|| true`, `--today`, `--repo-root`, `--check-templates`, env expressions that always read
   success, dropping `if: always()` on the aggregator, duplicate YAML keys) went from 16
   survivors to 0 non-equivalent. The checks now require the exact run line, the exact env
   expression, and that the aggregator itself can still go red.
4. **A prerequisite argument moved with it.** Bot PRs fabricate `test`, so the sweep's green is
   fabricated too. The unreachability argument only held for runs on `main`; the action now
   refuses to run elsewhere, and the note sits where an `ALLOWED_PATHS` editor will read it.

## Key Insight

Promoting a check from advisory to blocking changes the meaning of every lenient branch it
already had: a graceful skip becomes a bypass, a hard date becomes a freeze. Before arming,
list every branch that returns success without doing the work, and every input that can red
the gate for reasons unrelated to the diff.

## Session Errors

1. **A shell command included `git stash list`**, which the worktree guard blocked.
   **Prevention:** never chain a stash subcommand into a shell probe; the hook blocks all of
   them in worktrees.
2. **The first wiring suite pinned spelling**, and 16 of 26 mutations survived it.
   **Prevention:** for a merge gate, mutate the workflow's wiring (if, continue-on-error, run
   line, env expression, the aggregator's own if) before claiming coverage.
3. **The ADR claimed a soak window it had not measured** ("since 2026-09-08" for a 1,000-run
   sample that covered five days). **Prevention:** state the date span a capped query actually
   returned, never the span it was asked for.

## Tags

category: workflow-patterns
module: ci
