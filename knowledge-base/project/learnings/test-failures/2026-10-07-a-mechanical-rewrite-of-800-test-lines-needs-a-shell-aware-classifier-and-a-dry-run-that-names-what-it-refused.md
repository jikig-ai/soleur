---
title: "A mechanical rewrite of 800 test lines needs a shell-aware classifier — about one in five hits is data or an executed string, and a regex tokenizer misreads the rest"
date: 2026-10-07
category: test-failures
module: scripts/grep-q-drain-codemod.py + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Code versus data before a transform

## Problem

Wave B of the `grep -q` sweep rewrites `<producer> | grep -q P` to `<producer> | grep -c >/dev/null P` across 804
test-harness lines. The rewrite is one letter plus one redirect, so a reviewer can prove each converted line is
faithful. What no diff reader can prove is that the line SHOULD have been converted: a hook-input fixture
(`run_case 'T1' 'while ps | grep -q zz; do :; done' deny`), a source-text pin of a carrier that still has the shape, and a
deliberate SIGPIPE demonstration all match the sweep's pattern and all stop meaning what they mean once converted.
Measured on `origin/main` `411f034290` (command: the codemod's dry run, `python3 scripts/grep-q-drain-codemod.py apply`):
of S1's 107 in-scope lines, 98 are plain code, 5 are quoted hook inputs, 3 are `-m` (output-bearing, still an early
exit) and 1 is a demo.

## What the first classifier got wrong (all caught by reading the dry run's queue, not by a test)

- **A prefix probe is the wrong instrument for "where did the tokenizer lose balance".** Re-tokenizing growing prefixes
  of `devin-matcher-parity.test.sh` reported "unbalanced" at the first line inside any multi-line command, which is
  every prefix that ends mid-pipeline. The useful signal is the stack at EOF with each frame's opener position
  (`('dq', 378) ('param', 378) ('paren', 378)`), which named line 378 in one step.
- **`${rule#Bash(}` is a pattern, not a subshell.** Inside a `${...}` the `(` must not open a frame, or the closing `}`
  never pops and the rest of the file reads as quoted. Five hits in one file went to the queue as `unsure` until the
  parameter frame stopped counting parentheses.
- **A tail scan for a stdout redirect has to use the same code/quote map.** The first version searched the text after the
  match for `>` and refused two lines whose `>` sat inside the single-quoted pattern (`'soleur:__probe__->nonexistent_phase'`,
  a tagger-line pattern ending in `github\.com>`). The dry run showed them as `X:stdout-redirected`; reading the lines showed they
  were not redirects. Only a code-context `>` that is not `2>`..`9>` counts, and it must stop at the end of the command.
- **The demonstration-suspect rule is over-inclusive on purpose.** Files whose text names sigpipe, EPIPE, false-FAIL or
  broken pipe are never auto-applied. In S1 that routed 7 hits in 5 files to a human; reading them showed four files only
  mention the word in a comment, so they were applied with an explicit `--reviewed-suspect PATH` and the fifth
  (`iac-plan-write-guard.test.sh`, T6) got the `# sigpipe-demo: intentional` marker instead. The earlier partial pair run
  had shown the rule's value: two suites (`iac-plan-write-guard` T6, `scan-workflow-mutation` D1a/D2) failed after a blind
  conversion because the converted line was the thing the row demonstrates.

## What works

- Take the population from the guard itself (its `SWEEP_*` strings, its pathspec, its comment and marker filters) so the tool
  and the guard cannot disagree about what a site is. The dry run's `POPULATION: 827 lines` equals the guard's own
  `DEFERRED:` sum (804 test-shaped + 23 production).
- Print what was refused with a reason (`QUEUE path:line:tier:reason`). The queue is the first thing a reviewer reads; it is
  what caught every misclassification above.
- Refuse on unsure: an unbalanced tokenizer distrusts the whole file, not the line.

## Prevention

When a rewrite tool has to decide "code or data", its dry run must list every refusal with its reason, and the first pass
over a real population must be read line by line before `--write`. A green suite after a blind conversion is not evidence for
data lines.
