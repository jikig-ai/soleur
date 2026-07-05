# Learning: External-framework/article brainstorms must audit existing Soleur primitives before framing as greenfield

## Problem

A `/soleur:go` request asked to "apply the techniques from this article to Soleur" — the article
described two 2026 research frameworks (Self-Harness arXiv 2606.09498, HarnessX arXiv 2606.14249)
for autonomous agent-harness self-improvement. The naive path is to treat "apply framework X" as a
greenfield build. But Soleur had **already implemented ~70% of both frameworks** before the article
existed:

- Self-Harness's 3-stage loop ≈ `every-session-error→learning` gate + `/compound` (mining) →
  `cron-compound-promote.ts` (proposal) → `eval-gate.cjs` + ADR-069 (validation).
- HarnessX's typed-swappable-processor composability ≈ change-class `session-rules-loader.sh` +
  ToolSearch MCP deferral + the #5768 harness-L3 work.
- The exact "weekly cross-session pattern sweep" was already designed as Layer 2 of the 2026-03-03
  self-healing-workflow (#397) — and explicitly deferred.

Framing it greenfield would have re-specced shipped infrastructure and missed that the loop is open
at exactly **one** stage (weakness-mining / recurring-failure clustering).

## Solution

Reframed the brainstorm from "adopt Self-Harness/HarnessX" to "**audit the existing loop + close the
one open stage.**" Concretely, before dialogue: verified the frameworks are real (WebSearch/WebFetch —
both had arXiv papers + a real GitHub repo), then ran repo-research + learnings agents whose prompts
were "MAP THE CURRENT STATE and find the GAP — do not propose from scratch." The output was a
stage→primitive→automation→gap table, not a design. Scoped increment A (read-only weakness-miner,
#6037) with B/C deferred (#6038/#6039).

## Key Insight

When a brainstorm is triggered by an external paper/article/framework ("apply technique X to us"),
the first move is an **existing-primitive audit**, not a greenfield design. Map each concept in the
source to Soleur's current implementation and its automation level; the productive deliverable is a
gap-map that finds the *one* open stage, then scopes the smallest zero-risk increment that closes it.
This is distinct from the existing "check existing KB artifacts" pre-research step — the source here
isn't a prior Soleur artifact, it's an external framework, so the audit has to translate the
framework's vocabulary into Soleur's primitives first.

Corollary caught during the audit: `rule-metrics.json` showed 97 rules with 0 fires over 8 weeks —
`.rule-incidents.jsonl` telemetry is captured but never read by automation, so rule-fire counts are
not a usable weakness signal today (folded into #6037's secondary output).

## Session Errors

None detected. The greenfield→audit reframe was a deliberate research finding, not an error.
**Prevention:** the route-to-definition bullet below makes the audit-first move a default for
external-framework brainstorms so future sessions don't start from the greenfield framing.

## Tags
category: workflow-patterns
module: brainstorm
