---
title: One-shot Retrieval Diagnostic for `knowledge-base/project/learnings/`
date: 2026-05-19
status: decided
participants: founder, CTO, CPO, COO
issue: 4043
lane: cross-domain
brand_survival_threshold: none
---

# One-shot Retrieval Diagnostic for `knowledge-base/project/learnings/`

## What We're Building

A **one-shot diagnostic script** that measures whether `/compound`-produced learnings are actually findable via the lookup mechanism agents use today (kb-search + grep). Outputs corpus-wide R@5 / R@10 / MRR plus a top-N unfindable list. The result is written as a single learning, then #4043 is closed.

This is **not** ongoing infrastructure. It answers the trigger question the 2026-04-07 brainstorm explicitly punted: *"is there evidence that agents consistently fail to find relevant content despite having a manifest and standardized frontmatter?"* Producing that evidence is a finite act, not a recurring one.

## Why This Approach

### The reshape (from issue body to what we're building)

| Issue #4043 proposed | What we're building | Why |
|---|---|---|
| Monthly cron in `.github/workflows/` | One-shot script run by hand | At 841 files and one operator, monthly drift assumption isn't supported. CPO load-bearing call. |
| Output appended to `rule-metrics.json` | Output written as a learning | Aggregator schema collision risk; a learning IS the audit trail. |
| Single LLM-rewrite per file | Identity + light + heavy paraphrase gradient | CTO HIGH-severity risk: rewriter–retriever vocab loop inflates R@5. The gap between identity and heavy is the real signal. |
| Measure kb-search only | Measure kb-search AND grep, report gap | Agents typically grep first. R@5(kb-search) − R@5(grep) = skill ROI signal. |
| Numbers reported | Pre-committed three-bucket action ladder | CPO vanity-metric risk: numbers without committed actions become JSON nobody reads. |

### Scale correction surfaced by research

Issue body says "200+" / "~335" files. Actual count: **841** at `knowledge-base/project/learnings/`. **533/841 lack YAML frontmatter, 67/841 lack a `## Problem` section.** Fallback extraction rules required. Cost recalc with Haiku 4.5 + Batch API + 3 passes per file: ~**$1.30 one-time**.

### Why not defer entirely

CPO's stronger position (close #4043 as premature) was considered. The counter: the 2026-04-07 brainstorm named a specific trigger that has gone unresolved for ~6 weeks. Producing the evidence — even if it cancels the proposal — is what closes the loop. A one-shot diagnostic costs <$2 and one afternoon; deferring keeps the question open indefinitely.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Shape | One-shot diagnostic, not recurring | CPO: one operator, one corpus, drift not supported |
| Output destination | A single learning + close #4043 | The learning IS the audit trail |
| Methodology | Identity + light paraphrase + heavy paraphrase (3 passes) | CTO: gap between identity and heavy is the honest signal; absolute R@K alone is suspect |
| Lookup mechanism | Both kb-search AND grep, report gap | CTO: skill ROI = R@5(kb-search) − R@5(grep) |
| Action ladder (pre-committed) | R@5 ≥ 0.7 → close issue + write learning. R@5 0.4–0.7 → file follow-up for worst-N slug/frontmatter rewrites. R@5 < 0.4 → reopen 2026-04-07 RAG/embeddings decision via new brainstorm. | CPO: action must be committed BEFORE running, not negotiated after |
| Model | Haiku 4.5 via direct Anthropic API curl + Batch API (50% off) | COO: paraphrase is low-complexity; reuse `scripts/compound-promote.sh` lines 124-200 pattern (NDJSON + jq slurp, 15× speedup) |
| Output cost | ~$1.30 one-time, no recurring infra | COO + scale-corrected from CTO finding (841 files × 3 passes × Haiku) |
| Frontmatter fallback | If no YAML frontmatter, use first paragraph after `# Title`. If no `## Problem`, use first 500 chars of body. | Research: 533/841 missing frontmatter, 67 missing `## Problem` |
| Cross-filed learnings | `synced_to:` frontmatter expands the "correct hit" set | Research: cross-category duplicates already exist; both filings count as correct |
| Script location | `scripts/learning-retrieval-bench.sh` | Aligns with sibling `scripts/rule-metrics-aggregate.sh` and `scripts/compound-promote.sh`; not a workflow |

### Lane

Lane override: inferred=single-domain (Engineering), chosen=cross-domain. CTO + CPO + COO all contributed load-bearing decisions; the CPO challenge to the shape itself was the most consequential output of this brainstorm. Single-domain would have produced the wrong shape.

## Open Questions

- **Fixture-seed validation.** The learnings-researcher named 7 concrete fixture seeds (slug mismatches, frontmatter holes, cross-category duplicates via `synced_to:`). These are *pre-known* retrieval-failure shapes. If the bench surfaces them all as findable, the methodology is leaking. If it surfaces them all as unfindable, the diagnostic is catching the right shapes. Should the bench validate against this fixture set as a self-check before reporting corpus-wide numbers?
- **Paraphrase intensity calibration.** "Light" and "heavy" paraphrase need concrete prompts. Light = synonym substitution; heavy = problem reformulation? Plan-time decision.
- **K values.** R@5 and R@10 are both proposed. MRR is rank-aware. Does the action ladder use R@5 (matches the issue) or MRR (sharper signal)? Default to R@5; flag MRR as the secondary number.
- **What if kb-search returns >5 matches and the source is at rank 6-20?** kb-search caps at 20. Bench parses ordering. Need to define how ties are broken when kb-search lists multiple "Title match" results.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Framing is sound — #4043 is the missing measurement apparatus that turns "evidence" from anecdote into a number. Two architecture risks worth flagging: (1) HIGH — self-referential evaluator loop (rewriter–retriever shared vocab inflates R@K); mitigate with identity-prompt baseline + paraphrase-intensity gradient, treat the *gap* as the real signal. (2) MEDIUM — "actual lookup mechanism" is underspecified; measure both kb-search and grep, report `R@5(kb-search) − R@5(grep)` as the skill ROI. Schema additivity: append a new top-level key in `rule-metrics.json` (do NOT mutate `rules[]`) OR use a sibling file. No capability gaps.

### Product (CPO)

**Summary:** The product justification has not changed since 2026-04-07: beta users start with empty learnings, only the operator-of-one experiences current retrieval quality. Monthly cron on a single-operator corpus is overkill. Carve-out: a **one-shot** version (run once, write findings to a learning, close issue) generates the missing failure data cheaply. Two risks: (1) HIGH — vanity metric without action ladder (R@5 < 0.3 has no defined operator response); pre-commit the action ladder. (2) MEDIUM — rewriter-bounded ceiling; synthesized prompts measure paraphrase-to-source recall, not operator-natural-language-to-source recall. Worth stating in any results.

### Operations (COO)

**Summary:** Haiku 4.5 + Batch API (50% off) is the right model tier — paraphrase is low-complexity, keeps the bill negligible. **Output to a sibling JSON file**, not `rule-metrics.json` (schema collision risk with the rule-fire aggregator). Existing rule-metrics workflow is weekly, not monthly as #4043 says — sibling workflow file cleaner than extending if recurring (moot for one-shot). Missing artifact: `knowledge-base/operations/expenses-ledger.md` doesn't exist; this brainstorm is a forcing function to initialize it (deferred to follow-up).

## Capability Gaps

- **`knowledge-base/operations/expenses-ledger.md` does not exist.** Verified via `ls knowledge-base/operations/expenses-ledger.md` (file absent). COO flagged this as a missing forcing function for tracking LLM spend governance. Not a blocker for this brainstorm (one-shot diagnostic ~$1.30 is below any ledger threshold) but worth filing as a follow-up: initialize ops expense ledger when the first recurring LLM-bearing CI workflow lands.

## Productize Candidate

None. The work is explicitly one-shot. If results say R@5 < 0.4 and we reopen the RAG decision, the resulting investment will be much larger than a productized version of this bench.
