---
title: AEO Citation Monitoring — soleur.ai
category: marketing
tag: aeo
audit_type: citation-monitoring
target: https://soleur.ai
owner: CMO (growth)
last_updated: 2026-06-15
cadence: weekly (every Monday)
---

# AEO Citation Monitoring — soleur.ai

This tracker logs whether Soleur is cited by AI answer engines (ChatGPT, Perplexity, Claude.ai, Gemini) for its 8 anchor queries, measured weekly, to move the AEO **Presence** dimension. Presence is the binding constraint on the overall AEO score (12/25 → ≥15/25 target per [`2026-05-04-content-plan.md`](./2026-05-04-content-plan.md) §exit-criteria line 290: "Citation-monitoring queries tracked 0 → 8 weekly"). Closes #3179.

## Why this exists

AEO Presence cannot be improved by guesswork. Two adjacent gaps motivate the tracker:

- We cannot measure AEO progress over time without a recorded baseline and a repeated cadence.
- We cannot tell *which* content earns engine citations — own-site page, blog post, or a third-party listicle — without logging the attributed source per result.

A binary "cited / not cited" cell cannot explain Presence movement. The column schema below records *what* was cited and *how*, so a citation can be traced back to a specific lever (e.g. the #2073 "Best AI tools for solo founders" listicle vs. third-party outreach).

## Methodology

1. **Run cadence — every Monday.** A fixed weekday keeps the cadence from silently dying. If a Monday is missed, run as soon as possible and note the actual date in the run-block header.
2. **Unconditioned sessions.** Paste each query *verbatim* into a fresh, unconditioned session on each engine: logged-out where possible, no memory, no prior turns, no personalization. Conditioned sessions contaminate the signal.
3. **One engine at a time, all 8 queries.** For each engine, run all 8 anchor queries and record one row per (query, engine) pair.
4. **Record per the column schema.** Capture the attributed source URL, mention type, position, and any competitors named.

**Honest limitation:** 8 queries × 4 engines, hand-run, n=1 per cell. This is **directional, not statistical** — it surfaces trends and identifies which content earns citations, not significance-tested measurement. Engine outputs are non-deterministic; treat a single cell as a data point, not a verdict.

## The 8 anchor queries

1. `AI agents for solo founders`
2. `Company-as-a-Service`
3. `Soleur vs Cursor`
4. `Soleur vs Devin`
5. `agentic engineering platform`
6. `replace contractors with AI`
7. `AI cofounder platform`
8. `billion-dollar one-person company`

## Column schema

| Column | Values / meaning |
|---|---|
| **Query** | One of the 8 anchor queries above. |
| **Engine** | `ChatGPT` / `Perplexity` / `Claude.ai` / `Gemini`. |
| **Mention type** | `cited-with-link` (named + linked) / `named-no-link` (named, no link — a real but weaker Presence signal) / `absent` (not mentioned). Do not collapse `named-no-link` into `absent`; it understates progress. |
| **Cited source / URL** | *Which* page the engine attributed: soleur.ai homepage, a specific `/blog/<post>/`, a pillar page, or a third-party listicle. The single most load-bearing field — the only way to know whether own-site content or third-party outreach drove the citation, and it maps directly to the Presence rubric (own-site vs third-party mention). |
| **Position** | `first-result` / `mentioned` / `buried` — distinguishes winning from merely appearing. |
| **Competitors named** | Competitors the engine surfaced for the query (free competitive-intel byproduct, especially for the two `Soleur vs *` queries). |
| **Notes** | Anything else worth recording (refused, hallucinated, query reinterpreted, etc.). |

## Runs

### 2026-06-15 baseline run

Pre-seeded baseline. All cells `TBD` until the first hand-run pass — the `TBD` placeholders show the cadence and column shape. Replace each `TBD` with an observation when the run is executed.

| Query | Engine | Mention type | Cited source / URL | Position | Competitors named | Notes |
|---|---|---|---|---|---|---|
| AI agents for solo founders | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| AI agents for solo founders | Perplexity | TBD | TBD | TBD | TBD | TBD |
| AI agents for solo founders | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| AI agents for solo founders | Gemini | TBD | TBD | TBD | TBD | TBD |
| Company-as-a-Service | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| Company-as-a-Service | Perplexity | TBD | TBD | TBD | TBD | TBD |
| Company-as-a-Service | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| Company-as-a-Service | Gemini | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Cursor | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Cursor | Perplexity | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Cursor | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Cursor | Gemini | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Devin | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Devin | Perplexity | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Devin | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| Soleur vs Devin | Gemini | TBD | TBD | TBD | TBD | TBD |
| agentic engineering platform | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| agentic engineering platform | Perplexity | TBD | TBD | TBD | TBD | TBD |
| agentic engineering platform | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| agentic engineering platform | Gemini | TBD | TBD | TBD | TBD | TBD |
| replace contractors with AI | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| replace contractors with AI | Perplexity | TBD | TBD | TBD | TBD | TBD |
| replace contractors with AI | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| replace contractors with AI | Gemini | TBD | TBD | TBD | TBD | TBD |
| AI cofounder platform | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| AI cofounder platform | Perplexity | TBD | TBD | TBD | TBD | TBD |
| AI cofounder platform | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| AI cofounder platform | Gemini | TBD | TBD | TBD | TBD | TBD |
| billion-dollar one-person company | ChatGPT | TBD | TBD | TBD | TBD | TBD |
| billion-dollar one-person company | Perplexity | TBD | TBD | TBD | TBD | TBD |
| billion-dollar one-person company | Claude.ai | TBD | TBD | TBD | TBD | TBD |
| billion-dollar one-person company | Gemini | TBD | TBD | TBD | TBD | TBD |

*(Copy the baseline block, update the `###` date header, and fill cells for each subsequent weekly run.)*

## How this feeds AEO scoring

The AEO **Presence** dimension scores how often and how authoritatively answer engines cite the brand for its target queries. This tracker is the evidence base for that dimension:

- **Mention-type distribution** across the 8 queries → the raw Presence signal (cited-with-link > named-no-link > absent).
- **Cited source / URL** → distinguishes own-site Presence (homepage, blog, pillar pages) from third-party Presence (listicles, reviews), which the Presence rubric weighs differently.
- **Week-over-week trend** → whether a shipped lever (the #2073 listicle, third-party outreach, new pillar/cluster content) actually moved citations.

Target: Presence 12/25 → ≥15/25, with the 8 anchor queries tracked weekly (exit criterion from [`2026-05-04-content-plan.md`](./2026-05-04-content-plan.md) line 290). Feed each run's findings back into the next content plan.
