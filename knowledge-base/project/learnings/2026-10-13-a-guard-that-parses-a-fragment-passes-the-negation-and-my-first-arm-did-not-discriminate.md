---
title: "A guard that parses a fragment of the declaration passes its negation, and my first mutation arm did not discriminate"
date: 2026-10-13
category: test-failures
tags: [mutation-testing, vacuity, guard-predicate, terraform, hcl-comments, fixtures, review-panel]
issue: 7335
related:
  - 2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md
  - 2026-08-06-i-deleted-the-measurement-that-was-my-own-evidence.md
---

# Learning: a fragment-parsing guard passes the negation of what it guards

## Problem

Issue #7335 asked for an orientation test for `local.registry_arch` (a Terraform ternary that selects
between two OCI repositories). The premise was stale: the guard (R3) had landed two hours after the
issue was filed, so the real work was to prove the existing guard could go red and to pin the one
precondition `registry-userdata-budget.sh` leans on. The first version shipped 5 R3 arms and an R4
guard, all green at 139/0, and a 5-seat panel still found two P1s inside it:

- R3 extracted the `startswith(...)` text, the prefix and the two branch values, then replayed them.
  It never looked at the rest of the line, so `!startswith(...)`, `startswith(...) || true` and
  `startswith(...) == false` all printed 1. Those are inversions, the exact defect R3 exists for.
- The comment stripper handled `#` and `//` only. A multi-line `/* ... */` around the declaration or
  the precondition hid it from Terraform and not from the predicate.

## Solution

- Pin the WHOLE declaration to the one grammar the replay understands (anchored both ends) and require
  exactly one line-start declaration, so a decoy or a second declaration cannot hide the real one.
- One shared `_strip_hcl_comments`: strip line comments first (they are line-scoped; a glob such as
  `infra/*` inside one must not open a block comment), then `/* */` spans.
- Harness controls: the verdict is computed from the mutated file (damaging edit is RED, benign edit
  is GREEN), a crashed predicate is `UNRESOLVED` rather than a pass, a malformed edit is `SEDERR`.
- Scope the doppler_arch wiring pin (R5) to the registry resource, with an anchor arm and a
  duplicate arm. Set `MIN_ASSERTIONS` to the measured count, not measured-plus-slack.

## Key Insight

Two checks a green suite cannot give you:

1. **A predicate that parses a fragment of a declaration is satisfied by every edit that leaves the
   fragment alone.** Ask what the rest of the line can say. The replay over a fixture table proves
   the fragment, never the expression.
2. **A new arm is proven only when the implementation it targets is reverted and the arm goes red.**
   My first arm for "a `#` comment containing `/*` stays GREEN" put the comment on the declaration
   line, so the OLD (block-first) stripper still kept the declaration prefix and the arm passed under
   both orders. Moving the comment above the declaration made it discriminate. The arm was green and
   looked right; only reverting the stripper order showed it pinned nothing.

## Session Errors

1. **A `sleep N` chained before a `cat` was blocked by the harness.** Recovery: read the task output
   file with Read. Prevention: wait with a Monitor until-loop or a background-task notification,
   never a foreground sleep.
2. **`/usr/bin/time` does not exist on this host.** The isolated re-runs exited 127 and wrote
   `rc=127` lines. I noticed the missing binary from the log text. Recovery: re-ran with `$SECONDS`.
   Prevention: derive elapsed time from `$SECONDS` in the wrapper, and treat a verdict file written
   by a wrapper whose first line is `No such file` as un-run.
3. **`lint-trap-tempfile-ownership.py` has no `--base` flag.** Recovery: ran it on the file.
   Prevention: copy a lint's invocation from `scripts/test-all.sh`, not from memory.
4. **A report-only review seat ran `git checkout --detach` on the shared worktree.** It restored the
   branch itself and I verified `git branch --show-current` after the panel. Prevention: already
   covered by the review sharp edge on report-only seats; the post-panel branch check caught it.
5. **Three suites reported RED in the full registered-suite run (`ci-deploy`,
   `web-host-provisioner-parity-mutation`, `workspaces-boot-unlock`) and all passed alone.** Cause:
   load average 54 pushed them over their per-suite time bounds (360 to 900 s). Prevention: read the
   `exceeded its Ns bound` line before blaming the diff, then re-run each alone; none of the three
   references the edited file.
6. **My first mutation arm for the stripper order did not discriminate** (see Key Insight).
   Prevention: revert the implementation the arm targets and require the arm to fail, before
   committing it.
7. **The issue premise was stale** (the guard the issue asked for already existed). The plan's
   research caught it by running the INVERT and DELETE mutations first. Prevention: measure the
   issue's headline claim on a sandbox before sizing the work.

## Tags

category: test-failures
module: apps/web-platform/infra
