---
date: 2026-06-29
category: workflow-patterns
module: agent-reasoning
problem_type: wrong-assumption
severity: medium
symptoms:
  - dismissed real research/products as AI-generated fabrication
  - "called a real model (GPT-5.5) fake based on training knowledge"
  - user had to correct and request web verification
root_cause: knowledge-cutoff-staleness treated as ground truth for existence claims
tags: [knowledge-cutoff, verification, websearch, hallucination-inversion, brainstorm]
related:
  - hr-verify-repo-capability-claim-before-assert
---

# Learning: Verify post-cutoff existence before asserting fabrication

## Problem

During an article review (skill-eval-gate brainstorm, 2026-06-29), I flagged "SkillOpt (Microsoft
Research)", "EvoSkill", and "GPT-5.5" as likely AI-generated fabrications — citing suspiciously
precise benchmark numbers and an unfamiliar model name. I reasoned from my training knowledge
cutoff (Jan 2026). All three are real: SkillOpt (MS Research, arXiv 2605.23904, MIT, May 2026),
EvoSkill (arXiv 2603.02766, sentient-agi), and GPT-5.5 (shipped). The user corrected me and asked
me to web-search — which immediately confirmed all three.

## Solution

When judging whether a named system, model, paper, product, or company is real, treat the knowledge
cutoff as a hard boundary: a "this is fake / doesn't exist / is probably hallucinated" claim is
**unreliable for anything dated after the cutoff**. Run `WebSearch` (and `WebFetch` for specifics)
BEFORE asserting non-existence. Today's date (surfaced in session context) vs. the cutoff is the
trigger — if the entity could plausibly postdate the cutoff, verify, don't dismiss.

Skepticism about *unsourced specific claims* (exact benchmark deltas) is still fine — but attach it
to the claim ("I can't verify these numbers"), not to the entity's existence ("this system is fake").

## Key Insight

This is the inverse of the usual hallucination guard. The usual failure is *inventing* things that
don't exist; this failure is *denying* things that do, because they postdate training. Both are
fixed by the same discipline already encoded in `hr-verify-repo-capability-claim-before-assert`
(verify a capability claim before asserting it) — extended from repo capabilities to external-world
existence. Verify before asserting, in both directions.

## Session Errors

- **Asserted SkillOpt/EvoSkill/GPT-5.5 were likely fabrications based on stale cutoff** — Recovery: user instructed web-search, which confirmed all three real. Prevention: WebSearch any post-cutoff-plausible named entity before claiming it doesn't exist (this learning + route-to-definition proposal).
- **Called `Monitor` tool to wait on a background agent without loading its schema** — Recovery: harness returned InputValidationError with the schema; I dropped the call (background agents notify on completion automatically — no polling needed). Prevention: one-off; deferred-tool guidance already requires ToolSearch before calling. No action.

## Tags
category: workflow-patterns
module: agent-reasoning
