---
title: "Soak-suite cost bound: the plan's fixture figure was arithmetically impossible, and oracle-skipped CI legs leave re-prices on local measurements"
date: 2026-11-10
category: workflow-issues
tags: [ci, soak, followthrough, suite-pricing, mutation-battery]
issue: 12017
pr: 12622
---

# Soak-suite cost bound — two session learnings

## 1. A plan's numeric cut must be re-derived, not copied

`r_max_cap`'s planned cut (60→40 full runs at 2000s) was arithmetically impossible:
at 50 sampled runs it produces a mean of 28.37 min — UNDER the 29.08 limit, so the
row that exists to assert an over-limit verdict would have gone red by construction.
The implementer caught it only because the row's expected verdict was recomputed
against MEAN_LIMIT, not against the plan's prose. Fix: 2200s full runs (mean 31.03
over; the m-max-cap mutant's newest-30 mean 27.28 stays under — both arms still kill).

**Prevention:** any planned fixture constant that feeds a verdict threshold needs the
verdict arithmetic recomputed at implementation time — plan figures are proposals,
not proofs.

## 2. Oracle-skipped CI legs mean the re-price is a local measurement

`test-scripts` legs are oracle-selection-skipped on a followthrough-only diff, so no
`suite-timings-scripts-*` artifact ever measures the new code on CI. The committed
price (185400ms) came from local runs, conservative-direction, with the merge_group
CI runs named in the commit (42891735582/42887535182/42864026488 as scale evidence).
The next `--runs` regen reprices from real CI medians — a stale local-derived price
is expected drift, not a bug.

## 3. Verbatim-subexpression jq merging preserves every mutant anchor

Merging four per-run `jq` calls into `[(P1),(P2),(P3),(P4)] | @tsv` with each program
copied VERBATIM inside parens kept every jq-subexpression mutant anchor byte-identical;
only the two mutants anchored on call-site shape (m-no-voucher, m-unmatched-ok) needed
re-anchoring. Cheapest possible restructure for a mutation-pinned loop.
