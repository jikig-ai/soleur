---
title: "When a plan AC forbids an issue-token literal in the edited file, cite provenance by plan filename — not #N"
date: 2026-06-02
category: workflow-patterns
tags: [acceptance-criteria, provenance, one-shot, grep-gate]
related_prs: [4803]
related_issues: [4798]
---

# AC-forbidden token: cite the plan filename, not the issue number

## Problem

Repairing the stale `conversation-archive-release-slot.integration.test.ts`
suite (#4798), the plan's **AC4** asserted:

> `grep -n "#4798\|independently stale\|does not run in CI" <file>` returns **zero** lines.

The intent of AC4 is "the staleness NOTE is gone." When updating the file's
header docstring to record provenance, I wrote `Schema-alignment repair (#4798,
…)`. The AC4 re-check then returned `1` instead of `0` — my own provenance
citation reintroduced the exact `#4798` literal AC4 forbids.

## Solution

Removed the bare `#4798` token from the header and cited the repair **by plan
filename** instead:

```
 * Schema-alignment repair (drop title + add NOT NULL workspace_id +
 * WORM-bypass teardown):
 * 2026-06-02-fix-repair-stale-conversation-archive-release-slot-integration-suite-plan.md.
```

The plan filename already encodes the issue and the fix, so provenance stays
fully discoverable without the literal `#N` token. AC4 re-check → `0`.

## Key Insight

An AC of the form "grep for `#N` returns zero" treats the bare issue-token as a
**staleness marker**, not a provenance affordance. Provenance belongs in a form
the AC does not forbid — the plan filename (which is date- and issue-named) is
the canonical carrier. Before adding any `#N` citation to a file the plan edits,
re-read the file's own ACs: if an AC greps for that literal, cite the plan
filename instead.

## Prevention

- **Already-enforced** by the work skill's Phase 3 AC re-check: I ran AC4 after
  the edit, it returned `1`, and I corrected before commit. The existing
  per-AC grep verification is the mechanical gate — no new rule needed. The
  lesson is to *expect* this collision when a plan AC forbids the very issue
  token you'd reflexively add as a provenance comment, and reach for the plan
  filename first.

## Session Errors

1. **Added `#4798` to the test header docstring, tripping AC4.** Recovery:
   removed the bare issue token, cited the repair plan by filename. Prevention:
   when a plan AC greps-for-zero on an issue-token literal, cite provenance by
   plan filename only — the AC re-check (work Phase 3) catches the reflex if
   missed.
