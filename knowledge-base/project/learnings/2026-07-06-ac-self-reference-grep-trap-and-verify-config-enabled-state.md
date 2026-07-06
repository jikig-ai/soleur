# Learning: AC self-reference grep trap + verify a cited config's enabled state (not just existence)

## Problem

Two distinct plan-authoring defects surfaced while planning #6039 (add a
"got smarter" section to operator-digest + enable the compound-promote loop):

1. **AC self-reference grep trap.** Three of my acceptance criteria grepped for
   the *absence* of a forbidden token — `grep -c -- '--search'` returns 0,
   `grep -ci 'your workspace'` returns 0 — but the section being verified
   **legitimately contains those exact tokens as its own prohibition/comment**
   ("NOT `--search`: the Search API is empty…", `**Never write "your workspace
   got smarter"**`). The AC false-fails a correct file. Kieran plan-review
   flagged all three as P0.

2. **Verified existence, not enabled-state.** The whole feature premise ("0
   promotions to surface") was investigated as "the loop is quiet." It was
   actually **switched off**: `promotion-config.yml` had `enabled: false`. An
   existence/row-count check would never reveal this; only reading the flag's
   *value* did — and it changed the plan (the operator bundled "enable the loop"
   into scope).

## Solution

1. When an AC must verify that a forbidden pattern is not *used*, assert the
   **positive guardrail's presence** (`grep -c 'Never write "your workspace"'`
   ≥ 1) or scope the grep to a **command line / render example**
   (`awk '<section>' | grep -E '^\s*gh ' | grep -c -- '--search'`), never bare
   token absence over a file that documents the token.
2. When a plan premise turns on whether a capability is *active*, read the
   config flag's **value** (`grep -c '^enabled: true'`), not just that the
   config/table/row exists.

## Key Insight

A negative-absence grep is only valid when the forbidden token has **no
legitimate occurrence** in the searched scope. Prohibitions, comments, and
guardrail lines are legitimate occurrences — so "assert the forbidden thing is
absent" flips to "assert the guardrail that forbids it is present." Generalizes
the existing awk-self-match / paren-spanning AC Sharp Edges to the
*documents-its-own-prohibition* case. And "verify existence" ≠ "verify enabled":
a default-OFF opt-in reads as present-but-inert.

## Tags
category: best-practices
module: plan
related: 2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface.md
issue: "#6039"
