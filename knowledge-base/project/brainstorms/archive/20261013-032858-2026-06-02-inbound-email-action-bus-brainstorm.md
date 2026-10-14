---
date: 2026-06-02
topic: inbound-email-action-bus
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 3012
decision: buy-for-dmarc-defer-the-bus
---

# Brainstorm: Agent-Native Inbound-Email Action Bus

## What We're Building

**Decision: buy for DMARC now; validate the general bus separately before any build.**

The inciting ask was narrow — "only alert me when a DMARC aggregate report shows a
failure." During discussion it expanded into a general **inbound-email → classify →
agent-action bus** for signals that arrive only by email (DMARC reports, vendor/registrar
notices, abuse complaints, compliance/legal notices, customer replies, cold inbound).

The CPO + CLO + CTO triad converged on a reframe: the DMARC need is best solved by
**buying** (repoint the DMARC `rua` to a free hosted aggregator), and the general bus
should be **validated as its own product bet** with a named second consumer before it earns
a build. Both halves were endorsed by the operator.

### Two concrete next actions

1. **Buy the DMARC slice (≈1 hour, $0 infra).** Sign up for a free DMARC aggregator
   (recommended: Postmark DMARC — free weekly digest, failure visibility). Add its `rua`
   address as a **second** `rua` in the `_dmarc` TXT record (keep the existing
   `dmarc-reports@soleur.ai` so nothing breaks during cutover). Ship the multi-`rua`
   change via Terraform (`apps/web-platform/infra/dns.tf`). This resolves #3012 the cheap
   way — no Proton mailbox provisioning needed.
2. **Validate the bus separately (~30 min).** Route "agent runs my inbox" to
   `business-validator` as a distinct platform feature. If it validates, it earns its own
   roadmap row + spec — it does NOT ride in as DMARC infrastructure.

## Why This Approach

- **The infra cost is ~$0 for every option** at this volume — the real cost is engineering
  + legal *time*, which scales steeply: buy (~1hr) → narrow build (~days) → general bus
  (week+ plus a full GDPR triad). Spending days-to-weeks against **zero current traffic**
  is speculative generality (YAGNI).
- **The DMARC need is fully served by buying.** A free aggregator parses reports and emails
  failure-only digests with zero infra and zero GDPR exposure (DMARC reports carry no PII —
  only IPs and auth results).
- **The bus is the operator's real want, but it's unvalidated.** No second consumer exists
  today; building the classification/routing/per-class-action machinery now would design for
  traffic that has zero volume. It deserves validation + a roadmap row, not a side door.
- **The general bus carries brand-survival risk disproportionate to its proven value:**
  inbound free-text email is an attacker-controlled prompt-injection surface, and an LLM
  mis-classifying a DSAR (Art. 12, 1-month) or breach notice (Art. 33, 72h) would manufacture
  a compliance failure with an audit trail proving the agent saw it.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| K1 | **Buy, don't build, for DMARC.** Repoint `rua` to a free aggregator; close #3012 cheaply. | Solves the actual need in ~1hr at $0; in-house only wins with a 2nd consumer + agent-remediation actions a SaaS can't do. |
| K2 | **Defer the general inbound-email bus.** | Not validated, no 2nd consumer, week+ build + heavy GDPR load, brand-survival injection risk. All three leaders recommend deferral. |
| K3 | **Validate the bus as its own product bet** via `business-validator`, separate from DMARC. | "Agent runs my inbox" may be a strategic agent-native capability — but it must earn a roadmap row on its own merits, not enter as DMARC infra. |
| K4 | **Multi-`rua` cutover, not replace.** Add the aggregator address alongside the existing `dmarc-reports@soleur.ai`. | DMARC allows comma-separated `rua`; keeping both avoids a blind window during DNS propagation, and the apex `_dmarc`/MX edit is brand-critical (shared Terraform root with Proton MX). |
| K5 | **Sentry/GitHub stay on native webhooks, never email.** (Carried from pre-brainstorm dialogue.) | Email is a lossy, delayed, fragile transport when first-class webhooks/APIs exist. |
| K6 | **If the bus is ever built:** Resend Inbound front door (not a Cloudflare Worker), code-static handler registry (not runtime/table-driven), escalate-only for legal/abuse/customer classes, fail-loud on no-match, WORM received-at timestamp, hardened parser (zip-bomb/XXE), reporter allowlist, `gdpr-gate` at plan Phase 2.7 (mandatory). | Reuses the existing webhook→Inngest pattern + already-wired vendor (lowest blast radius); ADR-034/035 already chose code-static registries; CLO statutory-clock + injection guardrails. Captured so a future build inherits the decisions. |

## Cost Summary (operator-requested)

| Option | Infra $/mo | Time cost | GDPR load | Brand risk |
|---|---|---|---|---|
| **Buy (hosted aggregator)** | $0 (Postmark DMARC free; $14/mo/domain optional dashboard) | ~1 hour (repoint `rua`) | None (no PII) | None |
| Build narrow DMARC slice | $0 (Resend Inbound incl. free tier; Inngest self-hosted; Supabase rows trivial; CF Email Routing free) | ~Days (DNS cutover + hardened parser + alerting) | Light (parse-and-discard, infra-class) | DNS cutover + parser |
| Build general bus | $0 | Week+ + full GDPR triad | Heavy (new Art. 30 PA, DPIA, per-class LIA) | High (injection, statutory clock) |

Source pricing (fetched 2026-06-02): Resend Inbound included on all plans incl. free (3k emails/mo, no inbound-specific fee); Cloudflare Email Routing free on all plans, Email Workers on standard Workers free tier; Postmark DMARC free weekly digest, $14/mo/domain premium dashboard.

## Bus Validation Verdict (business-validator, 2026-06-02)

**FAIL as a distinct platform capability now; CONDITIONAL PASS for a narrow deferred slice
(read-only inbound notice triage) once a named second consumer exists.**

- Zero customer-demand signal: the validated beachhead (non-technical solo founders) never
  raised email triage in interviews. The capability profile matches the *operator's* own
  inbox (registrars, abuse, DMARC, legal), not a customer's — the "build for ourselves and
  call it a platform capability" trap.
- Hard design cap (not just a low score): inbound free-text email is a prompt-injection
  surface and the platform's injection defense (#4671) is itself an unsolved Post-MVP bet;
  an LLM can never be system-of-record for a statutory clock (DSAR Art.12 / breach Art.33).
- Even the narrow operator need is better served by a forward-to-human-inbox rule than an
  LLM classifier (near-zero cost/risk).
- **Three conditions, all required, to flip FAIL → CONDITIONAL PASS:** (1) a named second
  consumer from the #1439 founder-recruitment cohort asks for an email-only customer-facing
  action; (2) scope = one concrete action surfaced into the existing conversation inbox
  (3.3 / #1690), not a general bus; (3) statutory-class mail never reaches the LLM act path.

**Outcome:** Do not open a roadmap row. Log as a Post-MVP bet adjacent to CP1/CP4; re-validate
after the #1439 cohort, gated on the three conditions.

## Open Questions

1. Which free aggregator? (Recommended: Postmark DMARC. Alternatives: dmarcian, URIports,
   Valimail — all have free tiers.) Operator chose to proceed with Postmark DMARC; signup is
   operator-owned (digests are emailed to the operator).
2. (Deferred to any future build) parse-and-discard vs. retain raw DMARC reports — CLO prefers
   store only the failure delta.

## Domain Assessments

**Assessed:** Product, Legal, Engineering (CPO + CLO + CTO triad — mandatory under USER_BRAND_CRITICAL)

### Product (CPO)

**Summary:** Scope inflation from a one-line ops ask into a platform primitive. Ship the
DMARC slice only; for DMARC alone, *buy* (free aggregator). The bus is the real want but is
unvalidated with no second consumer — route it to `business-validator` as a distinct feature,
don't let it ride in as DMARC infra. Autonomy must be per-class and start at zero
(propose-and-approve default; escalate-only for high-stakes classes).

### Legal (CLO)

**Summary:** DMARC alone = no PII, negligible exposure. The general bus = a **new Article 30
processing activity + likely DPIA (Art. 35)**, because an LLM would classify uncontrolled
inbound PII from involuntary senders (special-category data will arrive). Brand-survival core:
a DSAR (Art. 12, 1-month) or breach notice (Art. 33, 72h) arriving by email and mis-classified
manufactures a compliance failure. Requires fail-loud, statutory-keyword fast-path, WORM
received-at timestamp, per-class lawful basis, reconcile with DSAR self-serve (#3637), and
`gdpr-gate` at plan Phase 2.7 (mandatory) — all only if the bus is built.

### Engineering (CTO)

**Summary:** Pattern fits cleanly (3rd webhook→Inngest ingress; dedup mig 052, scope-grants,
`action_sends` all exist). But the real first deliverable is a **brand-critical DNS edit**
(`rua`/`_dmarc` on the same Terraform root as Proton MX). DMARC doesn't fit the
founder-attributed scope-grant model (it's an infra signal). Dominant risk is **silent
ingestion failure**, not over-action. If built: Resend Inbound front door, code-static
registry, hardened parser (zip-bomb/XXE), reporter allowlist, escalate no-match to
Sentry/Better Stack. Recommends an ADR (3rd ingress, alongside ADR-036).
