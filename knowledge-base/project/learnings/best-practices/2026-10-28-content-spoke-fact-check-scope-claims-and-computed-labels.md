---
title: "A content spoke's 'every' claims are its first fact-check failures — and char-count labels must be computed, not estimated"
date: 2026-10-28
category: best-practices
module: knowledge-base/marketing
issue: 11364
tags: [content, blog, fact-checker, distribution, census-lint, review]
---

# Learning: the census spoke fact-check — scope claims and derived labels

## Problem

The #11364 spoke post (census lint retro-brief) shipped through an independent
`soleur:marketing:fact-checker` pass and three of its claims failed — all the
same class: a noun whose *scope* the draft had quietly widened.

1. "a full count of every place in the code that catches an error" — the lint
   only classifies catches whose `try` contains `step.run(` or that sit inside
   a step callback. A third bucket (unrelated catches) is silently ignored, so
   "every place" overreached. Fix: "every place … where a hand-off is involved."
2. "flags it, every time, with no exceptions" — bare `instanceof Error` is an
   exempt precision anchor in both shapes. Fix: name the one pass it gives.
3. "In some [other tools], the label is dropped" — the sourced generalization
   (Temporal) supports only the *wrapper* form. The dropped-label form is
   verified for our own tool only. Fix: "in our tool the label is dropped; in
   others the original arrives intact but wrapped" — still no vendor named.

## Solution / Rule

**Scope-claim check for content PRs:** when a draft says "every X" about a
linter, census or guard, the falsifier is the tool's *negative* arm — its
self-test row or code path for the input it ignores. Ask "what does it NOT
classify?" before "what does it flag?". The fact-checker found all three by
reading `lint-inngest-step-boundary.py`'s self-test and
`IDENT_INSTANCEOF_RE`, not by reading the prose.

**Char-count labels are derived, never estimated.** I wrote `(232/214/243…)`
tweet labels by estimate, then recomputed with the test's own t.co method
(`tweetLen` in `distribution-content-format.test.ts`: strip URLs, +23 each)
and every label moved. Compute the number with the same formula the gate
uses; write it after the text is final, and recompute after any edit (tweet 3
moved again after the fact-check remediation).

## Session Errors

1. **Estimated `-- NNN chars` labels instead of computing them.** — Recovery:
   recomputed per tweet with the gate's own t.co formula; one label (tweet 3)
   moved again after the fact-check edit and was re-derived. — Prevention:
   derive counts from the as-written file at write time (work SKILL rule:
   counts in artifacts are derived, not plan-prose estimates).
2. **`git mv` restore ran from the wrong cwd** (inside `plugins/soleur`, the
   relative restore path didn't exist) — Recovery: re-ran the move from the
   worktree root and verified with `git status`. — Prevention: absolute paths
   for every mutation that can run from a drifting cwd.
3. **Vacuity check's `sed` silently no-matched** (`Arrive rewritten` ≠ `arrives
   rewritten`) and the probe passed on an unmutated file — Recovery: appended
   a guaranteed backtick line instead; rc flipped to 1 as required. —
   Prevention: assert the mutation landed (`grep` the fixture for the injected
   token) before reading the guard's verdict — an unmutated fixture greens
   vacuously (constitution: batch edits must assert the needle matched).

## Verified outcomes

- Post: 1,992 body words (1,500–2,000 band), jargon scan rc 0, docs build
  clean, 4 content suites 192/192 green, `validate-blog-links.sh` green,
  `validate-tweet-draft.sh` rc 0 at `status: draft` then flipped to scheduled
  (publisher `content-publisher.sh:884-896` parse-equivalence confirmed).
- Mutations proven: PNG delete reddens AC5 while `seo-aeo-drift-guard` stays
  green (documented blind spot); redirect drop reddens `validate-blog-links`.
- Review: 4-seat non-code panel (git-history-analyzer,
  pattern-recognition-specialist, security-sentinel, code-quality-analyst) —
  0×P1, 0×P2, ~12 P3s; actionable ones fixed inline, decision-shaped ones
  (`type: pillar` majority convention, tag set matching the hub, two-part
  CTA question per plan, calendar rollover rows, char labels) disclosed.
- Fix-round: consolidated verification over `ca75a65fa0..HEAD` — clean.
