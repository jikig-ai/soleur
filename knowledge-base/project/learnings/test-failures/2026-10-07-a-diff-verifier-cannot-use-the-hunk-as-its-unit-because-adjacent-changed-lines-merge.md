---
title: "A diff verifier cannot use the hunk as its unit — adjacent changed lines merge into one hunk, so a hand edit hides its converted neighbours"
date: 2026-10-07
category: test-failures
module: scripts/grep-q-drain-codemod.py (verify)
issues: [9217]
---

# `git diff -U0` hunks are not edit boundaries

## Problem

`verify` has to prove that every changed line of a slice is either the mechanical transform of its base line or a listed
hand edit. The first design exempted a HUNK whose removed range equalled a listed range. That is not exact: with `-U0`, git
merges adjacent changed lines into one hunk, so a hand edit on line 1 of a six-line run of converted lines produces one hunk
`-1,6` and an entry for it either exempts all six (hiding five unchecked lines) or does not match at all. The selftest fixture
(a hand edit next to converted neighbours) hit it on the first run.

## What works

- Judge equal-count hunks line by line (`removed[i]` against `added[i]`): a transform of the base line is verified, anything
  else must fall inside a listed range.
- A listed range must cover ONLY hand-edited lines. An entry that covers a plain transform (an over-wide entry) is a finding
  (`hand-edit entry covers a line that is a plain transform`), and an entry no changed line falls in is stale. This replaces the
  hunk-equality rule that cannot be satisfied exactly.
- A hunk that changes the line count cannot be paired, so it must be listed with EXACTLY its removed range (`a-b`, or `a+` for a
  pure insertion), and the entry is marked used by that hunk.
- Restrict the verifier to files the guard's own pathspec sweeps (`git ls-files -- <pathspec>`), or the guard file, the tool and
  docs in the same diff are reported as unexplained.

## Prevention

A verifier that pairs removed and added lines owns the pairing; do not delegate it to the diff's hunking. State the verifier's
unit (line, not hunk) in its contract, and give it RED fixtures for the two boundary cases: a hand edit beside converted lines
(must pass when listed exactly) and an entry wider than the edit (must fail).
