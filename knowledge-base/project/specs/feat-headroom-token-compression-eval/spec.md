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

**Not adopted, for either audience — but on DIFFERENT grounds, and the two lists must not be
merged.** Full reasoning and evidence in the brainstorm.

**This separation is the whole point of the record.** An earlier draft of this section listed
"no marginal cost to save" as one of three grounds "any one sufficient" for "either audience".
That is wrong for users and was retracted at operator review: Soleur users run **BYOK on their
own Anthropic key**, so tokens are real money to them and cap headroom is finite. `$0/token` is
an operator-side billing fact about a flat Max 20x subscription; extending it to users was the
error. Do not re-merge these lists.

### Operator (our own dev loops)

1. **Reachable surface is 2–3%.** 98.17% of tokens are cache reads (measured, 42 transcripts /
   44,620 messages); the 46,000 B always-loaded rule corpus is frozen-prefix and untouchable by
   live-zone compression; tool output is median 410 B; the corpus is prose, which Headroom
   itself says compresses least.
2. **Correctness risk (the disqualifier).** Measured: 244 of 581 modified payloads lose ≥1
   gate-relevant literal.
3. *Weakly* — no metered spend today (`api-spend-ledger.jsonl` empty, flat Max 20x, ADR-056).
   Listed last and marked weak deliberately: a flat invoice is not a free resource. More tokens
   still consume rate-limit headroom. This ground is about the INVOICE, never about users.

### Users (BYOK, server-side sandbox)

1. **Structural.** They run agents server-side in a sandbox and have no local agent to wrap.
2. **The insertion point is disqualifying.** The only one available puts a third-party proxy in
   the **BYOK credential path** and desyncs ADR-041 cap accounting from the real bill.
3. **Correctness**, as above.

**Explicitly NOT a ground for the user half: cost.** BYOK users pay per token, so reducing
their spend is a legitimate goal that this tool does not serve — not a goal that does not
exist. Carried forward from the brainstorm's Key Decision 2b: **BYOK token reduction remains an
open, legitimate user-value objective.** A future session must not read this NO-GO as closing it.

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
   zero divergence** across the set ENUMERATED in the brainstorm's re-evaluation
   criterion 2 (three `hr-*` grep-discharged gates plus `extract-block.cjs`'s
   marker `indexOf`) — note §3b measured the `eval-gate:block` markers at **zero**
   losses, so that arm is a guard against regression, not a reported finding; **and**
3. compression is confinable to tool output no gate greps, or those gates are made
   compression-safe first.

## Follow-up

The evaluation surfaced that Soleur has **no token-usage baseline** — the CFO's P0 from the
2026-04-13 token-optimization brainstorm was never executed. That is the actual prerequisite
for this and every future token-cost decision. Tracked by **#1055** (per-workflow/per-agent cost observability), **#6297** and **#5692**. No new issue filed — the measurement gap this evaluation surfaced is exactly what those three already cover.
