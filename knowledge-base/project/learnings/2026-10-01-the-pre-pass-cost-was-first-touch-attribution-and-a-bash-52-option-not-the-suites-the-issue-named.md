---
title: The pre-pass cost sat on whichever suite touched a shared file first, and one bash 5.2 option made selection depend on the bash version
date: 2026-10-01
category: workflow-patterns
tags: [affected-gate, bash, performance, profiling, memoisation, selection-identity]
---

# The pre-pass cost sat on whichever suite touched a shared file first

## What happened

The affected pre-pass was reported as about 11 minutes of CPU on every local run, 73% of it in eight named registrations,
and the diagnosis was "comment tokens pull `test-all.sh` into the closure" plus an O(n) edge scan. Measuring on a quiet host
gave 222 to 310 s of median CPU (two probes), not 660, and a per-registration timer showed why the eight names were wrong: `_affected_file_edges`
memoises per file, so the cost of scanning a file lands on the FIRST registration whose closure reaches it. 785 distinct
files were scanned for 45.5 s of 80 s; `scripts/orphan-process-reaper` (registration 74) carried 23.8 s because its closure
reaches the runner and about 465 files, not because it is expensive.

## The bash 5.2 trap

Bash 5.2 added `patsub_replacement`, on by default: an unescaped `&` in the replacement of `${v//pat/repl}` expands to the
matched text. The derive substitutes captured variable values into tokens, so a value containing `&` resolved to something
different on 5.2 and later than on 3.2. That is a correctness difference (selection depended on the bash version), not only
a cost one, and it is invisible on any single host. `shopt -u patsub_replacement` is the only switch; `BASH_COMPAT` does
not turn it off.

## Prevention

- **Profile before choosing the lever, and attribute cost by cause, not by who paid it.** A memo moves cost to the first
  caller; a per-caller table then names the callers that happened to run first. Count distinct units of work (files
  scanned) and their size, not the callers.
- **A selection change is a regression, not an optimisation.** Certify a pre-pass change with a bench that compares the
  `AFFECTED_SELECTED` rows byte for byte against the base commit; it found that adding one suite adds an edge to every
  suite whose closure reaches the runner, which a naive "identical" check would have reported as 18 regressions. Declare
  what the change adds (`--added`, `--added-edges`), and fail on everything else.
- **Never edit a script while a long run reads it.** The first bench run died with a syntax error at a line number far
  from my edit because bash reads a script incrementally; run long measurements from a copy.
- **Quote CPU time and the load average, and measure the status-quo arm on the same host.** The 11-minute figure was taken
  at load 30 to 64; the same walk on a quiet host was 222 to 310 s, and the change brought it to 92 to 109 s (2.4x to 2.8x) with selection identical.
