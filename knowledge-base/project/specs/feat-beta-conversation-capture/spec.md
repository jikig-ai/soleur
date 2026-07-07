---
title: Beta-Tester Conversation Capture
date: 2026-07-07
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 6165
pr: 6160
brainstorm: knowledge-base/project/brainstorms/2026-07-07-beta-conversation-capture-brainstorm.md
validation: knowledge-base/product/validation/2026-07-07-agent-operated-crm-validation.md
domains_assessed: [product, legal, engineering, sales, operations, finance]
---

# Spec: Beta-Tester Conversation Capture

## Problem Statement

The operator is onboarding Soleur's first beta testers and has had many conversations with people and teams, carrying both **sales** signal (interest, objections, deal potential) and **product** signal (pain points, feature requests). There is no private, structured home for these conversations. The capture must (a) never leak — it holds third-party PII shared under implied confidence; (b) be reachable by agents (`cro`/`cpo`) so records aren't dead documents; and (c) be a **reusable per-tenant capability** future Soleur users inherit, complete with the compliance scaffolding that entails.

An embryonic precedent exists (`knowledge-base/support/community/user-conversations/2026-03-12-ex-colleague-bss-ai.md`) — one anonymized markdown record blending both lenses, but stored where neither `cro` nor `cpo` looks and with no PII boundary.

## Goals

- G1. A private, per-tenant store for beta-tester/prospect conversations, one **dual-lens** record per conversation (sales + product facets).
- G2. **Operator-private** by default (owner-only RLS).
- G3. Agent-mediated: `cro`/`cpo` can read AND write records via an agent-reachable path.
- G4. Pipeline fields (`amount`, `stage`, timestamps, …) that feed `pipeline-analyst` → `revenue-analyst`/`cfo` forecasting.
- G5. Compliance floor shipped WITH the feature: Article 30 processing record, retention policy, DSAR/erasure wiring.
- G6. Tenant-generic (no Soleur-specific stages/fields hardcoded) so it productizes.

## Non-Goals (this phase)

- N1. **No separate CRM UI.** Any visual surface is deferred and, when built, lives inside the Soleur UI over the store's API.
- N2. **No BYO-CRM / external-CRM connect** (native MCP integration) — deferred.
- N3. **No tester-visible records** (external-person auth / agent-user parity) — deferred; operator-private only.
- N4. **No unified-API vendor** (Merge/Apideck) and **no self-hosted OSS CRM** (Twenty/Corteza) — rejected in the brainstorm's Sourcing Canvas.
- N5. **No forecasting model** — capture the fields; forecasting is meaningless at 0 deals (CFO).

## Functional Requirements

- FR1. **Contact/opportunity record** with fields: `name`, `company`, `role`, `source`, `stage`, `next_action`, `next_action_date`, `last_contact`, `amount`, `currency`, `expected_close_date`, `owner`.
- FR2. **Conversation/interview notes** attached to a contact: dated free-text body + per-note `lens` tag(s) in `{sales, product}`.
- FR3. **Stage-transition timestamps** (`stage_entered_at` per stage) captured on every stage change — not reconstructable retroactively.
- FR4. **Canonical, versioned stage→probability map** owned in one place (drives weighted pipeline; no per-deal free-text probability).
- FR5. Agent read/write path (MCP tool or `app/api` route) letting `cro`/`cpo` create a contact and append a note headlessly.
- FR6. **De-identified insight layer:** aggregate/pseudonymised rollups (no identifiable person) written to `knowledge-base/sales/` + `product/`, where agents already synthesize — safe to commit.
- FR7. Article 30 processing-record entry + a stated retention horizon + DSAR/erasure that deletes a contact and all related notes cleanly.

## Technical Requirements

- TR1. **Storage = per-tenant Supabase Postgres tables** (`beta_contacts`, `interview_notes` or similar), workspace-scoped, **owner-only RLS** modeled on the `conversations` `visibility='private'` pattern (migration 075). **No third-party PII in git.**
- TR2. Inherit existing DSAR/WORM/erasure machinery (`dsar_export_jobs`, WORM audit) — new tables join the existing erasure sweep.
- TR3. Currency stored raw + normalized to one reporting currency at a dated FX rate (resolve single-vs-multi currency open question at plan time).
- TR4. `/soleur:gdpr-gate` runs at plan Phase 2.7 and work Phase 2 exit (regulated third-party-PII surface — `hr-gdpr-gate-on-regulated-data-surfaces`).
- TR5. **Architecture decision (ADR)** capturing the storage-boundary + data-model choice and rejected alternatives (per `wg-architecture-decision-is-a-plan-deliverable`; the Sourcing Canvas table is the alternatives record).
- TR6. Observability: agent write path errors reachable from Sentry/Better Stack without SSH (`hr-observability-as-plan-quality-gate`).
- TR7. If `knowledge-base/` gains a new top-level dir, update `SANCTIONED_DIRS` in `kb-domain-allowlist-guard.sh` (sales/product already sanctioned — likely no change).

## Open Questions

See brainstorm §Open Questions (currency basis, beta-stage `amount` semantics, consent mechanism, retention horizon, record grain, owner-private vs workspace-shared).

## Domain Sign-offs (carry-forward)

Product (CPO), Legal (CLO), Engineering (CTO), Sales (CRO), Operations (COO), Finance (CFO) — see brainstorm §Domain Assessments. CLO gate: `/soleur:gdpr-gate` mandatory. CTO: recommend ADR + medium (days) complexity.
