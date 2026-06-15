---
date: 2026-06-15
topic: agent-native-outbound-email
issue: 5325
branch: feat-agent-native-outbound-email
pr: 5326
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Agent-Native Outbound Email (reply/send) on the Operator Inbox

## What We're Building

A **pilot-scoped, human-approval-gated outbound email capability** that lets an agent
draft *and send* compliant cold outreach (starting with the #5314 listicle campaign)
on the founder's behalf — turning the "send the emails" step from a manual founder task
into an agent-run action under a human approval gate.

**Scope decision (operator, 2026-06-15): Pilot slice, not the full subsystem.**
The smallest slice that de-risks #5314:

1. **Sending-domain onboarding** — onboard `jikigai.com` as a Terraform/Cloudflare zone
   and add a dedicated **`mail.jikigai.com`** send subdomain with SPF/DKIM/DMARC
   (operator choice: founder's company brand, aligned with the `ops@jikigai.com` inbox).
2. **Compliance chokepoint** — a single `sendCompliantOutbound()` in
   `apps/web-platform/server/email-triage/outbound.ts` that is the ONLY module importing
   the Resend client for outbound, and **throws (refuse-to-send) on any C1–C4 / suppression
   failure** before touching Resend.
3. **Agent tools** `email_send` / `email_reply` added to `buildEmailTriageTools`, at an
   **ask-approval** tool tier (never auto-approve), routing exclusively through the chokepoint.
4. **Suppression list** table + opt-out honoring (C5 corollary = hard send-time precondition).
5. **Human approval rides the existing agent chat** — agent drafts in conversation, operator
   approves, chokepoint validates + sends. No new approval-queue UI in the pilot.
6. **New / amended LIA** for outbound authority (overturns the 2026-06-11 inbound LIA's explicit
   "no send authority" boundary) + GDPR Art. 30 register entry for the outbound processing.

**Deferred to a follow-up issue (the "subsystem"):** automated campaign state machine
(auto Touch-2 after 7 business days), jurisdiction auto-tagging, a dedicated approval-queue
UI, and any confidence-gated auto-send. For the pilot, Touch-2 is a **manual founder re-trigger**.

## Why This Approach

- **The premise was wrong in the issue's favor of *less* work.** The send *primitive*
  already exists (`notifications.ts` wraps `resend.emails.send()` with header-injection
  hygiene; `cron-email-ingress-probe.ts` sends too). So this is "expose + gate + persist",
  not "build send from scratch."
- **Cold mail under unproven compliance logic is irreversible and regulated** — the wrong
  place for autonomy. Human-approval-only for cold sends was the unanimous call (CPO + CLO + CMO).
- **Pilot-first lets the C1–C5 gate earn a track record** before a generic subsystem rides on it.
- **Onboarding `jikigai.com` is the true blocker**, surfaced now rather than discovered at
  ship — it is a Terraform/Cloudflare zone that does not exist in IaC today.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Pilot slice, defer the generic subsystem | CPO: real demand is "get #5314 sent compliantly," not a generic outbound engine. |
| D2 | Send from a dedicated `mail.jikigai.com` subdomain (onboard the zone) | Operator choice; CMO/COO: isolate cold-mail reputation from `ops@` inbox and `notifications@soleur.ai`; founder-brand alignment. |
| D3 | NO confidence-gated auto-send for cold mail — ever | CPO+CLO+CMO unanimous. Auto-send only later, scoped to *warm replies within an existing thread*. |
| D4 | Single chokepoint `sendCompliantOutbound()` is the only outbound→Resend path; refuse-to-send on gate fail; grep/lint sentinel forbids any other file calling outbound `resend.emails.send` | CTO; mirrors `hr-write-boundary-sentinel-sweep-all-write-sites`. Gate in the tool layer alone is bypassable. |
| D5 | C1–C4 = hard refuse-to-send preconditions; C5 suppression-check is also a hard precondition (C5 honoring is operational) | CLO. |
| D6 | C3 EU/UK disclosure is **content-validated**, not string-presence — it carries GDPR Art. 14 elements (identity, purpose, legal basis=legitimate interest, source, retention, rights) | CLO: scraped publisher emails = third-party collection, Art. 14 triggered. |
| D7 | Default to **EU/UK-strict** when jurisdiction is unknown/low-confidence; never fall through to lenient US path | CLO; matches issue's strict-superset default. |
| D8 | New Supabase tables (`outbound_campaigns`, suppression) mirror `email_triage_items` posture: RLS SELECT-owner-only, REVOKE INSERT/UPDATE, SECURITY DEFINER RPCs (search_path pinned), one-way transitions. Do NOT reuse the WORM inbound table. | CTO. |
| D9 | Reply/decline detection reuses the inbound classifier as a thread/message-id **matcher** (don't fork the classifier) | CTO. |
| D10 | Human approval rides existing agent chat in the pilot; dedicated approval-queue UI deferred | MVP leanness; keeps it agent-native; avoids a new UI surface (Phase 3.55 does not trigger). |
| D11 | New/amended LIA for outbound authority + Art. 30 register entry are required deliverables, not optional | Research: 2026-06-11 LIA explicitly deferred send authority (#4671/#4672 boundary). |
| D12 | Outreach bodies are plain-text 1:1 (deliverability), not a branded template | CMO/standard cold-mail practice. |

**Visual design:** N/A — no new UI surface (chat-based approval on the existing chat; plain-text mail). Phase 3.55 does not trigger.

## Open Questions

1. **Cloudflare token reach for jikigai.com** — is `jikigai.com` in the same Cloudflare
   account as `soleur.ai` (reachable by the existing `cf_zone_id` token), or a separate
   account needing its own provider/token? Must be resolved at plan time before assuming
   `dns.tf` can manage it (`hr-fresh-host-provisioning-reachable-from-terraform-apply`).
2. **Resend domain-count limit** — Resend free tier caps domains; adding `mail.jikigai.com`
   as a 2nd+ sending domain may force the $20/mo tier. Confirm before provisioning (ledger entry).
3. **DMARC gap on send.soleur.ai** — research found `dns.tf` has no DMARC record even for the
   existing `send.soleur.ai`. New `mail.jikigai.com` must ship DMARC `p=quarantine`→`reject`;
   consider closing the soleur.ai DMARC gap in the same infra PR.
4. **Multi-zone `dns.tf` vs new Terraform root** — does onboarding a 2nd zone refactor the
   single-zone `dns.tf`, or stand up a new root? (CTO/terraform-architect call at plan time.)

## Domain Assessments

**Assessed:** Product (CPO), Legal (CLO), Engineering (CTO), Marketing (CMO), Operations (COO).
Not assessed: Sales, Finance, Support (not relevant to this capability).

### Product (CPO)
Correctly framed as agent-user parity, but the issue over-specifies. Real demand is one job:
get #5314 sent compliantly. Scope MVP to a human-approval-gated sender for the pilot; defer the
generic subsystem. The C1–C5 gate is the load-bearing component and needs CLO sign-off +
user-impact-reviewer **before** first live send. Approval-gate only; no auto-send for the pilot.

### Legal (CLO)
Cold commercial outreach at machine scale is categorically higher-risk than transactional mail
(CAN-SPAM opt-out; GDPR/PECR EU/UK far stricter). Enforce C1–C5 in code, not agent memory.
C1–C4 are refuse-to-send preconditions; C5's suppression-check is a precondition too. GDPR Art. 14
is triggered (third-party-collected emails) → C3's EU/UK disclosure must be content-validated.
No auto-send for cold mail; default-to-EU/UK-strict when jurisdiction unknown. External counsel
should review the EU/UK cold-outreach posture before first EU/UK send.

### Engineering (CTO)
Medium-large. Send primitive + tool/runner wiring exist; the build is the gate chokepoint,
campaign/suppression tables, and a brand-new DNS-authenticated sending domain. `jikigai.com` is
NOT in Terraform (`dns.tf` is single-zone soleur.ai). The compliance gate MUST be a single
chokepoint (`outbound.ts`) — gate in the tool layer is bypassable. New tables mirror the
`email_triage_items` RLS/SECURITY-DEFINER posture; reuse the inbound classifier for reply matching.
Recommends an ADR for the outbound sending domain + compliance chokepoint.

### Marketing (CMO)
Right initial lever (earned-media / link-building), but a one-time campaign motion, not a scalable
demand-gen engine — build lean. Domain auth is mandatory and load-bearing. Biggest brand risk: a
mis-personalized first line sent autonomously to a journalist/author (megaphone audience). Human
approval for all cold sends, permanently. Dedicated send subdomain non-negotiable; warm-up + volume
caps even at small scale; DMARC `rua` monitoring before first send. 7-biz-day 2-touch cadence is sound.

### Operations (COO)
The ops-load-bearing piece is one thing: outbound domain auth for `jikigai.com`, which is in zero
Terraform. Onboarding `jikigai.com` as a Terraform-managed Cloudflare zone is a **prerequisite** of
#5325, not a checklist item — file as a dependency. Use a dedicated send subdomain (`mail.jikigai.com`),
DMARC `p=quarantine`→`reject`. Resend free tier = 100/day, 3K/mo; domain cap may force $20/mo tier.

## Capability Gaps

1. **`jikigai.com` Terraform/Cloudflare onboarding** — evidence: `apps/web-platform/infra/dns.tf`
   is single-zone (`var.cf_zone_id` = soleur.ai); `jikigai.com` appears only as the `ops@jikigai.com`
   recipient string in `infra/variables.tf:152`. No DNS records for `jikigai.com` exist in IaC.
   Owner: Engineering (terraform-architect) + Operations. Must verify Cloudflare token reach first.
2. **New / amended LIA for outbound authority** — evidence:
   `knowledge-base/legal/legitimate-interest-assessments/2026-06-11-operator-inbox-triage-lia.md`
   states "Not pursued under this LIA: any outbound reply authority (no send authority added to
   pipeline)" with re-eval triggers referencing the #4671/#4672 boundary. Owner: Legal (CLO).
3. **GDPR Art. 30 register entry** for outbound processing of scraped third-party contact data.
   Evidence: prior pattern in `knowledge-base/project/learnings/2026-02-21-gdpr-article-30-email-provider-documentation.md`.
   Owner: Legal (CLO).
4. **DMARC absent in `dns.tf`** even for `send.soleur.ai` — evidence: research grep of
   `apps/web-platform/infra/dns.tf` found SPF + DKIM but no DMARC TXT record. Owner: Engineering/Ops.

## User-Brand Impact

- **Artifact:** the `email_send` / `email_reply` agent tool and the `sendCompliantOutbound()`
  compliance chokepoint on the operator inbox.
- **Vector:** an agent sends a non-compliant or mis-personalized cold email from the founder's
  brand to a high-visibility recipient (journalist/author), or to a suppressed/opted-out contact —
  a CAN-SPAM/GDPR incident plus an irreversible reputation and deliverability hit.
- **Threshold:** single-user incident.

## Productize Candidate

`outbound-campaign` skill — the campaign state machine + suppression + jurisdiction tagging is the
recurring, reusable artifact (deferred subsystem). Filed as the follow-up issue, not built in the pilot.
