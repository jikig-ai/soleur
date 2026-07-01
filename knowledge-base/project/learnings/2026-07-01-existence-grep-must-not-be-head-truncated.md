---
date: 2026-07-01
category: best-practices
module: plan
issue: 5754
tags: [premise-validation, grep, named-artifact-verification, plan-review]
---

# Learning: an existence/absence grep whose result bounds a decision MUST NOT be `head`-truncated

## Problem

While planning #5754, I verified a guard symbol with
`git grep -n "resolveCurrentWorkspaceId\|resolveActiveWorkspace" -- '<file>' | head -3`. The three
lines returned all referenced `resolveCurrentWorkspaceId`, so I concluded `resolveActiveWorkspace`
was **absent** and built the plan's canonical acceptance criterion (AC5) on "the register's
`resolveActiveWorkspace` citation is stale — the drift detector must flag it."

The symbol was NOT absent — `export async function resolveActiveWorkspace(` is defined at
`workspace-resolver.ts:398`. The `| head -3` truncated the match list before reaching it. Two
plan-review agents (Kieran, spec-flow-analyzer) independently caught that AC5 rested on a non-fact;
the whole "prove the tool works on the real register" deliverable was unsatisfiable as written.

## Solution

Rewrote AC5: the live `resolveActiveWorkspace` citation became a **negative control** (must NOT be
flagged), with the positive stale case moved to a synthesized fixture. Re-ran the grep without
truncation (`git grep -nE "^\s*export (async )?function resolveActiveWorkspace\b"`) to confirm.

## Key Insight

`head -N` (and `| head`) on a grep is fine when you're *sampling* matches, but it is a latent
false-negative when the grep's PURPOSE is to prove a named artifact is **absent**. A truncated
existence-grep can show early matches (a related symbol, a comment reference) while hiding the
definitive definition line — and "absent" is exactly the claim that then bounds the plan's option
space. For any grep whose result will be asserted as "X does not exist / is stale / is unused,"
either (a) drop the truncation entirely, (b) use an exact-token anchored pattern
(`^\s*export .*function X\b`), or (c) use `grep -c` and reason about the count — never `| head -N`.
This is the truncation-shaped sibling of the plan skill's existing "verify named artifacts against
repo state" sharp edges: the grep was run, but its output was silently cut before the load-bearing line.

## Session Errors

- **Truncated existence-grep propagated a false "symbol absent" premise into a canonical AC** —
  Recovery: plan-review (Kieran P0 + spec-flow P0-3) caught it; AC5 rewritten to a negative-control +
  synthesized-fixture shape. Prevention: this learning; anchored/untruncated greps for absence claims.

## Tags
category: best-practices
module: plan
