# Learning: a probe's RETIREMENT: line under-enumerates its touch-points

## Problem

`scripts/followthroughs/ci-leg-durations-8006.sh` carried the convention's
`RETIREMENT:` header listing 3 deletion sites (probe file, `.test.sh`,
`run_suite` registration). The actual footprint was 5: the header missed the
`scripts/suite-shard-legs.tsv` manifest row (a phantom-label RED if it had
survived) and a mid-document regen-trigger bullet in the sharding runbook
that named the probe's breach signal — a signal that can never fire once
the probe is gone.

## Solution

When writing a `RETIREMENT:` line, enumerate by grep over live-code dirs
(`scripts/`, `.github/`, `plugins/`) AND the unnumbered stem, including
generated-registry rows (`*.tsv` manifests, index files) and mid-document
mentions in runbooks — not just the file's own siblings. At retirement
time, census again: the true footprint is whatever `git grep <stem>` finds
minus historical knowledge-base records, and every hit needs a
disposition in the plan before the deletion commit.

## Key Insight

A RETIREMENT note written at probe-creation time describes the footprint
the author *expected*; registries and runbook references accrete later.
The note is a checklist seed, not the checklist — the closing census is
the load-bearing step (cf. the earlier full-class-grep learning,
2026-05-09, which this extends from the consumer side to the writer side).

## Tags

followthrough, retirement, cleanup, census, convention
