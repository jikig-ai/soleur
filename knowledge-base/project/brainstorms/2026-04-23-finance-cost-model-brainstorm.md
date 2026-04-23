---
name: finance-cost-model
description: Brainstorm for issue #1053 — create knowledge-base/finance/cost-model.md as a derived summary of the live expense ledger, with explicit R&D/COGS burn split and sync of stale roadmap narrative.
type: brainstorm
date: 2026-04-23
issue: "#1053"
status: decided
---

# Finance Cost Model — Brainstorm

**Issue:** #1053 (OPEN, P2-medium, milestone "Phase 4 (Validate + Scale)")
**Domain:** Finance
**Branch:** `feat-finance-cost-model`
**Draft PR:** #2835

## What We're Building

`knowledge-base/finance/cost-model.md` — a living document that is a *derived view* over `knowledge-base/operations/expenses.md` (the authoritative ledger), with:

1. Monthly burn (split into **R&D/tooling** vs **product COGS**) — every line anchored to the ledger.
2. Per-user infrastructure cost model, built on BYOK as an architectural commitment (zero per-user inference cost).
3. Break-even analysis computed from both burn scopes.
4. Scaling triggers (Supabase 500 MB DB / 50 K MAU, CX33 10-12 concurrent sessions, X API Basic at first paying customer, etc.) each with an upgrade-cost delta.
5. Gross-margin-at-scale math with the 93 % claim shown.
6. Open questions and references.

The same PR also syncs `knowledge-base/product/roadmap.md` (L63 CFO assessment line, L397 Pricing Gate #4 status line) so the roadmap narrative matches the new cost-model.md numbers.

## Why This Approach

### Why derived-view over second ledger

`operations/expenses.md` is already the single source of truth (ops-advisor/ops-provisioner/ops-research/COO all write here; `/ship` Phase 5.5 COO gate keeps it current). A second ledger in `finance/` would drift the moment either side changes. Instead, cost-model.md carries inline anchors (`[expenses.md@2026-04-19]`) so every number is date-stamped and traceable. This matches how `product/roadmap.md` summarizes milestone state without duplicating `gh issue` data.

### Why R&D/COGS burn split

The issue's claimed burn of **EUR 35-44 / break-even 1-2 users** does not match the current ledger. Recomputed from `expenses.md` @ 2026-04-19:

| Line                                  |  USD/mo |
| ------------------------------------- | ------: |
| GitHub Copilot                        |   10.00 |
| Hetzner CX33                          |   15.37 |
| Hetzner Volume                        |    0.88 |
| Supabase Pro + custom domain          |   35.00 |
| Plausible                             |    9.00 |
| Anthropic API (ux-audit)              |  ~15.00 |
| Claude Code Max 20× × 2 seats         |  400.00 |
| Cloudflare domain (amortized $70/yr)  |    5.83 |
| **All-in recurring**                  | **~491** |

The Feb-2026 CFO figure omitted Supabase Pro, Claude Code Max seats, Plausible, and the Anthropic API line. At $49/month gross, all-in break-even is ~11 paying users, not 1-2.

**Split resolves the honesty tension.** Treat Claude Code Max seats + GitHub Copilot as R&D/dev tooling (defensible — they accelerate engineering, not per-user product delivery). Product COGS reduces to ~$91/month (CX33 + volume + Supabase Pro + Plausible + Anthropic ux-audit + Cloudflare). Break-even at $49/month product COGS ≈ **2-3 users**, which is closer to the original spirit of the CFO narrative while being materially correct.

The single-number framings (EUR 35-44 or $491) each have a failure mode: the small number collapses under scrutiny; the large number misrepresents product economics. The split is defensible and carries forward cleanly into pricing conversations.

### Why cross-reference, don't duplicate

- Prior learnings flagged stale cross-references after KB restructuring ([2026-03-13-stale-cross-references-after-kb-restructuring](../learnings/2026-03-13-stale-cross-references-after-kb-restructuring.md)).
- Cross-domain disambiguation learnings warn that adding a new domain without back-links leaves it invisible ([2026-02-22-cross-domain-disambiguation-is-bidirectional](../learnings/2026-02-22-cross-domain-disambiguation-is-bidirectional.md)). cost-model.md needs back-links from `ops/expenses.md` and `product/pricing-strategy.md`, not just forward links.
- Frontmatter with `last_updated`, `review_cadence`, `depends_on` matches the strategy-review-cadence convention ([2026-03-23-strategy-review-cadence-system](../learnings/2026-03-23-strategy-review-cadence-system.md)).

### Why partial Pricing Gate #4 framing

Roadmap L152 defines Gate #4 as "Infrastructure ready" — cloud sync, hosted execution, and analytics dashboard are buildable (not necessarily built). Cost-model.md addresses the *affordability* dimension. The *buildability* dimension stays with CPO/CTO. Framing this explicitly in the opening of cost-model.md prevents issue #1053 from false-closing Gate #4 when it merges.

### Why no sibling finance docs in this PR

The CFO assessment recommended against creating revenue-model.md, burn-rate.md, or break-even.md as standalone files: pre-revenue (Stripe in test mode, zero paying users) means revenue-model is speculative; break-even math is a few paragraphs and belongs inline; pricing economics already live in `product/pricing-strategy.md` + `finance/memos/2026-04-19-conversation-slot-economics-cfo-reconsult.md`. Stubs violate YAGNI and rot per the strategy-review-cadence learning.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Single file `knowledge-base/finance/cost-model.md` (Approach A — derived summary). | Matches repo's derived-from-ledger pattern; minimal rot surface. |
| 2 | Burn reported as R&D/tooling split from product COGS, with both numbers and break-even computed for each. | Honest and defensible; preserves spirit of original CFO narrative while correcting the ledger. |
| 3 | Every number in cost-model.md carries an inline anchor `[expenses.md@YYYY-MM-DD]`. | Enforces traceability; breaks cleanly when ledger date changes. |
| 4 | Frontmatter: `last_updated`, `last_reviewed`, `review_cadence: monthly`, `owner: cfo`, `depends_on: [operations/expenses.md, product/pricing-strategy.md]`. | Matches `marketing/brand-guide.md` + `product/roadmap.md` convention. |
| 5 | Same PR syncs `product/roadmap.md` L63 (CFO assessment line) + L397 (Pricing Gate #4 status line) to match new numbers. | Prevents a merged cost-model.md from immediately contradicting the roadmap. |
| 6 | Cost-model.md positions as *partial* addressal of Pricing Gate #4 (affordability only); buildability stays with CPO/CTO. | Prevents false Gate-4 closure from #1053 merge. |
| 7 | No sibling finance docs (no revenue-model.md, break-even.md, burn-rate.md, pricing-model.md). | CFO-validated YAGNI; pre-revenue, so most would be stubs. |
| 8 | BYOK called out as architectural commitment: "BYOK is a cost-model-load-bearing architecture commitment; revisit if a managed-LLM tier is ever considered." | Future-proofs the $0 per-user inference-cost claim; no new ADR needed (ADR-004 covers encryption; cost is policy). |
| 9 | Refresh mechanism: frontmatter + existing `/ship` Phase 5.5 COO gate. Add one AGENTS.md Workflow Gate: "When editing `operations/expenses.md`, re-read `finance/cost-model.md` and refresh if totals shifted >10 %." | No new hook surface; leverages existing COO→CFO handoff. |
| 10 | Gross-margin math shown (not stated): derive 93 % claim explicitly, note Stripe fee drag (1.5 % + EUR 0.25 per EU charge) which prior framing ignored. | Claim needs math to survive scrutiny. |
| 11 | CX22 line in issue-description summary dropped (ledger only shows active CX33). CX22 covered under `telegram-bridge` — COGS if bridge is product, R&D if internal. Classify as R&D/tooling for now; revisit when/if bridge is productized. | Avoid propagating stale server lines into cost-model.md. |
| 12 | Reference the 2026-04-19 CFO conversation-slot memo under References; do not absorb it (memo is a dated decision record with point-in-time framing that cost-model.md as a living doc would lose). | Keeps memo's role clean; keeps cost-model.md focused. |

## Proposed Structure for cost-model.md

1. Frontmatter (see Decision #4)
2. `## Monthly Burn` — two tables (R&D/tooling, product COGS), each anchored to ledger date, with split rationale
3. `## Per-User Infrastructure Cost` — CX33 capacity model (10-12 concurrent sessions without Playwright), volume amortization, BYOK zero-inference claim and architectural commitment note
4. `## Break-Even Analysis` — users-to-cover-burn at $49/month, both scopes (R&D-inclusive and COGS-only), Stripe fee drag acknowledged
5. `## Scaling Triggers` — Supabase Pro-tier already active (baseline); next triggers: 500 MB DB / 50 K MAU / 1 GB file / 2 GB bandwidth (all on Pro); CX33 session capacity → CX43 at ~11 concurrent; X API Basic ($100/mo at first paying customer per #497); Buttondown, Resend, Plausible tier thresholds
6. `## Gross Margin at Scale` — math shown for 50 users @ $49 against product COGS (~80 %, not 93 %); note Stripe fee drag
7. `## Pricing Gate #4 Status` — partial addressal (affordability only); buildability handoff to CPO/CTO
8. `## Open Questions` — Claude Code Max seat classification; CX22 `telegram-bridge` classification; managed-LLM tier impact on BYOK claim; cost-model review cadence ownership
9. `## References` — expenses.md, pricing-strategy.md, roadmap.md Phase 4.10, ADR-004-byok-encryption-model, 2026-04-19 CFO conversation-slot memo

## Open Questions

- **Claude Code Max seat classification for public framing.** Internally split is defensible. Externally (e.g., if the cost model is ever shared with investors or in marketing), does "$91/month product COGS" hold up to scrutiny when tooling costs are visible in `expenses.md`? Propose: cost-model.md is internal-first; produce an external-facing summary only when needed.
- **Should pricing-strategy.md reference cost-model.md directly**, or only the roadmap? Leaning yes — pricing-strategy.md §Gate #4 benefits from a deep link. Decide in plan phase.
- **CX22 (telegram-bridge) R&D vs COGS.** Currently classed as R&D. If telegram bridge becomes a paying-customer channel, reclass.
- **Is a freshness lint needed in this PR**, or defer? CFO recommended against a dedicated hook; rely on `/ship` Phase 5.5 COO gate. Lint is a follow-up if drift materializes.

## Domain Assessments

**Assessed:** Finance (relevant), Operations (relevant — but CFO absorbed ops expense-ledger context; no separate COO spawn), Marketing (not relevant), Engineering (not relevant — no code), Product (partially relevant via Pricing Gate #4 — handled inline), Legal (not relevant), Sales (not relevant), Support (not relevant).

### Finance (CFO)

**Summary:** Recommended Approach A (single derived-view file), flagged the burn-number discrepancy (~10× off) as the highest-signal finding, recommended the R&D/COGS split as the defensible reconciliation, validated that cost-model.md only partially addresses Pricing Gate #4, recommended no sibling finance docs in this PR, and delegated sole authorship to budget-analyst. Proposed frontmatter convention, refresh mechanism via existing `/ship` Phase 5.5 COO gate rather than new hooks or cron.

## Capability Gaps

None new. Existing capability (budget-analyst, CFO, ops-advisor, `/ship` Phase 5.5 COO gate) is sufficient to author and maintain cost-model.md.
