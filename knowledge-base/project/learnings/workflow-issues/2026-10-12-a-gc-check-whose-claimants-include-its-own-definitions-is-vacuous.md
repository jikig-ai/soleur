---
title: "A garbage-collection check whose claimant set includes its own definition files is vacuous — and a hand-rolled comment stripper reintroduced a twice-fixed defect"
date: 2026-10-12
category: workflow-issues
module: apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts + test/helpers/strip-comments.ts
issues: [9994, 8603]
---

# Two small false-negative traps in census-style guards

## Problem 1 — self-claiming garbage collection

A sentinel test asserting "every `SYNTHETIC_PREFIXES` entry is claimed by a suite file" joined the
comment-stripped contents of **every** `.ts` under `test/` — which necessarily includes the helper
that defines the prefixes and the unit test that repeats them. The check could never go RED: a
deleted suite's prefix would stay "claimed" by its own declaration forever, while the test's name
claimed the opposite guarantee. Four independent review seats caught it. The fix is boring and
mechanical: **exclude the definition files from the claimant set** (and for the `tenant-isolation-`
prefix, also beware substring self-claims like the path `tenant-isolation-teardown`).

General shape: any "X must be used somewhere" assertion whose "somewhere" corpus includes the file
that defines X is vacuous by construction. The claimant corpus must be **exclusion-listed**, or the
claim must require a non-definition site.

## Problem 2 — the regex stripper, again

The same sentinel briefly grew an inline `stripComments` built from
`/\/\*[\s\S]*?\*\//g` + per-line `//` truncation — the exact defect `test/helpers/strip-comments.ts`
(the TS-parser token walk) was created to eliminate, twice (learning 2026-06-12, then #8603). A
`/*` inside a `//` comment or a string opens a phantom block that swallows real code to the next
`*/`; a `//` inside a string truncates a line mid-call. Both are **carrier-hiding** directions —
the worst kind for a guard whose job is noticing hidden call sites. Every source-walk guard under
`test/` uses the shared parser helper so they all read the same comment-free text; new guards should
inherit it, not re-derive it.
