---
title: "Legible self-improvement changelog — dogfood-first (#6039)"
date: 2026-07-06
issue: "#6039"
parent: "#6037"
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Legible Self-Improvement Changelog — Brainstorm

## What We're Building

A **platform-framed "What got smarter this week" section added to the existing
`operator-digest` skill** — surfacing Soleur's *completed* self-improvement
activity (merged `self-healing/auto-*` promotion PRs + retired rules) in plain
language, for the **operator (Jean) first** as a dogfood.

The founder-facing in-product changelog originally described in #6039 is
**deferred** behind a sharpened trigger. This brainstorm re-scoped #6039 from
"ship a founder-facing changelog now" to "dogfood the honest signal on the
operator first, then graduate to a founder surface once there is a real
audience and real data."

## Why This Approach

Three facts, verified live during this brainstorm, drove the re-scope:

1. **Zero data to show.** `promotion-log.md` has **0 data rows** and **0
   `self-healing/auto-*` PRs have ever been opened** (verified via
   `gh pr list --search "head:self-healing/auto-" --state all`). The compound-
   promote loop has promoted nothing to date. A "3 mistakes fixed this week"
   changelog would render "0 fixed" every week — actively eroding the trust it
   exists to build.
2. **Zero external audience.** Roadmap Phase 4 (Validate + Scale) is in
   progress but **beta users = 0**. A founder-facing surface has no one to read
   it yet.
3. **Improvement is global, not per-tenant.** `cron-compound-promote` edits the
   *shared* harness (`AGENTS.core.md`, plugin `SKILL.md`), never per-workspace
   data. "**Your** workspace got smarter" is a misleading per-tenant claim
   (CLO + CPO + CMO all flagged it).

Dogfooding inside `operator-digest` is the cheapest honest move: it reuses an
existing weekly plain-language digest, validates the framing and the real
signal volume on the operator before any external exposure, and defers the
build cost of a founder UI until the underlying loop is actually producing
promotions worth showing.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Host: extend `operator-digest`**, not a new founder surface | Reuses weekly digest infra + 4-section structure; operator audience is the honest near-term reader. CTO's fork-`cron-weekly-release-digest` option is deferred with the founder surface. |
| D2 | **Content: completed improvements only** — merged `self-healing/auto-*` PRs (resolved via `promotion-log.md` cluster-hash) + retired rules | Maps "N mistakes fixed" to real, substantiable outcomes (CLO substantiation). Rejected: folding in rule-metrics `prevented_errors` / weakness patterns as "smarter" (mixes *found* with *fixed* — overclaim risk). |
| D3 | **Honest empty state** — deterministic "Nothing was promoted to the shared harness this week" | 0 promotions is the current reality; empty weeks are the common case (WEEK_CAP_DEFAULT=2). Must follow operator-digest's read-failure-≠-quiet-week rule: a failed `gh` read renders ⚠️, never "quiet week". |
| D4 | **Framing: platform-level, never "your workspace"** | "Soleur got sharper" / "your agents learned N things" / "shipped to the shared brain every workspace runs on". Attribute to the product/agents, not the user's tenant (CLO deceptive-implication; CMO honest felt-benefit). |
| D5 | **Data-minimization**: generate from sanitized promotion-log / rule artifacts, not raw logs | Shared-log sourcing risks leaking incident detail; artifacts are already sanitized (GDPR Art. 5(1)(c) minimization). Architectural constraint, not copy-review afterthought. |
| D6 | **Fallback rendering is a product surface** — test against real promotion-log shape | 2026-06-11 digest-launch-quality learning: a fallback posting unacceptable content is worse than none. Content-quality verification, not just "post exists + Sentry ok". |
| D7 | **Substantiation trail** — each "N fixed" links to its merged PR | FTC/UCPD substantiation; promotion-log cluster-hash → PR lookup already provides the trail. |
| D8 | **Defer founder-facing surface** (in-product card + email) behind trigger: **≥1 beta user AND ≥N accumulated real promotions** | Write-mostly avoidance (2026-05-12 lifecycle-prereq learning). Filed as follow-up issue. |
| Visual design | **N/A — no UI surface in this scope** | The digest is plain markdown prose posted to a GitHub issue (private repo). Phase 3.55 trigger boundary = no page/component/banner/email-template. The *deferred* founder card + email WILL require wireframes when built (noted on the follow-up issue). |

## Open Questions

- **Threshold N for the deferred trigger** (D8): how many accumulated real
  promotions justify graduating to a founder surface? Deferred to the follow-up
  issue — best decided from dogfood evidence (e.g. "after 4 weeks each showing
  ≥2 real promotions").
- **Cadence of the operator section**: inherits operator-digest's weekly
  window. Revisit only if empty weeks dominate for a long stretch (may signal
  the promotion loop itself needs attention — a separate concern from surfacing).

## User-Brand Impact

- **Artifact:** the "What got smarter this week" section rendered into the
  operator's weekly digest.
- **Vector:** a self-improvement claim that overstates what actually improved
  (per-tenant framing of a global change, or "N fixed" not backed by a merged
  PR) — a trust/brand-integrity breach.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(Operations, Sales, Finance, Support not relevant to this content/skill change.)

### Product (CPO)

**Summary:** Defer the founder-facing surface with a sharper trigger; dogfood a
shared-truth "platform got smarter" section inside `operator-digest` now.
0 beta users + ~2/wk cap (0 so far) = write-mostly risk; per-tenant framing
misrepresents the moat and must not ship.

### Legal (CLO)

**Summary:** Permitted with wording guardrails. "Your workspace got smarter" is
a misleading deceptive-implication (FTC net-impression / EU UCPD Art. 6) since
improvement is global, not per-tenant — reframe to product-level. Enforce
data-minimization on the generation source (sanitized artifacts, not raw logs)
and a substantiation link per metric.

### Engineering (CTO)

**Summary:** Data source is global-only (merged `self-healing/auto` PRs +
rule-metrics + retired rules); no per-tenant signal exists. For the eventual
founder surface, fork `cron-weekly-release-digest.ts` (highest infra reuse) —
but no new web page for v1. Empty-week is the common case; count only *merged*
PRs. Suggested an ADR for delivery-surface + tenant attribution when the
founder surface is built.

### Marketing (CMO)

**Summary:** Never "your workspace" — use "Soleur / your agents got sharper" /
"shared brain". In-product weekly card + monthly (not weekly) email for the
eventual founder surface; suppress empty weeks. Build engine early and pre-seed
so onboarding founders see momentum — tempered here by the 0-promotions reality
(nothing to pre-seed yet), which is why the operator dogfood comes first.

## Deferred Items (→ tracking issue)

- **Founder-facing self-improvement changelog** (in-product weekly card +
  monthly email roll-up), platform-framed, forking `cron-weekly-release-digest.ts`.
  Trigger: ≥1 beta user AND ≥N accumulated real promotions. Requires Pencil
  wireframes (UI surface) + an ADR for delivery-surface & tenant attribution.
