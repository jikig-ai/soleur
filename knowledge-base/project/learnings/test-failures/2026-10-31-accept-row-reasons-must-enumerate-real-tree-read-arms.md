---
title: "accept-row 'never reads' reasons must enumerate every real-tree run of the suite — or cite the always-on twin that duplicates it"
date: 2026-10-31
category: test-failures
tags: [ci-pr-affected, accept-rows, review-findings]
---

# Learning

## Problem

A `scripts/ci-pr-affected-audit.accept.tsv` reason of the form "the suite never reads or executes `<exempted path>`" is a universal claim about the suite's read surface — and it fails on suites with **real-tree arms**. `scripts/betterstack-emitter-read` (`lint-betterstack-emitter-read.test.sh`) has two no-arg invocations of the guard that default `TREE` to `REPO_ROOT` — the FLOOR arm at `:335` and the LIVE arm at `:347` — both of which `git grep` + `strip_code`-read every candidate probe file, including the exempted one. A "never reads" reason for that pair is false twice over; enumerating only the LIVE arm (as a first review fix did) is still false once.

The defect matters because the reason column is the only narrative a `stale-accept` triager reads — and a false "never reads" precedent is copy-pasteable into a future accept row for a suite that has **no** always-on twin, where it becomes a real false negative. Two pre-existing `inngest-luks-keeper-dark-11265` rows carried a second false description ("header comment names the installer") for anchors that are actually heredoc usage text (`betterstack-query.sh:109/110`) — whole-line comments are blanked by the audit's `strip_comments`, so a header comment can never produce a live anchor at all.

## Solution

When an accept row's reason asserts the suite does not read the exempted file, the claim must be checkable:

1. Grep the suite's test file for **every** invocation of the guard/probe that lacks a fixture-tree argument (`bash "$GUARD"` with no `$TREE` arg defaults to `REPO_ROOT`) — enumerate them by line number in the reason.
2. If the exemption is safe only because a separately-registered **always-on** suite duplicates the same real-tree read surface (e.g. `scripts/betterstack-emitter-read-live` in `ALWAYS_ON_SUITES`, `scripts/lib/test-affected-paths.sh`), say that — that is the load-bearing fact, not "never reads".
3. Prefer the runbook's closed kind grammar (`false-positive: <kind>: <file:line>: <evidence>` — `message`, `data row not fed to a read loop`, …) over freeform prose; the `kind:` prefix forces the writer to name *why* the line is a mention.
4. Verify the cited anchor's line content before describing it — `strip_comments` blanks whole-line comments before scanning, so "comment names X" reasons are suspect on their face.

## Key Insight

An accept row exempts a *boundary line*, but its reason is judged against the suite's *entire read surface* — arms, env-overridden runs, and fixture-vs-real-tree invocations all count. The exemption survives review on the strength of its duplication argument (an always-on twin runs the same walk), never on an enumeration of reads that can silently miss an arm.

## Evidence

- Session: one-shot on #11694 (PR #11734), 2026-10-31. Security-sentinel flagged the false "never reads" claim (P2); the first fix enumerated only the LIVE arm and the fix round flagged the missed FLOOR arm (P2 residual). Both pre-existing stale `luks-keeper` reasons were corrected in the same pass.
- `lint-betterstack-emitter-read.test.sh:335` (FLOOR, `EMITTER_READ_MIN_POP=100000`) and `:347` (LIVE) are the only no-arg real-tree runs; the floor verdict fires at guard `:365`, after the candidate walk reads every probe at `:275`/`:283`.
