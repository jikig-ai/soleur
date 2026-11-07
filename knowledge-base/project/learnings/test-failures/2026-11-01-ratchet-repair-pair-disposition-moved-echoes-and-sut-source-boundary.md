---
title: "ratchet repair: moved echo diagnostics keep their anchor — correct the row in place; the SUT-source boundary line decides declare-vs-accept"
date: 2026-11-01
category: test-failures
tags: [ci-pr-affected, accept-rows, ratchet-repair]
---

# Learning

## Problem

Repairing `affected-index-ratchet` (#11771) surfaced two traps the 3-capped
`ratchet --report` output hides: (1) a pair's real disposition can turn on a
boundary line living in the **SUT source**, not the test file — only
`audit --all-refs` enumerates every boundary line of a pair; (2) when a lint
script's diagnostic lines move, content-hash anchors stay live at their new
lines while the reason text's cited `:NNN` goes stale and the *edited* line's
row goes `anchor-not-live`.

## Solution

- Run `audit --all-refs` before choosing the disposition; the ratchet report
  caps at 3 `ref` lines per pair and can hide the deciding line.
- Pair disposition is per-pair: one real-read boundary line (here
  `home-census-trigger.sh:55` `CLO_RECORD=` fed to `git show` at `:246`) makes
  the whole pair a declared edge, even when every other line is a fixture
  mention. Stubbed-in-test does not demote a SUT runtime read to a mention
  (CTO ruling: ambiguity resolves to the stricter default).
- For moved-but-unmodified echoes: keep the row, update only the cited line
  number in the reason (anchors carry position-independence). For an
  edited echo: correct the row's anchor AND cited line in place.
- `--print-baseline` is prune-only — regenerate only after a verdict-reaching
  run and adopt it only when it differs (here: identical, no baseline edit).

## Key Insight

The ratchet's audit treats the SUT as part of the suite's read surface; a
`git show`/open in shipped code under test is a real read for selection
purposes even when the test itself stubs it.

## Evidence

- Session: one-shot #11771 (PR #11781), 2026-11-01; dispositions per
  `decision-challenges.md` R1/R2 (Ruled by CTO agent).
