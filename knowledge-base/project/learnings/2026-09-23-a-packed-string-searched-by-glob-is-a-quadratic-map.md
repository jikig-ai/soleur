---
title: "A packed string searched by glob is a quadratic map, and three live-corpus guards had contracts only CI could show me"
date: 2026-09-23
category: test-failures
tags: [bash, performance, ci-paths, mutation-testing, guard-contracts, shard-assignment]
issue: 8006
pr: 8612
related:
  - knowledge-base/project/learnings/2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md
---

# A packed string searched by glob is a quadratic map, and three live-corpus guards had contracts only CI could show me

## Problem

`feat-ci-duration-aware-shards` (PR #8612) committed a `label→leg` manifest to make CI shard
assignment duration-aware. The first implementation stored the 482-row table as a packed
pseudo-map — `"|label=leg|label=leg|…"` — and looked labels up with a `case` glob. Every
verdict passed locally, every row of the mutation battery was written, and the design was
correct. The mechanism was also unusable: one `--enumerate` burned 6+ CPU-minutes, and the
battery's control invocation failed on a box that was merely contended.

Two smaller bugs shipped in the same window: `10#_shard_mn` (the `10#` prefix applies to the
expanded literal, not a bare variable — a syntax error under `set -e` that silently took the
wrong branch), and the bash-3.2 `"${arr[@]}"`-on-empty-array `set -u` landmine in the
duplicate check.

## Solution

Parallel indexed arrays (`_shard_m_labels[]` / `_shard_m_legs[]`) with a literal `==` linear
scan: the same 482×482 lookup workload ran in ~1.4s, enumerate in ~6s. All iteration
index-based (`for (( i = 0; i < ${#arr[@]}; i++ ))`), never `"${arr[@]}"`. The earlier
off-by-one in the generator's sticky-LPT (1-based manifest leg used as a 0-based Python
index) was caught the same way the packed map should have been — by a fixpoint test that
re-ran the mechanism on its own output.

## Key Insight

Two generalizable lessons:

1. **A "map" built from a delimited string and searched by glob is a quadratic map.** Glob
   `*` backtracks over every delimiter per lookup; over a registration stream it is cubic.
   bash 3.2 has no `declare -A` — the portable associative structure is parallel indexed
   arrays plus literal `==`, not `case`/`##` glob surgery. Benchmark the lookup before
   shipping, not the parse.
2. **Live-corpus guards carry construction contracts that local runs may never exercise.**
   `guard-vacuity-floor`, `lint-shell-capture-exit-live`, and `fixture-relative-assert`
   each red-lit a *new* suite for a contract violation (mutant-builder assignment adjacency,
   `grep|head` inside `$(…)`, baseline ledger membership) that nothing flagged until CI.
   When adding a suite to a corpus a guard scans, run that guard locally against the new
   file before pushing — the corpus grew, and the floor is derived from it.

## Tags
category: test-failures
module: ci/test-all-sharding
