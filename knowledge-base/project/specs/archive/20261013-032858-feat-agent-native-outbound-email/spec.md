---
feature: agent-native-outbound-email
issue: 5325
branch: feat-agent-native-outbound-email
pr: 5326
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
closes: 5325
brainstorm: knowledge-base/project/brainstorms/2026-06-15-agent-native-outbound-email-brainstorm.md
---

# Feature: Agent-Native Outbound Email (Pilot Slice)

## Problem Statement

The "send the outreach emails" step of the #5314 listicle campaign is framed as a manual
founder task. It is actually a **capability gap**: the operator inbox (`ops@jikigai.com`,
Resend) is inbound-only — agents can read/triage mail but cannot send or reply. The send
*primitive* already exists (`notifications.ts` wraps `resend.emails.send()` with header-injection
hygiene), but there is no agent-callable cold-outbound path, no send-time compliance enforcement,
no campaign/suppression persistence, and no authenticated sending domain for `jikigai.com`.

This spec covers the **pilot slice** that de-risks #5314: a human-approval-gated agent send/reply
capability with a code-enforced compliance gate, suppression list, and a dedicated authenticated
sending domain. The generic outbound subsystem (automated campaign state machine, jurisdiction
auto-tagging, approval-queue UI, auto-send) is deferred to a follow-up issue.

## Goals

- Let an agent draft and **send compliant cold outreach** for #5314 under a human approval gate.
- Enforce CLO conditions **C1–C5 in code** (refuse-to-send on failure), not by agent memory.
- Authenticate a dedicated **`mail.jikigai.com`** sending subdomain (SPF/DKIM/DMARC) via IaC.
- Persist a **suppression list** honored at send time and across future campaigns.
- Establish the **legal basis** (new/amended LIA + Art. 30 register entry) for outbound authority.

## Non-Goals

- Automated campaign state machine / auto Touch-2 after 7 business days (manual re-trigger in pilot).
- Jurisdiction auto-tagging (publisher TLD / whois inference) — manual tagging on the send list for pilot.
- Confidence-gated **auto-send** of any kind — cold sends are human-approved, permanently.
- A dedicated approval-queue UI — approval rides the existing agent chat in the pilot.
- Branded HTML outreach templates — outreach bodies are plain-text 1:1 for deliverability.
- CAPTCHA-gated / contact-form-only targets — true human gate, out of scope.

## Functional Requirements

### FR1: Agent send/reply tools
Add `email_send` and `email_reply` to `buildEmailTriageTools`, wired into `agent-runner.ts` as
`mcp__soleur_platform__email_*`. Both route exclusively through the compliance chokepoint and are
registered at an **ask-approval** tool tier (never auto-approve, unlike the read tools).

### FR2: Human approval via existing chat
The agent drafts the outreach in the conversation; the operator approves; only then does the send
fire. No new UI surface. A persisted `approved_at` is re-verified by the chokepoint at send time.

### FR3: Compliance chokepoint (refuse-to-send)
`sendCompliantOutbound()` validates C1 (postal-address footer), C2 (working opt-out line),
C3 (jurisdiction tag present + EU/UK data-source/Art.14 disclosure block — content-validated),
C4 (FTC material-connection line on free-access pitches), and the C5 suppression-check (recipient
not suppressed). It **throws before touching Resend** on any failure.

### FR4: Suppression list
A suppression table; opt-out replies (detected via the inbound classifier thread-matcher) add the
recipient permanently; the chokepoint rejects any send to a suppressed address.

### FR5: Authenticated sending domain
Onboard `jikigai.com` to Terraform/Cloudflare and provision `mail.jikigai.com` with SPF, DKIM, and
a DMARC record (`p=quarantine` → `reject` after alignment verified). Outreach sends from this subdomain.

### FR6: Legal artifacts
A new/amended LIA authorizing outbound reply/send (superseding the 2026-06-11 inbound LIA's
"no send authority" boundary) and a GDPR Art. 30 register entry for the outbound processing.

## Technical Requirements

### TR1: Single chokepoint, sentinel-enforced
`apps/web-platform/server/email-triage/outbound.ts` is the ONLY module importing the Resend client
for outbound. A grep/lint sentinel (per `hr-write-boundary-sentinel-sweep-all-write-sites`) fails
CI if any other file references outbound `resend.emails.send`. Reuse the shared send helper +
`sanitizeDisplayString`/`escapeHtml` extracted from `notifications.ts`.

### TR2: Data model mirrors inbound posture
New `outbound_campaigns` and suppression tables: ENABLE RLS (SELECT-for-owner only), REVOKE
INSERT/UPDATE from `authenticated`, all writes via SECURITY DEFINER RPCs with one-way state
transitions and `set search_path = pg_temp` pinned (`cq-pg-security-definer-search-path-pin-pg-temp`).
Do NOT reuse the WORM `email_triage_items` table.

### TR3: Reply/decline detection
Reuse the inbound triage classifier (`summarize.ts`/`events.ts`) plus a campaign-reply matcher keyed
on thread/message-id that flips campaign state and triggers suppression on decline. Do not fork the classifier.

### TR4: Jurisdiction default
Unknown/low-confidence jurisdiction defaults to **EU/UK-strict**; never falls through to the lenient
US path. C3's EU/UK disclosure is content-validated for Art. 14 elements, not string-presence.

### TR5: Observability (no SSH / no dashboard-eyeball)
Send failures and refuse-to-send events mirror to Sentry (`cq-silent-fallback-must-mirror-to-sentry`),
reachable without SSH (`hr-no-ssh-fallback-in-runbooks`, `hr-observability-as-plan-quality-gate`).
DMARC `rua` aggregate reports monitored before/after first send.

### TR6: Infra reachability + cost
Verify `jikigai.com` is reachable by the existing Cloudflare `cf_zone_id` token (else a new
provider/token per `hr-fresh-host-provisioning-reachable-from-terraform-apply`). Confirm Resend
domain-count limit before provisioning; record any tier bump in the expense ledger.

### TR7: Tests before code
Failing tests first (`cq-write-failing-tests-before`): chokepoint refuse-to-send for each of
C1–C4 + suppression; sentinel test asserting single outbound→Resend path; RLS/RPC tests on new tables.
