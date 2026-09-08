---
title: "Headroom token-compression evaluation — decision record (no-build)"
feature: feat-headroom-token-compression-eval
date: 2026-09-07
status: decided-no-build
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-07-headroom-token-compression-eval-brainstorm.md
---

# Spec — Headroom evaluation (no-build outcome)

This spec exists to record a **decision not to build**. There are no functional
requirements, because nothing is being implemented. It carries the lane and
brand-survival threshold forward per the brainstorm→plan contract, and it fixes the
re-evaluation criteria so a future session certifies a trigger instead of re-deriving
the analysis.

## Problem Statement

Determine whether Headroom (<https://github.com/headroomlabs-ai/headroom>) — a local
token-compression proxy/library for AI coding agents — should be adopted to reduce token
consumption for (a) Soleur's own development sessions and (b) Soleur end users.

## Outcome

**Not adopted, for either audience.** Full reasoning and evidence in the brainstorm.
Three independent grounds, any one sufficient:

1. **No marginal cost to save.** Local loops run on a flat Max 20x subscription
   ($0/token, ADR-056); `knowledge-base/finance/api-spend-ledger.jsonl` is empty.
2. **Reachable surface is 2–3%.** 98.17% of tokens are cache reads (measured, 42
   transcripts / 44,620 messages); the 46,000 B always-loaded rule corpus is frozen-prefix
   and untouchable by live-zone compression; tool output is median 410 B; the corpus is prose,
   which Headroom itself says compresses least.
3. **Correctness risk is the disqualifier.** Lossy tool-output rewriting manufactures false
   negatives in grep-discharged gates (`hr-verify-repo-capability-claim-before-assert`,
   `hr-third-party-content-grep-on-undertaking`, `hr-type-widening-cross-consumer-grep`,
   `extract-block.cjs` marker `indexOf`). CCR retrieval relocates rather than mitigates,
   because retrieval is model-initiated and the failure mode is false confidence.

For end users the answer is structural: they run agents server-side in a sandbox and have
no local agent to wrap. The only insertion point would put a third-party proxy in the BYOK
credential path and desync ADR-041 cap accounting from the real bill.

## Non-Goals

- Vendoring or bundling Headroom.
- Running `headroom learn` against this repo under any circumstances (trips the 46,000 B
  ratchet; bypasses `cq-agents-md-tier-gate`, `cq-rule-ids-are-immutable`, ADR-155 markers,
  and the `lint-rule-bodies.py` WORM ack manifest).
- Evaluating Serena MCP, which is separable and undecided.

## Constraints carried forward

- **TR1** — Any future re-evaluation must run the falsification offline, over archived
  `tool_result` payloads, with no proxy, no `wrap`, and no user-scope `~/.claude.json` write.
- **TR2** — If ever piloted: pin exact package version + checksum, pin the HuggingFace model
  by revision SHA (never `main`), set `HEADROOM_BEACON=off`, and never point it at customer
  content under a Jikigai credential (CLO).
- **TR3** — Depend, never vendor (Apache-2.0 §4 obligations trigger on distribution).

## Re-evaluation criteria (ALL must hold)

1. `api-spend-ledger.jsonl` is non-empty and monthly metered spend is material; **and**
2. an offline run over archived `tool_result` payloads ≥2 kB shows **>15% reduction** **and
   zero divergence** across `extract-block.cjs` and the four grep-based gates above; **and**
3. compression is confinable to tool output no gate greps, or those gates are made
   compression-safe first.

## Follow-up

The evaluation surfaced that Soleur has **no token-usage baseline** — the CFO's P0 from the
2026-04-13 token-optimization brainstorm was never executed. That is the actual prerequisite
for this and every future token-cost decision. Tracked separately.
