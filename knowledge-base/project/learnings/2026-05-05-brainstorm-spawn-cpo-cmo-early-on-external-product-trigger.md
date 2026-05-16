# Learning: Spawn CPO + CMO early when a brainstorm is triggered by external-product comparison

## Problem

A brainstorm started as "review Augment Cosmos and investigate what to borrow to make Soleur better." The user then framed the architectural direction as "pivot to server-side agentic runtime, Cosmos competitor, target solo founder." The brainstorm skill spawned 5 domain leaders in Phase 0.5 (CPO + CTO + CMO + CLO + COO) only after the user's framing had already committed the brainstorm to a "Cosmos-class platform" direction.

CPO and CMO independently surfaced that **the user's framing was wrong on two axes:**

1. It wasn't a pivot — the existing roadmap, brand guide, and Phase 1.10/1.11 already described this work. Calling it a pivot created urgency theater.
2. It shouldn't position vs Cosmos — Cosmos targets engineering teams; Soleur targets one-person companies. Real comp is Polsia, Lindy, Notion AI 3.3. Direct positioning vs Cosmos would make Soleur read as "Cosmos-lite" in a category Augment will outspend ~50:1.

CTO additionally discovered the substrate already largely existed (`apps/web-platform/server/agent-runner.ts`) — the "architectural pivot" was actually alignment + Inngest layer + RLS hardening. Total scope reduced significantly.

The framing was inherited from the comparison itself: a Cosmos blog post talks about "OS for agentic SDLC," so the brainstorm output adopted that frame uncritically. The fact that CPO + CMO challenged it only because they were spawned in parallel with everyone else means: had they been spawned only based on apparent relevance ("this is an architectural decision, spawn CTO"), the framing would have shipped unchallenged.

## Solution

**When a brainstorm's feature description includes an external-product URL or names an external product as a competitive trigger, treat CPO and CMO as default-relevant in Phase 0.5 — do not require a domain-relevance assessment to clear the bar.**

The reason: external-product comparisons import framing baked in by the comparison source. Architecture, UX, target-user, and positioning decisions inherit assumptions from the comparison page. CPO and CMO are the leaders whose first job is to challenge those assumptions:

- CPO challenges target user, MVP scope, validation status, trust model.
- CMO challenges positioning, competitive frame, naming, channel fit.

Spawning them only when the brainstorm topic appears product- or marketing-shaped (per the standard relevance assessment) misses external-product brainstorms because the *topic* looks architectural.

**Concrete fix:** in `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.5 (Domain Leader Assessment), add a default-on rule: if Phase 1.0 (External Platform Verification) ran or the feature description contains a URL, spawn CPO + CMO regardless of the domain-relevance assessment.

## Key Insight

**Architecture-first risks designing the wrong product correctly.**

When a brainstorm spawns CTO before CPO + CMO have validated the framing, the CTO produces a detailed architectural answer to a question the founder shouldn't have been asking. The CTO's work is then expensive to undo — engineers want to defend the architecture they spent context designing.

The cure is cheap: spawn CPO + CMO in parallel with CTO from the start, accept that some brainstorms will get redundant assessments, and trust that the parallelism pays for itself the first time a leader catches a wrong frame.

## Session Errors

- **Initial framing error.** I described Soleur as "a Claude Code plugin" in my first comparison, missing `apps/web-platform/`. **Recovery:** user corrected; reframed comparison. **Prevention:** read project structure (`apps/`, `README.md`, `roadmap.md`) before framing competitive comparisons. Don't rely on AGENTS.md alone for product context.
- **Stale milestone selection.** Created GH issue #3244 with milestone `Post-MVP / Later` without reading `roadmap.md` first. CPO's response showed Phase 3 was correct. **Recovery:** re-milestoned via `gh issue edit`. **Prevention:** read `roadmap.md` Current State and milestone table before issue creation, not after.
- **Brainstorm skill prescribes commit-before-compound; AGENTS.md rule `wg-before-every-commit-run-compound-skill` requires compound-before-commit.** The brainstorm Phase 3.6 commits artifacts before Phase 4 invokes compound. This violates the rule but follows the skill. **Recovery:** acknowledged in deviation analysis; flagged for skill/rule reconciliation. **Prevention:** file an issue to reconcile the brainstorm skill's commit ordering with the workflow gate, OR carve out a brainstorm-artifact-commits exception in the rule wording.

## Tags

category: workflow-issues
module: plugins/soleur/skills/brainstorm
related:
  - 2026-02-13-brainstorm-domain-routing-pattern.md
  - workflow-issues/domain-leader-false-status-assertions-20260323.md
trigger: external-product-comparison-brainstorm
