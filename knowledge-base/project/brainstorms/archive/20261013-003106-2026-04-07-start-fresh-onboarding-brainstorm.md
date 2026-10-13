# Start Fresh Onboarding — Brainstorm

**Date:** 2026-04-07
**Status:** Decided
**Approach:** KB-derived state, full connected flow

## What We're Building

A guided first-run experience for the Soleur web platform that captures a founder's startup idea on their first dashboard interaction and surfaces 4 contextual foundation cards that help them bootstrap their company's core documents.

### The Flow

1. Founder completes "Start Fresh" (existing connect-repo wizard — no changes needed)
2. Dashboard renders a **first-run state**: welcome message + focused prompt asking "What are you building?"
3. Founder's first chat message describes their vision → system writes `vision.md` to the KB
4. Dashboard transitions to **foundations state**: 4 smart prompt cards appear alongside the chat input
5. Cards detect completion by checking KB file existence (e.g., `brand-guide.md` exists → card complete)
6. Once all 4 foundation cards are complete → dashboard transitions to **full Command Center** (general-purpose prompts + all 8 leaders)

### Three Dashboard States

| State | Trigger | What Shows |
|-------|---------|------------|
| `first-run` | No `vision.md` in KB | Welcome message + "What are you building?" prompt. No cards. No leader strip. |
| `foundations` | `vision.md` exists, but brand/validation/legal incomplete | Chat input + 4 foundation cards (smart prompts) + leader strip |
| `command-center` | All 4 foundation KB files exist | Full Command Center (existing design) with general prompts + 8 leaders |

### The 4 Foundation Cards

| Card | Domain Leader | KB File Check | Smart Prompt |
|------|--------------|---------------|--------------|
| Vision | (auto) | `knowledge-base/overview/vision.md` | N/A — auto-completed from first message |
| Brand Identity | CMO | `knowledge-base/marketing/brand-guide.md` | "Help me define the brand identity for {project idea}" |
| Business Validation | CPO | `knowledge-base/product/business-validation.md` | "Help me validate the business model for {project idea}" |
| Legal Foundations | CLO | `knowledge-base/legal/privacy-policy.md` | "Help me set up legal foundations for {project idea}" |

Cards are **smart prompts** — clicking one pre-fills the chat input with a contextual prompt that includes the founder's idea. Tag-and-route handles routing to the correct domain leader. No strict sequence — founders pick their own order.

## Why This Approach

1. **Works WITH tag-and-route, not against it.** Cards pre-fill the chat input; tag-and-route handles routing. No parallel interaction model.
2. **KB-derived state avoids schema changes.** Card completion is determined by checking if specific files exist in the knowledge base via API. No new DB tables or columns needed.
3. **Keeps the onboarding wizard lean.** The idea capture happens on the dashboard, not as an extra step in connect-repo. Fewer steps before the founder sees the dashboard.
4. **Demonstrates the CaaS thesis in the first session.** A founder who completes all 4 cards has a brand guide, business validation, and legal docs — tangible proof that an AI organization produces real artifacts.
5. **Transitions to existing UI.** The Command Center design is already built on `feat-kb-no-project-empty-state`. This feature adds a guided on-ramp to it, not a replacement.

## Key Decisions

| # | Decision | Alternatives Considered | Rationale |
|---|----------|------------------------|-----------|
| 1 | Idea capture on dashboard (first message), not in onboarding wizard | Extra step after project naming; During setup animation | Keeps signup flow lean. Dashboard becomes the first meaningful interaction. No dead time. |
| 2 | Smart prompt cards (pre-fill chat input) | Sequential wizard with locked steps; Passive status-only indicators | Works with tag-and-route architecture. Founders choose their own order. Less prescriptive, more empowering. |
| 3 | Core 4 cards only (Vision, Brand, Validation, Legal) | Extended 6 (add Ops + Pricing); Dynamic from KB scan | Tight scope. Covers essentials a day-1 startup needs. Dynamic scan is a future enhancement. |
| 4 | KB file existence drives card state | New DB schema for progress tracking; Hybrid (DB + KB) | Simplest approach. No migrations. Leans on existing KB infrastructure. If a file exists, the work is done. |
| 5 | Cards transition to Command Center when complete | Cards stay permanently as org status dashboard | First steps are temporary scaffolding. The Command Center is the long-term working surface. Clean transition avoids permanent visual debt. |
| 6 | No gamification (no badges, points, streaks) | Progress bars; Achievement badges; Streak tracking | Brand is "Tesla and SpaceX: audacious, mission-driven." Gamification patterns clash with the positioning. Status cards showing done/not-done are informative, not gamified. |

## Open Questions

| # | Question | Impact | Owner |
|---|----------|--------|-------|
| 1 | What counts as "done" for each card? File existence only, or file content validation? | A nearly-empty `brand-guide.md` would falsely show completion. | Engineering |
| 2 | How does the first message get processed? Does it go through a specific agent or the general router? | Determines whether vision.md is written by the router, a specific leader, or a side-effect hook. | Engineering |
| 3 | Must merge `feat-kb-no-project-empty-state` first — that branch has the Command Center, connect-repo flow, KB viewer, and responsive layout. | HIGH collision risk if both branches modify dashboard independently. | Engineering |
| 4 | Copy for the first-run prompt needs brand-voice precision. "What are you building?" vs something more ambitious. | First impression sets the tone for the entire product relationship. | CMO / Copywriter |
| 5 | How does this work for "Connect Existing Project" users? Their KB may already have some files. | Foundations cards should still work — just some may already be complete. | Product |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** The empty dashboard is a real problem and the first-5-minutes audit rated it FAIL. However, building a full guided experience before observing real founders (Phase 4) risks designing based on assumptions. Recommended Option B (KB-aware checklist) over gamification. Gamification clashes with the "Tesla/SpaceX" brand positioning. The feature aligns with the validation directive to focus on the onboarding surface. Tag-and-route (#1059) is shipped — any card-based experience must work within that architecture, not reintroduce the department-office model.

### Marketing (CMO)

**Summary:** The first 60 seconds are the highest-leverage activation moment. Capturing the startup idea is a commitment device (Cialdini's commitment/consistency principle) — once founders articulate their vision inside Soleur, they're psychologically invested. The prompt copy is high-stakes and needs dedicated copywriter attention. Framing should be "executive briefing readiness," not "tutorial completion." Recommended delegating to conversion-optimizer and ux-design-lead for layout review. The CaaS thesis becomes tangible when the onboarding produces real artifacts ("Your CMO drafted a brand brief. Your CLO flagged a compliance gap.").

### Engineering (CTO)

**Summary:** Prior art exists: `ChooseState`, `CreateProjectState`, `useOnboarding` hook, `WelcomeCard`. The `feat-kb-no-project-empty-state` branch is substantially ahead of main and must be merged first — HIGH collision risk. Three technical options ranging from guided prompts (days) to full orchestration (weeks). No multi-step workflow primitive exists in the web platform — the approach must work within single-turn chat. Recommended starting with guided prompts (Approach A) to deliver value without architecture risk. Architecture Decision Record recommended for onboarding progress model if scope grows beyond Option A.
