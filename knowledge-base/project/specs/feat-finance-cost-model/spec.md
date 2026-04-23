# Feature: finance-cost-model

**Issue:** #1053
**Branch:** `feat-finance-cost-model`
**Draft PR:** #2835
**Brainstorm:** [../../brainstorms/2026-04-23-finance-cost-model-brainstorm.md](../../brainstorms/2026-04-23-finance-cost-model-brainstorm.md)

## Problem Statement

No finance artifacts exist in `knowledge-base/finance/` (only a `memos/` subdir with point-in-time CFO memos). The Feb-2026 CFO assessment that feeds the roadmap and pricing narrative lives only in a brainstorm document. The assessment's monthly burn number (EUR 35-44) and break-even (1-2 paying users at $49/month) are stale vs the current `operations/expenses.md` ledger (2026-04-19) — recomputed all-in burn is ~$491/month (~11 users to break even), or ~$91/month product-COGS-only (~2-3 users) if Claude Code Max seats and GitHub Copilot are classed as R&D/tooling.

Without a living cost model:

- The roadmap and pricing pages carry a number that collapses under first-principles scrutiny.
- Pricing Gate #4 ("Infrastructure ready") has no documented cost-side readiness assessment.
- Future finance specialists (budget-analyst, revenue-analyst) have no canonical cost-model to build forecasts on.
- BYOK's "zero per-user inference cost" is a policy claim, not a documented architectural commitment.

## Goals

1. Create `knowledge-base/finance/cost-model.md` as a derived-view living document over `operations/expenses.md`, with the R&D/tooling burn split from product COGS and both break-even computations shown.
2. Every cost figure in cost-model.md is anchored to a dated ledger reference (`[expenses.md@YYYY-MM-DD]`) so stale numbers surface on the next review.
3. Sync `product/roadmap.md` narrative (L63 CFO line, L397 Pricing Gate #4 status) in the same PR so the roadmap and cost-model.md do not contradict each other at merge time.
4. Document BYOK as an architectural cost commitment (not just an encryption choice).
5. Establish a freshness mechanism that leverages the existing `/ship` Phase 5.5 COO→CFO handoff (no new hooks, no cron).
6. Partially close Pricing Gate #4 (affordability dimension only); explicitly hand off buildability to CPO/CTO.

## Non-Goals

- No new sibling finance docs (revenue-model.md, burn-rate.md, break-even.md, pricing-model.md). Pre-revenue; stubs violate YAGNI.
- No absorption of the 2026-04-19 CFO conversation-slot-economics memo into cost-model.md. The memo is a dated decision record and retains its own framing.
- No new dedicated freshness-lint hook (`.claude/hooks/finance-freshness.sh`). Rely on existing `/ship` Phase 5.5 COO gate and frontmatter-based strategy-review-cadence cron.
- **No AGENTS.md workflow gate rule** (original FR6 — deferred during plan review 2026-04-23). Rationale: (a) AGENTS.md is already 84 bytes over the 40 KB warn threshold; (b) frontmatter (`review_cadence: monthly`, `depends_on`) + strategy-review-cadence cron covers this file class's freshness; (c) the rule can be added later if observation (post-merge AC #2 in plan) shows silent rot. See `knowledge-base/project/plans/2026-04-23-docs-finance-cost-model-and-roadmap-sync-plan.md` §Alternative Approaches.
- No new CFO-cron scheduled agent.
- No claim that cost-model.md closes Pricing Gate #4 — it only addresses the affordability dimension.
- No external-facing cost disclosure (cost-model.md is internal-first; external-facing derivatives are a separate future concern).

## Functional Requirements

### FR1: Cost model file with frontmatter

Create `knowledge-base/finance/cost-model.md` with frontmatter matching the repo strategy-doc convention:

```yaml
---
last_updated: 2026-04-23
last_reviewed: 2026-04-23
review_cadence: monthly
owner: cfo
depends_on:
  - knowledge-base/operations/expenses.md
  - knowledge-base/product/pricing-strategy.md
---
```

### FR2: Nine body sections

1. `## Monthly Burn` — two tables (R&D/tooling, product COGS) with an explanatory paragraph on the split rationale; both totals.
2. `## Per-User Infrastructure Cost` — CX33 capacity model (10-12 concurrent agent sessions without Playwright), volume amortization, BYOK zero-inference claim, explicit BYOK architectural-commitment note.
3. `## Break-Even Analysis` — math at $49/month for both scopes, Stripe fee drag acknowledged (1.5 % + EUR 0.25 per EU charge).
4. `## Scaling Triggers` — Supabase Pro (baseline; next triggers 500 MB DB / 50 K MAU / 1 GB storage / 2 GB bandwidth), CX33 session capacity (upgrade to CX43 at ~11 concurrent), X API Basic ($100/mo at first paying customer per #497), Resend, Buttondown, Plausible tier thresholds. Each with upgrade-cost delta.
5. `## Gross Margin at Scale` — 50-user @ $49/month worked example against product COGS (~80 %, not 93 % as previously claimed), with Stripe fee drag.
6. `## Pricing Gate #4 Status` — partial addressal (affordability only); buildability handoff to CPO/CTO.
7. `## Open Questions` — Claude Code Max seat classification for external framing; CX22 telegram-bridge R&D/COGS split; managed-LLM-tier impact on BYOK.
8. `## References` — `operations/expenses.md`, `product/pricing-strategy.md`, `product/roadmap.md` (Phase 4.10 + Pricing section), `engineering/architecture/decisions/ADR-004-byok-encryption-model.md`, `finance/memos/2026-04-19-conversation-slot-economics-cfo-reconsult.md`.

### FR3: Inline ledger anchors

Every numeric figure in cost-model.md that originates in `expenses.md` MUST be followed by an inline anchor of the form `[expenses.md@YYYY-MM-DD]`. Anchors use the `last_updated` of the expense ledger at the time the cost model row was last reconciled.

### FR4: Roadmap narrative sync

In the same PR, update `product/roadmap.md`:

- CFO burn line (L63 at plan time) — reframe from "Break-even at 1-2 paying users. EUR 35-44/month burn." to the split formulation ("~$91/month product COGS (break-even 2-3 users), ~$491/month all-in (break-even ~11 users). BYOK eliminates per-user LLM cost. Dev-tooling classed R&D.").
- CFO artifact line (L64 at plan time) — update from "No finance artifacts exist. Need cost model." to reflect that cost-model.md has shipped and partially addresses Pricing Gate #4.
- Pricing Gate #4 status row (L404 at plan time, **not L397** as originally specced — see plan's Research Reconciliation) — update status to "Partial. Affordability documented in `finance/cost-model.md`; buildability pending CPO/CTO assessment."
- Cost-model.md action item (L416 at plan time) — mark disposition as shipped with partial Gate #4 closure.
- `## Current State` section — add a "Financial posture" sub-bullet naming both burn scopes and cross-linking to `finance/cost-model.md` so operators reading the roadmap summary see the reconciled numbers, not just the tables.
- Advance `last_updated` frontmatter to the PR's merge date (or author date for pre-merge review).
- Work-time note: re-grep for "CFO" and "Infrastructure cost model" anchors before editing — line numbers may have drifted since plan time.

### FR5: Back-links from dependent docs

Add back-links (one line each) to cost-model.md from:

- `operations/expenses.md` — "Finance consumer: [finance/cost-model.md]".
- `product/pricing-strategy.md` — Gate #4 section references `finance/cost-model.md`.

### FR6: [DEFERRED — originally "AGENTS.md Workflow Gate rule"]

Deferred during plan review (2026-04-23) — see Non-Goals for rationale. If post-merge observation (plan AC #2) shows silent rot, a follow-up PR may add the rule.

## Technical Requirements

### TR1: Markdownlint clean

The new doc and the roadmap/back-link edits MUST pass `npx markdownlint-cli2 --fix` on the changed files only (per `cq-markdownlint-fix-target-specific-paths` — no repo-wide glob).

### TR2: Cross-reference validity

All KB paths referenced from cost-model.md MUST resolve to existing files. Verify with a grep-style sweep before commit (per `2026-03-13-stale-cross-references-after-kb-restructuring` learning).

### TR3: Number traceability

Every number in cost-model.md MUST be derivable from `expenses.md` at the dated anchor. No free-floating figures. Reviewer can spot-check any row by opening the ledger at the cited date.

### TR4: No duplication of expense-ledger rows

cost-model.md MUST NOT reproduce the expenses.md recurring table verbatim. Categories and derived totals are allowed; row-by-row copy is not (would drift and violate the derived-view decision).

### TR5: [DEFERRED — was "AGENTS.md budget adherence"]

Moot with FR6 deferred. No AGENTS.md edit in this PR.

### TR6: Back-link commits atomic with cost-model.md

`operations/expenses.md` and `product/pricing-strategy.md` back-link edits are in the same PR as cost-model.md creation. Merging cost-model.md without back-links would leave the new doc invisible to dependents.

## Acceptance Criteria

1. `knowledge-base/finance/cost-model.md` exists with the FR1 frontmatter and all nine FR2 sections.
2. All numeric figures carry an `[expenses.md@YYYY-MM-DD]` anchor.
3. `product/roadmap.md` CFO narrative lines + Pricing Gate #4 status row + cost-model action item + `## Current State` section updated per FR4 (plan corrects the spec's L397 → actual L404; see plan's Research Reconciliation).
4. `operations/expenses.md` and `product/pricing-strategy.md` have back-links to cost-model.md per FR5.
5. Markdownlint clean on all changed files.
6. PR body includes "Partially addresses #1053" (not "Closes" — Gate #4 buildability remains with CPO/CTO). If the product team agrees the issue's full Task list is satisfied by this PR, operator may close manually post-merge.
7. No new sibling finance docs created.
8. No new hooks, cron, scheduled agents, or AGENTS.md rules introduced (FR6 deferred).
