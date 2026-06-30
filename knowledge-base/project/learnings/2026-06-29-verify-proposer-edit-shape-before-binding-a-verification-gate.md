---
date: 2026-06-29
category: workflow-patterns
module: plan-design
problem_type: wrong-assumption
severity: medium
symptoms:
  - verification gate wired to a proposer that doesn't edit the thing being measured
  - eval prompt is a hand-copied paraphrase, not a mechanical projection of the source
  - gate passes trivially (candidate == current) having measured nothing
root_cause: assumed a proposer edits classifier rules and that the eval prompt mechanically tracks the source; both were false
tags: [plan-review, verification-gate, eval-harness, compound, heal-skill, fixture-sync]
related:
  - 2026-06-29-verify-post-cutoff-existence-before-asserting-fabrication
---

# Learning: Verify the proposer's actual edit shape before binding a verification gate to it

## Problem

The skill-eval-gate plan (feat-skill-eval-gate, #5702) wired a before/after eval gate into
`compound`'s edit-application step, assuming compound proposes edits to classifier-skill *rules*
(the `/go` routing table, triage rubric). Plan-review (Kieran) showed two false premises: (1)
compound's Step 8 appends **commentary bullets** to the nearest section — it never edits the routing
table rows; and (2) the eval-harness skill-arm prompt is a **hand-distilled 15-line paraphrase** of
the 84-line `commands/go.md`, with no mechanical link. Result: for nearly every real edit, the
candidate prompt would equal the current prompt → the gate passes having measured nothing (a
false-accept), and even when it didn't, the *measured* artifact (paraphrase) ≠ the *shipped* artifact.

## Solution

Re-scoped to **block-keyed, proposer-agnostic**: the classifier rules live in a delimited block
(sentinel markers) in the source that is the single source of truth for BOTH production and the eval
prompt (the prompt becomes a mechanical projection of the block — `extract-block.cjs`). The gate
fires on any edit that changes a gated block, regardless of which skill proposed it; the primary
in-session hook moved to `heal-skill` (the path that actually edits skill rules), with a CI backstop
(#5703) as the proposer-agnostic catch-all.

## Key Insight

Before binding a verification gate to a specific proposer, verify two things by **reading the
proposer and the measurement surface**, not by assuming: (a) does the proposer actually edit the
artifact the gate measures? (b) is the gate's input a *mechanical projection* of what ships, or a
hand-maintained copy that can drift? If either is false, the gate is theater. The robust shape is to
key the gate on the *artifact* (a delimited block that is the SSOT) and let any proposer trigger it,
rather than binding to one proposer's edit path. This is the verification-side twin of
paraphrase-without-verification.

## Session Errors

- **Brainstorm chose "wired into compound" trigger on a false premise about what compound edits** — Recovery: 3-agent plan-review (Kieran P1-3) caught it; operator chose block-keyed proposer-agnostic re-scope. Prevention: at brainstorm/plan time, read the chosen proposer's actual edit step before selecting it as the gate hook (this learning).
- **Plan assumed eval skill-arm prompt tracks the source** — Recovery: Kieran P1-1; mechanical-projection design adopted, killing the fixture-sync caveat. Prevention: when a gate compares "before/after" of a prose artifact, confirm the compared artifact is a projection of what ships, not a snapshot.

## Tags
category: workflow-patterns
module: plan-design
