---
title: "one-shot collision gate false-positives on a cited-predecessor MERGED PR"
date: 2026-06-15
category: workflow-patterns
tags: [one-shot, collision-gate, soleur-go, follow-up-issues, gh-pr-list]
issue: 5356
---

# Learning: one-shot Step 0a.5 collision probe fires on a cited-predecessor MERGED PR

## Problem

`/soleur:go #5356` → `/soleur:one-shot #5356`. #5356 is an OPEN `deferred-scope-out`
issue explicitly authored as a **follow-up** to merged PR #5350 ("Follow-up to
#5275 (PR #5350)"). The one-shot Step 0a.5 collision gate ran its
merged-linked-PR probe:

```
gh pr list --search "linked:issue #5356" --state all --json number,title,state
→  #5350 [MERGED]: feat(session-resume): ... (#5275)
```

and classified #5350 as the "high-signal collision" (an implementation that
already landed under the open issue), triggering the **abort-by-default**
AskUserQuestion. But #5350 did **not** implement #5356 — it implemented #5275
(the legacy path). GitHub returned it because #5356's body *cites* #5350, and
`linked:issue` matches body cross-references, not just the closing PR.

## Root cause

The Step 0a.5 merged-PR probe assumes any MERGED PR returned by
`linked:issue #N` is "the work already landed." That holds for the squash-merge
rename case the gate was built for (#4232/#4508), but **not** for a follow-up
issue that names its predecessor PR in prose. `linked:issue` is a body-text
cross-reference match: a "Follow-up to #M" / "Ref #M" / "supersedes #M" line is
enough to surface #M as MERGED under the OPEN issue, even though #M closed a
*different* issue.

This is the linked-PR-probe analogue of the already-documented closed-issue
citation trap ([[2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs]]):
both stem from `#N` / `linked:issue` matching CITATIONS indistinguishably from
WORK-TARGETS.

## Solution

The gate is correctly **abort-by-default**, so the false-positive is a one-question
pause, not a wrong abort. Disposition: read the surfaced PR's title + the issue
body; if the MERGED PR closed a DIFFERENT issue (here #5350 → #5275) and the
open issue is framed as a follow-up ("Follow-up to", "not fixed in #M",
"scoped out as ... in #M"), answer **continue (genuinely new scope)** and
proceed. Confirmed here: #5356 built the cc-soleur-go disconnect terminal #5350
explicitly scoped out.

## Key Insight

A MERGED PR returned by `gh pr list --search "linked:issue #N"` is a
"work-already-landed" signal ONLY if that PR's `closesIssues` includes #N — NOT
if #N merely cites it. Before trusting the merged-linked-PR collision, check
whether the surfaced PR closed a *different* issue and whether the open issue's
body frames itself as a follow-up. The cheap discriminator:
`gh pr view <surfaced-PR> --json closingIssuesReferences` — if #N is absent, the
link is a citation, continue.

## Prevention

Routed to definition: one-line note added to one-shot Step 0a.5's merged-linked-PR
disposition so the next operator distinguishes a cited-predecessor from a real
collision without re-deriving it.

## Tags
category: workflow-patterns
module: one-shot
