---
date: 2026-07-22
category: workflow-patterns
module: competitive-analysis / review-discipline
issue: 6827
pr: 6830
tags: [premise-verification, substantiation, correction-discipline, half-sweep, competitive-intelligence]
---

# Grading a claim's substantiation means reading every cited source — and a correction must not half-sweep

Two learnings from implementing #6827 (correct a stale competitor figure + annotate a positioning
takeaway). Both are the *same defect class the issue exists to fix*, met from the inside.

## 1. "Unsubstantiated" is a claim about sources — check every cited one, not the landing page

The brainstorm/CMO premise was: "Cofounder's pricing, revenue-share, memory, and ownership claims
are NOT stated on cofounder.co." It came from a single **landing-page** WebFetch.

During `/work`, the existing `competitive-intelligence.md` Tier-3 table row already **linked**
`cofounder.co/pricing` and a GIC memory blog post as sources for exactly those claims. Reading
those cited subpages showed:

- Pricing (trial / $20 Pro / $50 Team "coming soon") — stated verbatim on `cofounder.co/pricing`.
- Ownership graduation — stated verbatim there ("graduate at any point and claim ownership …").
- Three-tier memory + sleep-time compute — stated in the cited GIC post.

So nearly every claim graded "unsubstantiated" was in fact substantiated. Asserting "unsubstantiated"
from an incomplete source check is **the 2026-07-20 correction's own defect class, in reverse** — that
correction fired because unverified competitor figures were asserted as *fact*; this nearly asserted
verified claims as *unverified*. Both are "graded a claim without reading its evidence."

**Rule:** before grading a claim VERIFIED / UNSUBSTANTIATED, read every source the artifact already
cites for it. A landing page is one source; the table row's links are the source set. The cheapest
tell that you under-checked: the artifact you are editing cites a URL you did not open.

## 2. A correction/annotation edit can introduce a half-sweep contradiction with its own corpus

The FR7 edit re-graded "no revenue share" as INFERRED and introduced "11 domains" in takeaway #7 —
but four sibling assertions in the same file (`competitive-intelligence.md:21,100,185`) plus
`business-validation.md` still stated "no revenue share" as flat fact and "8 departments" as verified.
**Two review agents (pattern-recognition + code-quality) independently converged** on the
contradiction — orthogonal convergence, so it was real, not a single-agent false positive.

The scope-respecting fix (full positioning-corpus reconciliation was deliberately deferred as NG2):
**confine the edit to the block you authored, make it explicitly authoritative over the un-reconciled
siblings, and flag the rest for the deferred owner** — rather than either (a) leaving your correction
silently contradicting untouched siblings, or (b) rewriting the whole corpus (scope creep into
deferred work). The breadth "11 vs 8" was resolved the same way: don't unilaterally pick a number
that fights the corpus — state both groupings and hand the taxonomy call to the deferred rewrite.

**Rule:** when you correct or re-grade one instance of a claim that recurs across a corpus, either
sweep every instance (if in scope) or make your corrected instance explicitly authoritative and flag
the untouched siblings for the owner. Never ship a correction that silently contradicts its neighbours
— that is the same half-sweep failure as an incomplete write-site sweep
(`hr-write-boundary-sentinel-sweep-all-write-sites`), applied to prose claims.

## Session Errors

1. **FR7 premise was wrong (landing-page-only verification).** Graded pricing/memory/ownership
   "not stated on cofounder.co" from one WebFetch. **Recovery:** read the cited subpages during
   `/work`, corrected takeaway #7 + `decision-challenges.md` to the true split before any of it
   reached the PR body. **Prevention:** learning §1 — read every cited source before grading.
2. **The FR7 edit introduced a half-sweep contradiction.** "no revenue share" graded inferred in the
   new block while stated as fact in four siblings; "11 domains" vs the corpus's "8". **Recovery:**
   two converging review agents caught it; fixed inline by making the block authoritative + flagging
   siblings for the deferred rewrite. **Prevention:** learning §2.
3. **Scratchpad dir auto-cleaned twice mid-session.** `gh … --body-file $SP/x.md` failed "No such
   file or directory". **Recovery:** `mkdir -p $SP` before each write. **Prevention:** one-off
   (session-scratch lifecycle); no rule warranted.
4. **Persisted `cd apps/web-platform` (from a vitest run) drifted a later grep to the wrong root.**
   `ugrep: No such file or directory` for worktree-relative paths. **Recovery:** re-ran with an
   explicit `cd <worktree-root> &&` prefix. **Prevention:** already covered by the existing
   "chain `cd <abs> && <cmd>` in one Bash call" guidance; no new rule.

## Related

- `knowledge-base/project/learnings/2026-07-22-no-consumer-claim-is-a-producer-consumer-contract-mismatch.md`
  — the brainstorm-phase learning for the same issue (queue contract + write-site sweep).
- `hr-write-boundary-sentinel-sweep-all-write-sites` — §2 is the prose-claim analogue.
- Issues: #6827 (tracker), #6850 (pipeline redesign), #6851 (battlecard), #6838 (twin-drift gate).
