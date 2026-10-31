---
title: CLO ruling record, counts-only production-HOME census method (#10455)
date: 2026-10-31
status: C8 pending
---

# CLO ruling record: counts-only production-HOME census method

The CLO approved the exact census mechanism with conditions C1-C10 on 2026-10-31. The reasoning, the later rulings (C9 terminal
state, field cuts, sunset bound, executor, result publication) and the CTO rulings are recorded in
`knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/decision-challenges.md`; this file does not restate them.

This file carries one thing only: the C8 entry. C8 requires the CLO to re-read the final scanner, emitter and class-table diff
against the ruling before any real run. The entry is appended (append-only), naming the reviewed commit, after that re-read, as ONE line
that consists only of the word DISCHARGED, a space, and `sha=` followed by the 40 lowercase hex characters (the trigger script matches that
whole line exactly, so it must stand alone, with no other text on it); the trigger script refuses a real run unless the same commit is named here, in a `home-census C8 DISCHARGED`
comment on #10455 from a pinned author, and the served build's census paths equal that commit.

## Conditions the CLO set before recording C8 (dissent round, 2026-10-31)

1. The D1-D9 rulings are swept into the runbook, the ADR-075 addendum, the plan and compliance-posture with Superseded markers, and the absence greps are clean.
2. Test floors present: `account_state` alone reads `inconclusive`; an all-inconclusive result reads `inconclusive`, not `false`; a truncated or erroring class mixed with others reads `unknown`; the witness mutant is killed in the reviewer-run battery.
3. The `interpretation` change is mirrored in the server validator, the jq schema and the tests' independent allowlist.
4. The sunset constant is at most merge date + 30 days.
5. The script's working-tree self-check is present and tested.
6. A fresh DISCHARGED is needed if any bound file changes after the CLO's re-read, including a sunset-only change.

## C8 entries

C8 re-read: pending. No commit is discharged yet.
