---
date: 2026-09-27
problem_type: workflow_gap
component: ci
module: shard-totality-mutations
severity: low
tags: [same-commit-knock-on, doc-drift, enumeration-coverage, review-synthesis, tiling-guard]
issue: 8990
pr: 9027
---

# Learning: a same-commit knock-on list must grep the prose carriers of a count, not only the code surfaces

## Problem

PR #9027 bumped `DECLARED_TOTAL` 24→27 and re-split the `shard-totality-mutations` ci.yml
matrix in one commit — the battery's declared-row-drift check and the guard's ci.yml tiling
arm force that coupling, and the plan enumerated the knock-on set correctly *for code*: the
constant, the battery header, the matrix, the job comments.

Three review seats then independently flagged three instances of **one** gap the enumeration
had missed — prose that carries the same count and now contradicts the code:

- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` topology table
  still read `--rows 1-12` / `13-24` (flagged P2 by two seats — a live operational doc, not a
  historical artifact).
- `ci.yml`'s sizing comment had been mechanically rewritten to "the serial **27-row** battery
  measured ~9.5 min" — re-attributing a measurement taken on the 24-row battery to a
  configuration never run.
- The plan's own "Leg cost" line carried two arithmetic errors (`+36 s` where its own
  ~24 s/row gives ~72 s; "`15-27` leg becomes the heavier one (13 vs 14)" — backwards).

The count's referent (`24` / `twenty-four` / `1-12` / `13-24`) lived in a runbook table row
and a measured-claim sentence — both invisible to every mechanical drift check the battery
and guard own.

## Solution

When a change bumps a count, re-splits a range, or renames a contract constant, the same-commit
knock-on list is not complete until a prose sweep runs: grep the *referent's spellings*
(`24`, `twenty-four`, `1-12`, `13-24`) across `knowledge-base/`, workflow comments, and the
plan itself — not only the files the diff touches, and not only code. Each hit is either a
carrier to update or a legitimate historical record to leave alone (dated "Measured history"
entries stay).

For measured-claim prose specifically: when the count moves, keep the measurement attached to
the configuration it was *taken on* ("measured ~9.5 min at 24 rows"), never splice the new
count into the old measurement.

## Key Insight

A mechanical knock-on gate (declared-row drift, tiling arm) can only see code. Its existence
makes the prose carriers *more* likely to drift, not less — reviewers trust the gate to have
covered the count, so nobody greps it. The review panel caught this because three different
lenses all read prose; a lone code review would not have.

## Session Errors

1. `GUARD_RC=0` pipe artifact: `bash guard.sh | tail; echo $?` read `tail`'s exit status, not
   the suite's — printed `0` on a RED run. **Prevention:** capture rc before piping
   (`bash f.sh > log; rc=$?; tail log`), or read the suite's own verdict line as the
   authoritative signal (it is designed for exactly this).
2. `gh issue create` refused by the filing gate ("names no user-visible consequence") until
   `--label meta/machinery` was added — the correct exit for a guard/verification-machinery
   finding, and the error text named it. **Prevention:** when filing machinery-class findings,
   add `meta/machinery` on first attempt (it is also what keeps them out of user-facing drains).

## Tags

same-commit-knock-on, doc-drift, structural-cause-roll-up, review-synthesis
