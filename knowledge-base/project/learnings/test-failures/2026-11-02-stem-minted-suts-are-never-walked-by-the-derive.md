---
title: "affected-index: stem-minted SUTs are never walked by the derive — even literal `source` lines in a SUT are derive-invisible"
date: 2026-11-02
category: test-failures
tags: [ci-pr-affected, derive-gap, edge-declaration, ratchet-repair]
---

# Learning

## Problem

The `affected-index-ratchet` flagged a `new-pair`: suite
`scripts/inngest-a5-a6-owner-ask-10136` names `scripts/lib/trusted-verdict.sh`.
The suite's SUT probe *literally* sources the lib — `source
"$libdir/trusted-verdict.sh"` (scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh:177)
— yet no derivation channel produced the edge, so the audit saw only the `$FORCED`
fixture write at the companion `.test.sh:739` and charged a pair.

## Root cause (seat-verified, PR #11919)

The derive's closure BFS walks only edges *newly minted* by a walked file's
extraction. A SUT's edge is **pre-minted by the name-stem convention**
(`x.test.sh → x.sh`), so the SUT itself is never walked and its `source` lines —
literal or computed — mint nothing. The class affects every `x.test.sh ↔ x.sh`
pair, not just this suite; derive-cache records (`.soleur/cache/affected-derive/v1/`)
confirm it corpus-wide (SUT appears in `edge` rows, never `read` rows).

Two independent misses compounded here: (a) the unwalked SUT, and (b) even if
walked, the probe's `source "$(cd … 2>/dev/null && pwd)/trusted-verdict.sh"` form
defeats the extraction regex (redirect between target and `&&`) — the greedy
fallback mints a nonexistent `scripts/followthroughs/trusted-verdict.sh` and drops.

## Rule

A `new-pair` whose suite exercises the file through a **stem-minted SUT** is
always a `declared edge` candidate — the derive structurally cannot reach it.
Do not spend time hunting for a derivation fix per-suite; declare
`AFFECTED_<LABEL>_PATHS` with the real dep set and record *why* the derive
missed in the array comment. The extractor-level fixes (walk stem-minted SUTs,
tolerate `$(cd … 2>/dev/null && pwd)` prefixes or a `$libdir` map) would retire
this declaration class — implemented 2026-11-03 in the feat-one-shot-11775-10865-extractor-batch
PR (BFS frontier seeds stem-minted SUTs; the D1 `$(cd)` arm tolerates redirects
before `&& pwd`).

## Evidence

PR #11919 (declare edge for the last #11897 pair): security-sentinel + architecture
seats reproduced the gap three ways (derive-cache record, extracted-harness replay,
`--print-selection` row). `ratchet exit=0 reason=pass live=1510 baseline=1510`
after the declaration. See also the sibling rule — the SUT-source boundary decides
declare-vs-accept (`2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary.md`).
