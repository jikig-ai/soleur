---
title: Beta-CRM de-identified insight rollups — boundary note
type: reference
date: 2026-07-07
issue: 6165
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
---

# Beta-CRM insight rollups — where pseudonymised aggregate signal goes

The owner-private beta-CRM store (`beta_contacts` / `interview_notes` /
`beta_contact_stage_transitions`, migration 126, ADR-102) holds **third-party
PII in the database only** — it is **never** committed to git (a git-committed
copy would be an Art. 17 erasure impossibility and secret-scan-invisible).

The **de-identified insight layer** (ADR-102 §9, FR6) is the git-safe complement:
`cro`/`cpo` may write **aggregate, pseudonymised** signal here — trends across
conversations with **no identifiable person** — where the domain agents already
synthesize. This file is the canonical boundary note for **both** this directory
(`knowledge-base/sales/`) and `knowledge-base/product/` (see the sibling pointer
`knowledge-base/product/beta-crm-insight-rollups.md`).

## The boundary (hard rule)

**Safe to write here (git):** aggregate, no-identifiable-person signal.
- Stage-distribution and velocity trends ("N contacts advanced past `qualified`
  this month"; median days `contacted` → `evaluating`).
- Recurring objection / feature-request **themes** stated abstractly ("several
  prospects raised onboarding friction"), with **no** attribution to a named
  person, company, or verbatim quote that could re-identify.
- Counts, rates, and directional pipeline signal by `amount_basis`.

**NEVER write here (DB-only):** any raw PII or re-identifiable content.
- No `name`, `company`, `role`, `source`, contact ids, or verbatim `body` text.
- No single-subject rollups where the group is small enough to re-identify
  (k-anonymity: do not publish a "theme" derived from one prospect).
- No copy-paste of a conversation note. Raw records stay in the DB, reachable
  only via the owner-scoped `crm_*` agent tools.

## Status

The rollup **generation** skill is **deferred** (a follow-up under Beta-CRM epic
#6177). This note establishes the boundary now so that any agent writing here —
today by hand, later by the skill — knows the git/DB line. The disclosure of
this exact boundary is recorded in the Article 30 register (PA-30) and the LIA.
