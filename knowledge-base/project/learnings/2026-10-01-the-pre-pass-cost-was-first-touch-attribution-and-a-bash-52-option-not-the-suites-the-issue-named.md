---
title: The pre-pass cost sat on whichever suite touched a shared file first, and one bash 5.2 option made selection depend on the bash version
date: 2026-10-01
category: workflow-patterns
tags: [affected-gate, bash, performance, profiling, memoisation, selection-identity]
---

# The pre-pass cost sat on whichever suite touched a shared file first

## What happened

The affected pre-pass was reported as about 11 minutes of CPU on every local run, 73% of it in eight named
registrations, diagnosed as comment tokens plus an O(n) edge scan. On a quiet host it was 277 to 427 s of median
CPU (two probes), and a per-registration timer showed why the eight names were wrong: the per-file memo moves a shared
closure's cost onto the first registration that reaches it. 785 files were scanned for 45.5 s of 80 s;
`scripts/orphan-process-reaper` carried 23.8 s because its closure reaches the runner, not because it is expensive.
Bash 5.2's `patsub_replacement` (on by default) made `&` in a variable value resolve differently from bash 3.2, a
correctness difference no single host shows. The change brought the walk to 69 to 98 s with selection identical.

## Prevention

- **Profile before choosing the lever, and attribute cost by cause, not by who paid it.** Count distinct units of work
  (files scanned) and their size, not the callers a memo happened to charge.
- **A selection change is a regression, not an optimisation.** Certify a pre-pass change with `scripts/affected-prepass-bench.sh --base <rev>`, which compares the
  `AFFECTED_SELECTED` rows byte for byte against the base commit and declares what the change adds (a registration adds
  an edge to every suite whose closure reaches the runner); fail on everything else.
- **Re-measure the effect of every revert a review asks for.** A review argued, correctly, that a growth cap in the
  variable resolver is not identity-preserving in general; removing it tripled the walk (90 s to 220-260 s) and was
  caught only by timing the result. The right response was to keep the cap, state its limit where the function is, and
  make the bench its gate.
- **Never edit a script while a long run reads it** (bash reads incrementally); run long measurements from a copy.
- **Quote CPU time and the load average, and measure the status-quo arm on the same host.**
