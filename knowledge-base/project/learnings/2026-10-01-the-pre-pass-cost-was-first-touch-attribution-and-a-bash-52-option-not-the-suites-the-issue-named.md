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

## Session Errors

1. **Edited the bench script while its first run was reading it** — the run died with a syntax error at a line far from the edit and its numbers were void. Recovery: re-ran from a copy. **Prevention:** run any long measurement from a copy of the script (`work/SKILL.md` already says never edit under a running suite); this session ran every later bench that way.
2. **Removed the growth cap on a review finding without re-measuring its cost** — README-probe CPU went from ~90 s to 220-260 s. Recovery: an A/B of the two commits found it; the cap was restored in bytes with its limit stated. **Prevention:** re-time the walk after every revert a review asks for (a revert that is right for identity can be wrong for cost).
3. **Read a diff cut to 300 characters as "18 rows lose ~450 edges"** and bisected the levers for ~30 minutes before printing the full row (the only difference was one added-file edge). **Prevention:** print the full differing set (`set difference`), never a truncated row, before bisecting.
4. **A splice script cut from a function's start to a later anchor and deleted the compare-only rows and a helper in between.** Recovery: restored the segment from `git show`. **Prevention:** after any scripted multi-region edit, run the suite and diff the row count, not just syntax.
5. **The ADR draft claimed "no remaining lever clears the 10% gate"** without measuring the memo index; a review seat prototyped one. **Prevention:** a claim of absence in prose gets the command that would falsify it (`work/SKILL.md` already says so).
6. **The generated, gitignored `knowledge-base/INDEX.md` makes `test-affected-kb-consumers` report extra violations locally that CI never sees.** **Prevention:** run that ratchet with the file moved aside when it reports `knowledge-base/INDEX.md` rows.
7. **Time wrapper used a binary that does not exist** (`/usr/bin/time`), so an A/B printed empty timings; and a `rm -rf` of a scratch dir was refused by the protected-path hook. One-offs; use the shell `time` builtin and `mkdir -p` a fresh directory.
