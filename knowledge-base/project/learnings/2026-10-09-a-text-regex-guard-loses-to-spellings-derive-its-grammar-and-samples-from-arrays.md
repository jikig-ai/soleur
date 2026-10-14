---
title: A text-regex guard loses to spellings; derive its grammar and its samples from the same arrays
date: 2026-10-09
category: test-failures
tags: [ci, apt, assembly-guard, census, mutation-battery, review, contended-box, git-data]
issue: 9395
---

# Learning: a text-regex guard loses to spellings; derive its grammar and its samples from the same arrays

## Problem

#9395 moved two in-container apt cycles onto the shared bounded-apt helper and extended the derived
assembly row (A10) of `apt-bounded.test.sh`. The conversion was small and was proven against real docker
(forced decline local/CI, mount deleted, image rebuilt). The guard was the expensive part: a first version
matched `docker run` and raw apt in command position, plus a census over top-level `*.test.sh`. A ten-seat
review panel found no P1 but about twenty evasions of that grammar, a second round found more, and a
verification pass a few cheap P3s. Every round was a new spelling of the same gap (`sudo`, `timeout "$T"`,
column-0 `if`, `docker exec ... apt-get`, `apt-get -o K=V install`, subdirectory suites, `docker build` with a
`RUN` line, `$DOCKER run`). Patching the regex per spelling is the loop the repo's own review notes say to
stop after two consecutive rounds.

## Solution

- Put every grammar arm in an ARRAY (separators, keywords, wrapper words, apt binaries and verbs, docker
  verbs). Build the regexes from the arrays and GENERATE the positive samples from the same arrays, so no arm
  can exist unsampled. Pin the number of sample calls and fail on a list shorter than three, so an emptied
  list is a finding rather than a quiet green.
- Make the census LOOSE (any docker verb plus any apt text, recursive over every `*.test.sh`) and resolve
  its false positives with an explicit `EXEMPT` list with a reason per file, plus a stale-exemption check and
  a check that an exempt file stays free of a real command-position docker run or raw apt. A false candidate
  costs one line; a miss is silent. Measured on the real tree: exactly the four declared consumers plus two
  suites that only quote command text as data.
- Count SITES, not lines; require the first statement after an arm to be a docker run that carries the
  mount; read SPECS fields as decimal (`10#`); pin the classification call site so a flipped or constant
  condition is a finding.
- Make the failure text sufficient for an agent to resolve a new suite: it names the recipe, the SPECS
  format, the EXEMPT alternative and prints the matched site lines instead of bare counts.

## Key Insight

A guard built from a command-position text grammar is a bet that you have enumerated the spellings. Do not
win it by enumerating harder. Derive the grammar and its samples from one source so coverage is by
construction, and bias the population census toward over-matching with an explicit, self-checking exemption
list. The same panel also showed that the author's own mutation battery measured only the mutations the
author imagined: 64 rows were green while the panel's escape corpora were not, so feed the pristine guard
corpora it should refuse, not only mutants of itself.

## Session Errors

1. **Grammar chased spellings across three rounds** — Recovery: arrays, generated samples, loose census with
   EXEMPT. Prevention: for a guard whose job is "no member escapes", start from the loose population plus an
   exemption list, never from a precise matcher.
2. **Heavy local verification on a contended box (load 55-80)** — operator interrupted twice to ask for CI.
   Recovery: pushed and read CI with a monitor. Prevention: check capacity (`scripts/test-all.sh --capacity`)
   before a multi-minute battery or real-docker chain; run locally only what is cheap and decisive and let CI
   run the rest (routed into the work skill's pitfalls).
3. **Asserted web-2 had not received the resolver fix after grepping one of two delivery resources** (wrong;
   retracted on #9393). Recovery: the other session's evidence, verified against `server.tf` and the apply
   log. Prevention: grep the claim's SUBJECT across every resource and workflow that can deliver it before
   asserting an absence.
4. **`lockfile-sync` failed on a BEHIND PR with "no sdk-bump-verified acknowledgement"** though the PR touched no
   package file: main had bumped the SDK after the merge ref was built, so the PR looked like a downgrade.
   Recovery: merge current main. Prevention: on a lockfile or SDK-bump gate failure, read `mergeStateStatus`
   and the detected `A -> B` versions first; BEHIND plus a "downgrade" means sync, not an acknowledgement.
5. **Two unrelated CI flakes** (provider download HTTP 500; a finalizer row on the cutover suite) plus the
   pre-existing whole-second A12 flake. Recovery: re-ran the failed jobs; widened A12's budget. Prevention:
   read the failing step via the jobs API before any log grep, and confirm the same step is green on main.
6. **A draft commit message cited the wrong issue number** — caught before committing. Prevention: write
   issue numbers into commit messages only after `gh issue view` confirms them.
7. **Hook denials and tool friction** (`pgrep -f`, `git stash list`, `gh` from a non-repo cwd, `gh api
   .../logs` needing `--allow-escape-sequences`). One-off; no change.

## Tags

category: test-failures
module: apps/web-platform/infra
