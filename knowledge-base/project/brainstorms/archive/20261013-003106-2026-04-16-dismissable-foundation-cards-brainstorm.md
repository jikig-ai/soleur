---
title: Dismissable Foundation Cards — Progressive Task Surfacing
date: 2026-04-16
status: accepted
participants: founder, cpo
---

# Dismissable Foundation Cards

## What We're Building

The Command Center foundation cards (Vision, Brand Identity, Business Validation, Legal Foundations) currently stay visible with a green checkmark until ALL 4 are complete, then the entire section is replaced with static suggested prompts. This creates dead space — a founder who completes Vision still sees 3 incomplete cards without guidance on what else they could be doing.

We're adding **progressive task surfacing**: completed foundation cards auto-collapse into compact chips, and the freed grid slots fill with KB-gap-aware operational tasks. The card grid always shows the founder's most relevant next actions.

## Why This Approach

- **Auto-replace over manual dismiss** — Less friction. No button to click. The grid evolves as the founder progresses.
- **KB-gap-aware tasks over static prompts** — Each "next task" maps to a KB file path. If the file already exists (with sufficient content), that task is skipped. This reuses the existing `kbFiles.has(path) && size >= FOUNDATION_MIN_CONTENT_BYTES` pattern from foundation cards.
- **Curated list over AI-generated** — A predetermined list of ~6 operational tasks, ordered by startup progression. Simple to implement, predictable behavior, and aligned with the L2 (MVP) UX level. Dynamic AI-generated recommendations deferred to L4 North Star.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Dismiss mechanism | Auto-replace (no manual dismiss) | Less friction, grid always shows relevant next actions |
| Replacement source | Curated list of KB-gap-aware tasks | Simple, predictable, reuses existing KB state pattern |
| Completed card treatment | Compact chips above active grid | Minimal space, still visible as progress indicator |
| Task list | 6 operational tasks (see below) | Covers typical post-foundation startup needs |
| State storage | None (derived from KB tree) | No database or localStorage needed — purely derived from file existence |

## Operational Tasks (Post-Foundations)

These fill the grid after foundation cards are completed, ordered by priority:

1. **Set pricing strategy** — `product/pricing-strategy.md` — Talk to CMO
2. **Create competitive analysis** — `product/competitive-analysis.md` — Talk to CPO
3. **Plan marketing launch** — `marketing/launch-plan.md` — Talk to CMO
4. **Define hiring plan** — `operations/hiring-plan.md` — Talk to COO
5. **Build distribution strategy** — `marketing/distribution-strategy.md` — Talk to CMO
6. **Set up financial projections** — `finance/financial-projections.md` — Talk to CFO

Each task follows the same interface as foundation cards: `{ id, title, leaderId, kbPath, promptText, done }`.

## Visual Behavior

```text
State 1: No foundations complete
FOUNDATIONS
[Vision] [Brand Identity] [Business Validation] [Legal Foundations]

State 2: Vision complete
FOUNDATIONS
✅ Vision

[Brand Identity] [Business Validation] [Legal Foundations] [Set pricing strategy]

State 3: Vision + Brand complete
FOUNDATIONS
✅ Vision  ✅ Brand Identity

[Business Validation] [Legal Foundations] [Set pricing strategy] [Competitive analysis]

State 4: All foundations complete
FOUNDATIONS
✅ Vision  ✅ Brand Identity  ✅ Business Validation  ✅ Legal Foundations

UP NEXT
[Set pricing strategy] [Competitive analysis] [Plan marketing launch] [Define hiring plan]

State 5: All tasks complete
Section hidden entirely (current behavior preserved)
```

## Open Questions

- Should operational tasks show a different visual treatment than foundation cards (e.g., different header label like "UP NEXT")?
- Should the compact chips link to the KB file (like completed cards do today)?
- What happens when all 6 operational tasks are also complete? Show the existing `SUGGESTED_PROMPTS` or hide the section?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** The feature is well-scoped for L2 MVP. KB-gap-aware tasks are preferred over static prompts — they align with the CaaS thesis that agents know what the founder needs. No new infrastructure required; extends the existing `FoundationCards` pattern. Recommended deferring AI-generated dynamic recommendations to L4 North Star. Flagged that the roadmap Current State section is stale (3 weeks behind) and needs syncing.
