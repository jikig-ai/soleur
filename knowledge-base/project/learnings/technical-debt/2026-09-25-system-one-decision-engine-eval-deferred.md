---
title: System-1 decision engine (Laya/Jev) evaluation deferred until alpha decision corpus exists
date: 2026-09-25
category: technical-debt
tags: [deferred-capability, llm-judgment, laya, jev, system-one, cost, determinism]
severity: low
status: open
---

# System-1 decision engine (Laya/Jev) evaluation deferred until alpha decision corpus exists

## Context

Reviewed 2026-09-25 after both hit the news: TypeSafe **Jev** (closed API, early access —
typed probabilistic decisions, no text generation, ~70–500ms, $0.042/MTok input, output free)
and **Laya** (`NandhaKishorM/laya`, Apache 2.0, open weights — ModernBERT/mmBERT checkpoints
322–421M params, ~33ms/question on T4, same `POST /v1/systemone` wire protocol as Jev, MCP
server available).

Soleur spends LLM judgment on exactly this shape of work — classify / route / gate, not
generate. Candidate surfaces identified:

- `/soleur:go` intent routing (`commands/go.md` → `GO_SKILL_ROUTES` in
  `plugins/soleur/lib/workflow-fidelity.ts`, ~9 labels — inside Laya's <20-option sweet spot)
- Issue/PR triage (`drain-labeled-backlog`, `triage`, ticket-triage) — `predict_batch` fit
- Deferral triple-test (`wg-defer-only-after-inline-triage`, `guardrails.sh`) — `noul` fit
- Passive domain routing (`pdr-*` rules)
- Guardrail classification (injection/credential) as a complement to regex hooks, with
  calibrated-confidence escalation to LLM
- Explicitly NOT: workflow `opts.model` cheap/standard pins (static allowlist is deliberately
  auditable — a learned head trades that for marginal savings)

Decision: **deferred, ~2/10 priority vs alpha onboarding / value-prop validation.**

## Why deferred

1. No decision volume to optimize — zero alpha testers means no triage backlog, no
   mechanical-step spend worth shaving (single-digit $/mo at current volume).
2. Fine-tuning is what makes Laya viable (base checkpoints score ~0.36 vs 0.32 random
   zero-shot on typed-decisions; the 0.766 "beats Jev" figure is after training on the
   benchmark's own split). Fine-tuning needs a labeled corpus of Soleur's OWN decisions,
   which only exists after real usage. Sequence is forced: testers → corpus → evaluation.
3. Install friction at the worst moment — torch + ~1.5GB checkpoints + a running daemon on
   every tester machine across four harnesses, or graceful degradation = a feature that
   mostly doesn't run.
4. Determinism is largely already had via shell hooks / structural gates; the remaining
   LLM-judgment surfaces are the ones where fuzzy judgment is the point.

## Known Laya limits (from its own README — relevant if revisited)

- Confident-wrong is documented (Khmer 0.000 acc @ 0.952 conf; negation #377; `noul`
  label-following #156; score position bias on multilingual). Gate on `answer_confidence`,
  not `confidence` (different semantics than Jev's). Low confidence = escalate to LLM,
  never deny.
- >20 options needs `predict_shortlist` or a raised `head_max_len`; ~50+ collapses
  (Banking77 0.425 vs Jev 0.870).
- Not bit-deterministic across batch shapes near thresholds; test thresholds with margin.
- Single-author upstream — supply-chain/maintenance risk for a prod dependency.
- Jev alternative: same wire protocol, frontier intelligence without fine-tuning, ~cents at
  our volumes — but sends diffs/prompts off-box, which is disqualifying on exactly the
  GDPR-gate surfaces where a local decider is most attractive (data residency is Laya's
  real differentiator).

## Revisit triggers (any one promotes this entry)

1. LLM spend on mechanical steps (classify/route/triage) crosses a felt threshold in the bill.
2. ≥a few hundred logged production decisions exist to fine-tune + eval against.
3. An alpha tester asks for self-hosted inference / data residency.
4. A latency-critical UX surface appears where a multi-second LLM judgment is perceptible.

## Enabling action (cheap, worth doing now)

Make triage/routing decisions land in a durable log — alpha usage then produces the
fine-tune/eval corpus for free. No engine needed for this step.

## Integration sketch (for the revisit)

Shadow first: `laya-serve` local sidecar (Jev wire protocol → swap by repointing baseUrl),
replay real decision corpus, measure zero-shot agreement. Dark-launch behind the LLM path
per `wg-dark-launch-deploy-gates`. Fine-tune `laya-soleur` on disagreements (Kaggle 2×T4
notebook exists, ~4–5h), fit calibration temperatures on held-out Soleur decisions. Promote
per-surface only where measured accuracy justifies.
