---
title: Golden tasks for a literal-token-scan classifier must avoid semantically-adjacent but token-absent inputs
date: 2026-06-29
category: best-practices
tags: [eval-harness, golden-sets, classifier-gate, token-scan, fixture-design]
module: eval-harness
related-issues: [#5704]
related-learnings:
  - knowledge-base/project/learnings/2026-06-29-eval-gate-target-validity-and-three-map-drift.md
  - knowledge-base/project/learnings/2026-05-15-classifier-prose-table-row-ordering-collision.md
---

# Learning: golden tasks for a token-scan classifier must not straddle semantic-vs-token

## Problem

The brainstorm lane-inference rule is an explicit *case-insensitive token scan* (cross-domain iff one
of `audit|security|billing|payment|…` appears literally; procedural iff a procedural token AND no
cross-domain token). A synthesized golden task `"Refine the subscription cancellation email copy"` was
labeled `single-domain` — correct under the rule (no literal cross-domain token), but `"subscription
cancellation"` is **billing-adjacent semantically**. An LLM skill-arm reasoning by topic (not by
literal token) could classify it `cross-domain` on some samples, making that golden task flaky in the
actual eval even though the label is rule-correct. An independent label-verification agent flagged it
as the one fixture where strict-token and semantic readings diverge.

## Solution

Reword the input to remove the semantic adjacency while keeping the label: `"Refine the onboarding
welcome email copy for clarity"` (still `single-domain`, but no token any reader associates with the
cross-domain list). For a classifier whose rule is a literal token scan, every golden input should be
unambiguous under BOTH a token reading AND a semantic reading — or it tests rule-fidelity by accident
and flakes the measurement.

## Key Insight

A golden label must be the single defensible answer under the *actual* decision procedure AND under
the way the LLM-arm will plausibly reason. When the rule is literal-token but the model reasons
semantically, an input that is token-clean but semantically-adjacent to another class is a latent flake
— not a wrong label, but a non-robust fixture. Either (a) reword to remove the adjacency (default), or
(b) keep it ONLY as a deliberate, documented token-strictness distractor. This is the complement of the
adversarial-overlap rule (`2026-05-15-classifier-prose-table-row-ordering-collision`): that one says
*include* cross-label-overlap cases to catch collisions; this one says don't let an *unintended*
semantic overlap masquerade as a clean single-label case. Cheapest gate: when you cannot run the eval
(no API key in-session), have an agent independently classify each golden against the rule prose and
flag any semantic-vs-rule divergence before shipping the corpus.

## Tags
category: best-practices
module: eval-harness
