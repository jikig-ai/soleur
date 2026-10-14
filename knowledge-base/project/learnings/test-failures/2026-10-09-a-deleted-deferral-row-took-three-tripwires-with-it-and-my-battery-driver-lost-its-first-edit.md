---
title: "A deleted deferral row took three tripwires with it, and my battery driver silently lost its first edit"
date: 2026-10-09
category: test-failures
module: .claude/hooks/grep-q-pipe-guard.test.sh + tests/
issues: [9217]
---

# Slice S4 of the grep -q drain: what the row deletion removed beyond the canaries

## Problem

S4 converted 181 lines in 23 files under `tests/` and deleted the `tests/*` deferral row. The plan already carried the S3 lesson (plant a violating-file canary under each shape the deleted row owned, mutation-prove both directions), and the author's Guard 1 matrix (rows 1 to 15) was green as predicted. A twelve-seat review still found three gaps in the guard, all in what the row deletion removed.

## What was measured

1. **The row was also a stale-row tripwire for the whole subtree.** While `tests/*` existed, a `.gitignore` entry hiding `tests/` produced zero hits and failed `stale deferral`. With the row gone and no `tests/` entry in `SWEEP_CANARIES`, appending `/tests/` to `.gitignore` left the guard green at 1648 swept files (down from 1765). The fix is a canary root, not another probe check.
2. **Canaries one directory deep do not witness a depth-keyed exclusion.** `':(exclude,glob)tests/fixtures/*/**'` and `'**/fixtures/*/**'` spared canaries sitting directly under `fixtures/`, and the second hid 112 files repo-wide. Two nested canaries closed both.
3. **The owner comparison was pinned by one matrix row.** Replacing the `real_got == real_want` comparison with `true` plus a resurrected `tests/* <= 1` row and a covering hit stayed green. A control row (`tests/* <= 99` must leave exactly the non-`tests/` canaries undeferred) and a rule that no row may start with `tests/` now back it; the second also closes the test-shaped narrow row (`tests/commands/*.test.sh <= 1`) that survived as matrix row 14.
4. **Six hand-synced places for one fact.** The mkdir list, the planted names, the sorted expectation, the count literal and two message strings had to move together. One `real_paths` array plus a single `REAL_PLANTED` literal and a derived expectation leaves one list and one number for the next slice to edit.

## Prevention

- When a slice deletes the last deferral row for a subtree, replace each guarantee the row gave, not only the canaries: (a) a `SWEEP_CANARIES` root so the subtree dropping out of the population reads UNRESOLVED, (b) canaries at the depths the subtree really has, (c) a control that pins the owner comparison itself, (d) a rule rejecting any resurrected row under the subtree's prefix.
- Keep the probe's planted set in one array with one pinned count literal and derive every expectation from it.
- A reviewer-added check that changes a hand-verified file needs its own `hand-edits.txt` entry, and every artifact quoting the old counts needs an append-only addendum rather than an in-place edit.

## Session Errors

1. **The mutation driver's multi-edit helper re-read the ORIGINAL file for a second edit to the same file**, so rows 12, N4 and N4b first ran with only their last edit (row 12 read rc 1, which was one of its two edits alone). Recovery: the implausible rc (row 12 is a documented survivor) triggered a standalone reproduction; the helper now reads current content and the three rows were re-run. **Prevention:** a battery driver's edit helper reads the file's current content, and any row that edits one file twice gets a standalone reproduction before its verdict is recorded.
2. **A `str.replace` helper changed the driver's `exclude()` spelling silently** (no `assert`), so the missing closing quote was only noticed by grepping the result. Recovery: grepped the line and rebuilt it. **Prevention:** every scripted replacement asserts its old text occurs exactly once and prints the changed line back.
3. **A reviewer-added comment edit changed a line count in a converted file and `verify` flagged it as unexplained**, forcing a `hand-edits.txt` entry and `hand-edited: 7` to become `10` across the evidence. Recovery: made the edit line-count neutral, recorded it, appended an addendum. **Prevention:** before touching a verified file during review, check whether `verify` will see the hunk, and prefer a fix in a file `verify` does not cover.
4. **I proposed a batch of heavy local gates (ratchet lane, vacuity floor, orphan and capture lints) on a host at load 25 to 33 after the user had already decided CI is the full-battery gate**, and the call was declined. Recovery: dropped them and recorded them as left to CI. **Prevention:** when a standing decision defers the long local gate to CI and the host is contended, apply it to every non-essential local gate, not only the one it was stated for.
5. **A report-only seat ran `scripts/test-all.sh --print-selection` despite the brief forbidding runners**, and it hung under load (exit 144). Recovery: the seat re-ran its cases with a 4 s timeout. **Prevention:** brief report-only seats with the specific command they may not run, not only the category.
6. **The plan's guard-diff figure (7 added / 7 removed) disagreed with the measured 6 / 7**, found by the code-quality seat. Recovery: addendum in `evidence.md` and a pointer under the plan's Acceptance Criteria. **Prevention:** a plan's rehearsal numbers are preconditions; re-measure at work start and write the measured figure where the AC quotes it.
