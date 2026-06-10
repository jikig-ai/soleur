# Learning: A plan revision that adds a mechanism must be re-checked against every existing AC — and a reviewer re-validation pass catches it cheaply

## Problem

Folding spec-flow-analyzer's v1 finding P3.13 ("disclosure log line can drift from pins") into plan v2 introduced a `TIER_PINS` map as the anti-drift mechanism — without noticing that the existing AC2 grep (`model: '(sonnet|haiku)'` counting inline literals) and the new map were mutually exclusive: call sites referencing the map make AC2 count 0; literal call sites make the map a drifting duplicate. The fix for a P3 created a P0.

## Solution

Two things caught and resolved it before /work:

1. **5-agent panel convergence** — DHH (P0), code-simplicity (P0), Kieran (P1, with the only co-satisfiable shape), spec-flow re-validation (PAPER verdict) all fired on the same scope. Per the plan-review delete-over-fix rule, the map was deleted rather than reshaped: inline pins + adjacent handwritten log line + a standing allowlist test (architecture-strategist's P1) that guards the policy mechanically — strictly better than the map at its own stated purpose.
2. **Spec-flow re-validation pass** — re-spawning the SAME reviewer on the revision with its own v1 findings list and an explicit paper-resolution mandate ("for EACH v1 finding, verify v2 encodes an implementable mechanism, flag RESOLVED-in-prose") caught both PAPER items (TIER_PINS, the unsatisfiable MODEL_PRICING parity AC) and three findings the revision had silently dropped (P2.9/P3.14/P3.15 untraceable).

## Key Insight

When revising a plan to fold review findings, the new mechanism is itself unreviewed text — diff it against every existing AC/gate before shipping the revision (a 30-second cross-check per mechanism). And when a reviewer's findings drove the revision, re-spawn that reviewer on the revision with its own findings list and a paper-resolution mandate — self-assessed "all findings folded" claims are unreliable; the original finder verifying fix-by-fix is the cheap, high-recall check.

Bonus instance data: "counts drift, lists don't" fired again (plan said 15 cron files; greps showed 16+1 — two reviewers re-derived it independently), and a misnamed artifact ("model allowlist" → actually `MODEL_PRICING`) propagated from a research summary into the plan until a reviewer's grep killed it. Both are existing rule classes; both survived one revision pass and died at the multi-agent panel — corroborating that named-artifact greps belong at plan-WRITE time, not review time.

## Session Errors

1. **TIER_PINS↔AC2 contradiction (v2)** — Recovery: deleted the map per 4-reviewer convergence; standing allowlist test took over the anti-drift role. Prevention: cross-check each revision-added mechanism against all existing ACs; run a finder re-validation pass on revisions.
2. **"Model allowlist" misnomer (v1)** — Recovery: parity invariant re-aimed at `MODEL_PRICING` keys; later the whole FR moved to #5106. Prevention: existing named-artifact verification sharp edges (instance).
3. **15-vs-16 file count (v1/v2)** — Recovery: explicit 16-file list written into #5106. Prevention: existing "counts drift, lists don't" rule (instance).
4. **AC numbering gap (v2)** — Recovery: renumbered in v3. Prevention: renumber on AC deletion; cosmetic.

## Tags

category: workflow-patterns
module: plan, plan-review
