---
feature: operator-inbox-delegation
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 5103
status: draft
decision: overturn-deferral-build-narrow-read-only-triage
created: 2026-06-10
brainstorm: knowledge-base/project/brainstorms/2026-06-10-operator-inbox-delegation-brainstorm.md
closes: 5103
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Spec: Operator Inbox Delegation — Read-Only Email Triage

## Problem Statement

The operator personally reads and triages all inbound email to the company (vendor
notices, billing, quota warnings, legal/compliance mail) — low-leverage work that
contradicts Soleur's promise that the agent company runs operations. Mail sits unread
(2026-06-10 Better Stack quota warning) until the operator pastes it into a session.

This spec implements the narrow read-only triage slice chosen in the 2026-06-10
brainstorm, which **explicitly overturns** the 2026-06-02 deferral (#4788) on the
operator-dogfood framing (override recorded in the brainstorm; deferral conditions 2 and
3 are satisfied by design, condition 1 is operator-overridden).

## Infrastructure (IaC)

All Terraform-manageable infrastructure routes through the existing root:

- **DNS (Terraform):** any Resend Inbound records (inbound subdomain MX/TXT) are added to
  `apps/web-platform/infra/dns.tf` — additive-only diff, zero change to apex Proton
  MX/SPF/DKIM/`_dmarc` (TR1).
- **Sentry monitors (Terraform):** the dead-man heartbeat joins
  `apps/web-platform/infra/sentry/cron-monitors.tf` (FR7).
- **Secrets:** the Resend Inbound webhook signing secret lives in Doppler (TR5).
- **Genuinely non-IaC remainder (no API exists):** Proton Workspace exposes no public
  API or Terraform provider for mailbox-address creation or Sieve filter management —
  verified during brainstorm research (Proton requires Bridge even for IMAP; there is no
  management API). The two Proton-side steps (create the ops@ additional address; set the
  Sieve auto-forward rule) are therefore in-product Proton admin configuration, executed
  in-session via browser automation where possible per
  `hr-exhaust-all-automated-options-before`, and verified by AC1/AC3 end-to-end tests.

## Goals

- **G1.** Mail arriving at a dedicated company address is triaged by an agent and
  surfaced as decision-ready items in the existing conversation inbox, with a ping to the
  operator's notification channel.
- **G2.** Statutory-clock-bearing mail (DSAR, breach notice, service of process,
  regulator correspondence) reaches the operator deterministically — never gated on an
  LLM — with the clock stated.
- **G3.** No mailbox credential exists anywhere in the system; no autonomous send
  authority exists anywhere in this increment.
- **G4.** The legal posture ships with the build (Art. 30 PA row, LIA, DPIA screening
  memo, policy lockstep, Anthropic scope amendment).

## Non-Goals

- **Autonomous or draft-then-approve outbound replies** — deferred until #4672 (HITL
  approval queue) lands; must reuse the PR #4077 send-class invariants when built.
- **IMAP/JMAP polling or Proton Bridge** — rejected (Proton has no JMAP; Bridge requires
  a send-capable full-mailbox credential).
- **OAuth access to the operator's personal mailbox** — infeasible (no Proton OAuth) and
  legally rejected.
- **Paid shared-inbox vendors** (Front, Missive, Plain) — rejected pre-revenue.
- **A general customer-facing inbound-email platform capability** — remains deferred in
  #4788; this spec is operator dogfood only.
- **Raw email body retention** — parse-and-discard only.

## Functional Requirements

- **FR1.** `ops@soleur.ai` exists as an additional address on the existing Proton
  Workspace plan ($0; Proton-side step, see Infrastructure section). This address MUST
  NEVER be the recovery/login email for any vendor account (brainstorm K8,
  non-negotiable).
- **FR2.** ops@ mail reaches a Resend Inbound address (Proton-side Sieve auto-forward,
  see Infrastructure section); Resend Inbound webhook → Inngest is the third
  multi-source ingress (record via `/soleur:architecture` ADR alongside ADR-036).
  Inbound `Message-ID` deduplicates via the migration-052 `messages.source_ref`
  primitive.
- **FR3.** **Statutory fast-path (pre-LLM, deterministic, metadata-first):** sender/keyword
  rules detect DSAR / breach / service-of-process / regulator classes and escalate
  fail-loud to the operator BEFORE any LLM processing — and the subject/sender(+
  attachment-filename) check runs on webhook metadata BEFORE the body fetch, so a
  Resend fetch outage can degrade a statutory row but never drop it. **Ordering note
  (amended 2026-06-11):** metadata-first is load-bearing — the statutory check must
  never depend on the body fetch, which is why subject/sender stay in the
  `email/inbound.received` event payload (the Inngest event-store PII consequence is
  disclosed in Article 30 PA-27). Renders the statutory clock (calendar-month
  semantics per Art. 12(3)) and hard-links
  `knowledge-base/legal/recommended-tools.md#dsar-request` / `#breach-notice-triage`.
  Every message gets a WORM received-at timestamp sourced from the Resend event
  payload's receive time (never insert time). The LLM is never system-of-record for
  any deadline.
- **FR4.** Non-statutory mail is summarized by a read-only LLM step (no write tools, no
  repo access) after `sanitizePromptString`-parity sanitization of subject/body/sender
  (incl. `\x7f`, U+2028/U+2029). Output: summary, mail-class badge, sender, received-at.
- **FR5.** Triage output surfaces as items in the existing conversation inbox per the
  wireframes in `knowledge-base/product/design/inbox/operator-email-triage.pen`
  (email-triage row + read-only detail; statutory-escalation row pinned with clock +
  catalog link, per FR3) + a ping on the operator notification channel (transport decided at plan
  time: server-side Slack webhook vs existing web-push hierarchy — Open Question 1).
  GitHub issues are forbidden as a surface (third-party PII).
- **FR6.** **Parse-and-discard:** raw bodies are discarded after triage; persisted data =
  **summary, subject, sender, received-at, message-id** (plus the Resend email id,
  class/rule provenance, and lifecycle status fields) — **NOT full headers**: do not
  add a headers column (and do not "fix" this with a JSONB headers column at review
  time); the Proton mailbox local copy is the durable original, so the Sieve rule MUST
  forward-and-keep. The schema has no body column — parse-and-discard is structural,
  not policy. *(Amended 2026-06-11 per plan AC10 — wording aligned with migration 102.)*
- **FR9.** **Item lifecycle:** items carry **one-way** `new → acknowledged | archived`
  status (statutory: acknowledge unpins but the item stays visible with its clock —
  acknowledgment is workflow state, not legal resolution; standard: archive; no
  transition back to `new`, enforced in the DB by the `set_email_triage_status` RPC —
  a route-only matrix would leave `acknowledged → new` DB-legal). Status transitions
  are the only mutable fields under the WORM trigger. **Agent-write boundary:** status
  transitions are **UI-only in v1** — agents get read tools (`email_triage_list` /
  `email_triage_get`, auto-approve tier) but NO write/acknowledge tool. If a status
  write tool ever ships it MUST be `gated`-tier, and statutory acknowledge MUST never
  be auto-approve (cite #4671): the gate approval IS the human seeing the item — the
  entire signal the statutory pin protects; a prompt-injected agent auto-acknowledging
  a DSAR would silently unpin a statutory clock. *(Amended 2026-06-11 per plan AC10.)*
- **FR7.** Out-of-band liveness: dead-man heartbeat on the Inngest cron substrate +
  Sentry monitor with an independent freshness source; silent ingestion failure must page
  (a quiet mailbox is indistinguishable from a broken pipeline otherwise).
- **FR8.** Legal bundle ships in the same feature: new Art. 30 PA row (Anthropic as
  recipient, SCCs, 30-day Anthropic-side retention disclosed — Zero-Retention amendment
  deliberately NOT gating launch, brainstorm K6), one Art. 6(1)(f) LIA, DPIA screening
  memo, Privacy Policy + DPD + GDPR Policy lockstep, Anthropic vendor-DPA scope-cell
  amendment.

## Technical Requirements

- **TR1. (Brand-critical)** Any DNS additions for Resend Inbound live on the shared
  Terraform root (`apps/web-platform/infra/dns.tf`); `terraform plan` must show
  additive-only diff and zero change to apex Proton MX/SPF/DKIM and `_dmarc`.
- **TR2.** Handler registry is code-static (ADR-034/035 pattern), fail-loud on no-match
  → Sentry; hardened parser (zip-bomb/XXE) per 2026-06-02 K6.
- **TR3.** No raw email bodies or sender PII in observability sinks (pino, Sentry,
  Better Stack) — pseudonymize or strip-and-tag; otherwise sub-processor disclosures
  change (brainstorm K12).
- **TR4.** `/soleur:gdpr-gate` runs at plan Phase 2.7 (mandatory,
  `hr-gdpr-gate-on-regulated-data-surfaces`).
- **TR5.** Webhook signing-secret verification on the Resend Inbound route, matching the
  Stripe/GitHub ingress precedents; the signing secret is the entire credential surface
  and must be rotatable via Doppler.

## Companion Increments (separate PRs/issues, not this build)

- **C1.** Better Stack usage-poll cron (Telemetry API → operator alert) — prevents the
  inciting incident class natively. Productize candidate: `vendor-quota-watch`.
- **C2.** Progressive vendor-contact migration to ops@ (excluding recovery/login
  addresses per FR1).

## Acceptance Criteria

- **AC1.** A vendor email sent to ops@soleur.ai appears as a triage item in the
  conversation inbox with summary, class badge, sender, received-at — and the raw body is
  not persisted anywhere.
- **AC2.** A synthetic DSAR-keyword email reaches the operator escalation surface with
  the Art. 12 clock stated, with zero LLM involvement on its routing path (verifiable
  from the handler code path + tests).
- **AC3.** Halting the forwarding chain (e.g., disabling the Sieve rule in a test
  mailbox) triggers the dead-man alert within the freshness window. **Negative arm
  (restored 2026-06-11 per plan AC-P3):** a green check-in alone proves only the happy
  chain — the post-merge sequence includes a **one-time chaos check** (temporarily
  disable the Sieve rule, or fire the probe with a corrupted marker) confirming the
  missed/failed Sentry check-in actually raises the alert → founder email, then
  re-enable. The alert path itself must be proven, not assumed.
- **AC4.** No mailbox credential exists in Doppler, env files, or code; the only secret
  is the Resend Inbound webhook signing secret.
- **AC5.** The legal bundle (FR8) is committed and cross-consistent
  (legal-compliance-auditor pass).
- **AC6.** ops@soleur.ai is not the recovery/login address for any vendor account
  (checklist against the vendor list in the expense ledger).

## Open Questions (carried from brainstorm)

1. Ping transport: server-side Slack vs web push (no server-side Slack exists today).
2. Resend Inbound DNS/payload specifics — verify live at plan time.
3. Sender scoping at launch: allowlist-first vs all-mail (leaning allowlist-first).
4. Supersede vs amend `feat-inbound-email-action-bus/spec.md` (its Non-Goals prohibit
   this; its buy-path FRs already shipped on main).
