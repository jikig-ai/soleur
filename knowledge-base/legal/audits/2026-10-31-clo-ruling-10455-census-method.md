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
against the ruling before any real run. The entry is appended (append-only) in the form below, naming the reviewed commit, after
that re-read; the trigger script refuses a real run unless the same commit is named here, in a `home-census C8 DISCHARGED`
comment on #10455 from a pinned author, and the served build's census paths equal that commit.

## C8 entries

C8 re-read: pending. No commit is discharged yet.
