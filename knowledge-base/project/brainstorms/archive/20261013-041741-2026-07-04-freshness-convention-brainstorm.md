---
last_updated: 2026-07-04
review_cadence: quarterly
convention: pai-freshness-v1
lane: cross-domain
brand_survival_threshold: single-user incident
tracks_issue: 5999
epic: 6003
---

# Freshness Convention — `last_reviewed` Integrity Gate (Brainstorm)

**Date:** 2026-07-04 · **Issue:** #5999 · **Epic:** #6003 (LifeOS→Soleur adaptations) · **PR:** #6017
**Adapted from:** LifeOS `pai-freshness-v1`.

## What We're Building

A **trustworthy `last_reviewed` semantic** for Soleur's always-loaded rule layer, so that "this rule was human-reviewed N days ago" is a signal an agent can rely on. Concretely, v1:

1. **Reviewed-integrity gate** — a negative commit/Edit gate that **blocks automated `last_reviewed` bumps** unless an explicit human-review marker is set for the session. (Precedent: `brand-hex-commit-gate.sh`, `follow-through-directive-gate.sh`, `cla-signed-author-gate.sh`, `prod-write-defer-gate.sh` — all with `.test.sh` siblings.) A shared bump helper writes `last_updated` freely; `last_reviewed` is gated.
2. **Fix the Phase 0.25 self-violation** — brainstorm `SKILL.md:121` currently auto-bumps *both* `last_updated` and `last_reviewed` on `roadmap.md` during roadmap reconcile. A reconcile is an automated write; it must bump `last_updated` **only**. (Without this, the existing signal reads "freshly reviewed" precisely when the roadmap is drifting.)
3. **Extend the existing convention to the always-loaded rule layer** — add `last_reviewed` + `review_cadence` to `AGENTS.md` and `AGENTS.core.md` (the only constitutional population the current convention doesn't cover). Teach `.claude/hooks/session-rules-loader.sh` to **strip leading frontmatter** before it concatenates the sidecars into context (today they're injected raw).
4. **Reuse the existing overdue consumer** — the `review-reminder.yml` workflow + Inngest crons (`cron-review-reminder.ts`, `cron-strategy-review.ts`, `cron-campaign-calendar.ts`) already scan `last_reviewed`/`review_cadence` and file GitHub issues when overdue. Point them at the newly-tagged rule-layer files; do **not** build a fourth parser.

## Why This Approach

The convention (`last_reviewed`+`review_cadence` on **40 files**) and its detection/surfacing (issue-filing crons) **already exist and work**. The literal LifeOS design (an A–F grade surfaced every session) would largely **duplicate** that working overdue-issue channel and add ambient noise the operator learns to ignore. The one thing genuinely missing — and the whole value — is the `last_updated`-vs-`last_reviewed` **integrity split**: nothing today stops an automated flow from bumping `last_reviewed`, and one of Soleur's own skills does exactly that. A grade computed off an unguarded `last_reviewed` is *false confidence* — worse than no signal, and precisely the stale-premise failure class this was meant to kill. So v1 invests entirely in making `last_reviewed` **mean what it says**, and rides the existing surfacing.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| v1 core | Reviewed-integrity gate (negative commit/Edit gate) | The hard, essential, missing piece; makes the semantic trustworthy. |
| Phase 0.25 fix | Reconcile bumps `last_updated` only | It's an automated write; bumping `last_reviewed` is the self-violation. Ships **with** v1. |
| File scope | `AGENTS.md` + `AGENTS.core.md` (rule layer); `constitution.md`/`roadmap.md` already covered | The only always-loaded population lacking the convention. |
| MEMORY.md | **Out of scope** | CC-local, write-forbidden (`no-memory-write.sh`, `hr-never-write-to-claude-code-memory`). |
| Loader | Strip leading frontmatter before injecting sidecars | Sidecars are concatenated raw; YAML would leak into context. |
| Consumer | Reuse `review-reminder.yml` + Inngest crons | Avoid the multi-parser drift the repo already fights (`cq-union-widening-grep`); gray-matter YAML-1.1 date-coercion scar exists. |
| Review-recording UX | Default: lightweight marker (commit trailer / flag), **no new skill** (CTO YAGNI: "no new agent or skill required"). Top open question for plan/ADR. | Avoid gold-plating a ContextCheckin skill in v1. |
| Surface | Stale-only (existing overdue-issue channel) | High-signal; an always-on green line is ignorable noise. |
| **CUT from v1** | A–F GPA aggregate · per-section markers · `derived_from`/`generator` inheritance · session-start grade line · statusline grade | Duplicative / no consumer / hides the actionable unit / wrong surface (statusline is user-global, not repo-shippable). |

## Open Questions (for plan / ADR)

1. **Review-recording mechanism (top question).** How does a human record "I reviewed AGENTS.core.md"? Passive commit-trailer / flag the gate checks (CTO-preferred, no new skill) vs. an active `/soleur:review-context` checkin skill (LifeOS ContextCheckin model, heavier). Default = passive; confirm at plan.
2. **Gate actor-detection.** The gate can't see "human vs generator" from the diff alone. Precedent gates key on a session marker / commit trailer — which marker, and how is it set only by a deliberate human review? (ADR-worthy.)
3. **Cron wiring.** Do the existing crons scan repo-root files (`AGENTS.md`) or only `knowledge-base/**`? If the latter, extend the scan glob — verify the gray-matter strict-date parser (`cron-strategy-review.ts`) handles the new files identically.
4. **`review_cadence` for rule files.** What cadence for `AGENTS.md`/`AGENTS.core.md` — monthly (hard rules change often) vs quarterly? Owner tag?

## Architecture Decision (plan deliverable)

Per CTO: capture an ADR for (a) reuse existing cron/convention vs new registry+parser, and (b) how `last_reviewed` write-integrity is enforced. Run `/soleur:architecture create` during plan.

## User-Brand Impact

- **Artifact:** the `last_reviewed` integrity gate + rule-layer freshness metadata + the Phase 0.25 reconcile fix.
- **Vector:** a false-fresh `last_reviewed` (automated bump slipping through) causes an agent to trust a silently-stale hard rule and make a wrong high-blast-radius decision — a single-user trust breach.
- **Threshold:** `single-user incident` (auto, per #5175).

## Domain Assessments

**Assessed:** Engineering (CTO). Legal/Product/others: not triggered — internal tooling, no user data, no external surface, no new user-facing capability.

### Engineering (CTO)

**Summary:** Endorses a small–medium v1 *only if* the integrity gate ships with the reviewed semantic ("a grade without the gate is actively harmful"). Corrected three premises: `constitution.md` lives at `knowledge-base/project/` and already carries the fields; MEMORY.md is write-forbidden; AGENTS sidecars are injected raw (loader must strip frontmatter). Load-bearing finding: the convention + detection already exist across 40 files with three live Inngest consumers — v1's job is the integrity split, not a new scanner. Flags the Phase 0.25 self-violation as HIGH and requires fixing it in v1. No capability gaps; no new agent/skill required.
