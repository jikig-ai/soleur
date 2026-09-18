---
title: A red-baseline blocker carries the host toolchain that measured it
date: 2026-09-18
category: workflow-patterns
module: scripts/test-all.sh
tags: [brainstorm, premise-validation, test-baseline, host-parity, lefthook]
issue: 8231
---

# Learning: a red-baseline blocker carries the host toolchain that measured it

## Problem

#8231's plan recorded "Phase 1 onward blocked on the green-baseline precondition: 20 pre-existing
red suites". The routing context for this session linked that precondition to #8112, the
main-branch health monitor. Both the count and the link were taken from the prior session's
evidence as settled facts.

## Solution

Before accepting the blocker:

1. **Re-run only the recorded red set** under today's toolchain. Use
   `test-all.sh --enumerate-commands all` to get each suite's argv, run the 21 names from the
   timing log's `FAIL` rows, and bound each with `timeout`. This took about 3 minutes, against 46
   minutes for a full battery. Result: 12 of 21 now pass, because the baseline was measured while
   `bun` was an unrunnable mise shim and `bun` now runs.
2. **Check CI on main** (`gh run list --workflow ci.yml -L 5`). It was green, so none of the
   residual reds is a defect on main. All nine are host-vs-CI divergence: a gitleaks shim with no
   version set, no GNU `/usr/bin/time`, Node 26, and an environment leak.
3. **Search open issues by symptom** (`gh issue list --search "gitleaks local OR /usr/bin/time OR
   scratch-root"`). Every residual red already had an owner: #8238, #8250, #8261, #8263, #8266.
   The blocker was a bundle of already-filed issues, not a methodology gap.

## Key Insight

A "blocked on N red" precondition is a measurement of one host at one moment. Its size depends on
that host's toolchain, which changes between sessions. Re-derive the count with a subset re-run,
and check CI on main, before the blocker bounds the options. Here that turned "change the plan's
method or wait on #8112" into "fix five filed issues, then resume the plan unchanged".

A second finding, stated precisely because the first draft of this paragraph overstated it and was
caught in review: `lefthook` is **not** on this host's PATH, and the shim's fail-open branch is
real — rewriting the binary path to `/nonexistent` makes `.git/hooks/pre-commit` print
`Can't find lefthook in PATH` and **exit 0**, so the gate would fail open silently. But the gate is
**not** dark here today: the shim carries a hardcoded third fallback
(`/tmp/soleur-merge-npm-cache/_npx/…/lefthook-linux-x64/bin/lefthook`), that binary exists and
runs (`lefthook v2.1.6`), and invoking the shim executes the full pre-commit gate at rc 0.

The true state is *more* fragile than "it does not run", not less: the local gate depends on a
binary under `/tmp`, which any reboot removes — and the failure mode when it disappears is the
silent exit-0 above, not an error. The general lesson stands and the specific host claim did not:
a durable sentence about a host is a measurement with a shelf life, so write what the command
returned rather than what the mechanism implies (#8271 tracks the fail-open itself).

## Session Errors

1. **`gh issue view --comments --json` rejected** (the flags are mutually exclusive). Recovery:
   `--json comments`. **Prevention:** use `--json comments` whenever comments are needed as data.
2. **`tail -4 a b c` rejected** with multiple files. Recovery: `tail -n 4`. **Prevention:** always
   write `-n N`.
3. **Inherited "#8112 is the home for the red baseline" framing.** It came from the prior
   evidence file into my routing context without being checked. Recovery: CI green on main
   refuted it. **Prevention:** new brainstorm premise-probe bullet (below). For any recorded red
   baseline, re-run the red set and check CI on main before accepting its framing.
4. **A research subagent labelled 3 suites GENUINE-ON-MAIN without consulting CI.** Recovery:
   the green `ci.yml` push run on main refuted it. **Prevention:** the existing brainstorm guidance
   ("a subagent's COUNT is a claim to re-derive") applies. Classification claims get the same
   treatment.
5. **A `gh run list` awk grouping cut workflow names to their first word.** Recovery: re-queried
   with `--workflow ci.yml`. **Prevention:** filter by `--workflow <file>` rather than grouping
   display names.
6. **Session-start preamble skipped (`plugin-root-unverified`, `CLAUDE_PLUGIN_ROOT` unset).**
   Recovery: none needed for this session. **Prevention:** already tracked (#7442).
7. **The lefthook shim fails open when lefthook is absent.** Both commits this session ran no git
   hooks. Recovery: filed as a tracked issue. **Prevention:** the shim must fail closed, or the
   session-start preamble must detect a missing lefthook.
8. **A Bash `cd` into the main checkout moved the session CWD out of the worktree.** It was a
   read-only `.git/hooks` inspection. Recovery: absolute worktree paths for everything after.
   **Prevention:** use `git -C` and absolute paths. Never `cd` to the main checkout from a worktree
   session.

## Tags

category: workflow-patterns
module: scripts/test-all.sh
