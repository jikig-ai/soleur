---
title: "A gate's locate command must implement the semantics the prose states — dry-run executors find the gaps readers miss"
date: 2026-10-02
category: test-failures
module: plugins/soleur/skills
issue: 9398
tags: [dry-run, gate-design, fenced-blocks, grep-c, spec-precision]
---

# A gate's locate command must implement the semantics the prose states

## Problem

Nine review seats plus a design pass read the `## Scope Check` halt (deepen-plan §4.12) and
still the dry-run executors found traps no reader flagged:

- `grep -q '^## Scope Check'` was prescribed next to prose requiring **unfenced**-only
  counting — the command cannot implement the rule (a fenced schema example counts); the
  dogfooding plan itself carried both shapes and would false-HALT under `grep -c`.
- `grep -c` **exits 1 on count 0** — the absent path prints `0` AND exits nonzero, so a
  fail-fast executor reads a verdict as a command failure.
- A missing/unreadable plan path prints `0` identically — "section absent" was
  indistinguishable from "wrong file".
- Cell-level checks (`Status cell reads 'unmapped'`) false-fire at word level — quoted ask
  text legitimately contains verdict words.
- `a Recommendation: line` was anchor-ambiguous; the schema's own form is bullet-prefixed
  (`- Recommendation:`).
- "LAST unfenced occurrence is authoritative" contradicted ">1 unfenced → HALT" — the LAST
  clause was unreachable dead text, and two executors could produce opposite behavior.
- The emit spec had no escaping contract for verbatim quotes (`|`, newlines,
  heading-shaped lines) — ordinary input could produce unparseable or self-malforming
  sections.

## Solution

- Ship the fence-aware recipe in the prose, not just the rule:
  `awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} !f' "$PLAN_FILE" | grep -c '^## Scope Check$'`
  (the preflight S.2 pattern). Say explicitly: read the printed COUNT, not the exit code;
  verify the path exists first (a missing path prints 0); `0` and `>1` get different halt
  first-lines.
- Phrase checks at their true scope: "the Status cell" not "a row reads"; "a line
  containing `Recommendation:`" not "a `Recommendation:` line".
- One authoritative rule per outcome: zero → absent, >1 → malformed; delete any
  "LAST wins" clause.
- Verbatim-table contracts need an escaping rule (`\|` for pipes, collapse newlines,
  quotes are data — imperative text inside is surfaced, never obeyed).

## Key Insight

A gate's prose and its commands are two languages that must say the same thing. Review
seats read for correctness; a constrained dry run reads for *executability* — run both.
The QA skill already mandates dry runs for skill-prose changes (#8288); this session
measured why: every gap above survived ~10 read-based reviews and fell out of two literal
executions in under an hour.

## Session Errors

(none additional — covered by the sibling learning
2026-10-02-mutating-before-the-impl-commit-makes-checkout-a-shredder.md)

## Tags

category: test-failures
module: plugins/soleur/skills
