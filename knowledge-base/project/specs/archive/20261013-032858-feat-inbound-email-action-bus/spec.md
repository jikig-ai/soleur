---
feature: inbound-email-action-bus
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 3012
status: superseded-in-part
decision: buy-for-dmarc-defer-the-bus
created: 2026-06-02
brainstorm: knowledge-base/project/brainstorms/2026-06-02-inbound-email-action-bus-brainstorm.md
---

# Spec: DMARC Failure Alerting (buy) + Inbound-Bus Validation

> **Supersession note (2026-06-11, Ref #5103):** `status: superseded-in-part`.
> The **buy path shipped** — the multi-`rua` `_dmarc` record is live on main
> (`apps/web-platform/infra/dns.tf:94`). The deferred "agent runs my inbox"
> slice is **no longer governed by this spec's Non-Goals**: the operator-dogfood
> read-only triage slice was built as
> `knowledge-base/project/specs/feat-operator-inbox-delegation/spec.md`
> (#5103; #4788 deferral explicitly overridden there — override recorded on
> #4788). The general customer-facing inbound-email platform capability remains
> deferred per #4788. This spec stays as the record of the DMARC buy decision.

## Problem Statement

DMARC aggregate reports for `soleur.ai` arrive at `dmarc-reports@soleur.ai` (Proton apex
inbox) and must be read by hand to learn whether mail is passing authentication. The operator
wants to be alerted only when a report shows a **failure**, without manual XML review. A
broader idea — an agent-native inbound-email action bus — was explored and **deferred** (see
brainstorm K2/K3).

## Goals

- **G1.** The operator receives failure-only DMARC visibility without manual XML parsing,
  at ~$0 infra cost.
- **G2.** No blind window: DMARC reports keep flowing to the existing destination throughout
  any DNS change.
- **G3.** Determine whether the general "agent runs my inbox" bus is a validated product bet
  before any engineering is committed to it.

## Non-Goals

- Building an in-house inbound-email ingestion pipeline (deferred — no validated second
  consumer; see brainstorm K2).
- Provisioning a `dmarc-reports@soleur.ai` mailbox in Proton (superseded by the buy path).
- Routing Sentry/GitHub notifications through email (they use native webhooks — brainstorm K5).
- Any LLM classification of, or autonomous action on, inbound PII (deferred with the bus).

## Functional Requirements

- **FR1.** Select a free DMARC aggregator (recommended: Postmark DMARC) and register
  `soleur.ai`. Operator-owned (digests are emailed to the operator).
- **FR2.** Add the aggregator's `rua` address as a **second** `mailto:` in the `_dmarc` TXT
  record, preserving the existing `dmarc-reports@soleur.ai` (multi-`rua`, comma-separated).
- **FR3.** Ship FR2 as a Terraform change to `apps/web-platform/infra/dns.tf` via PR; the
  plan diff MUST show zero change to the apex Proton MX/SPF and any DKIM records (TR1).
- **FR4.** Validate the inbound-bus concept via `business-validator`; record the verdict. If
  it passes, open a dedicated roadmap-placed issue + spec; if not, document the rejection.

## Technical Requirements

- **TR1. (Brand-critical)** The `_dmarc` edit lives on the same Terraform root as the Proton
  apex MX (`protonmail_mx_primary/secondary`) and apex SPF. `terraform plan` must be reviewed
  for a single-resource diff (the `cloudflare_record.dmarc` content string) and zero diff
  elsewhere before apply. A botched apply here is the single-user (founder) incident.
- **TR2.** The DMARC policy (`p=reject; pct=100`) is unchanged by FR2 — only `rua` is extended.
- **TR3.** No new Supabase tables, routes, or Inngest functions are introduced by the chosen
  (buy) path. (The deferred bus's technical decisions are captured in brainstorm K6 for any
  future build.)

## Acceptance Criteria

- AC1. A failure in a DMARC report surfaces to the operator without manual XML review.
- AC2. `dig +short TXT _dmarc.soleur.ai` shows both `rua` addresses after apply.
- AC3. The apply diff touched only the `_dmarc` record (TR1 evidence captured in the PR).
- AC4. #3012 is closed with the buy rationale, or re-scoped if the operator prefers a Proton
  mailbox after all.
- AC5. The `business-validator` verdict on the bus is recorded (pass → follow-up issue; fail →
  documented rejection).
