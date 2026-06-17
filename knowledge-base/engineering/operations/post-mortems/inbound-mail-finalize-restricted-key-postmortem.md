---
title: "Postmortem: inbound non-probe mail silently stranded at NULL (HOP F restricted_api_key) — masked by #5467"
date: 2026-06-17
incident_pr: 5475
incident_window: "since feat-operator-inbox-delegation shipped the email-on-received pipeline (fetch-received-email.ts reused the send-scoped RESEND_API_KEY for the inbound receiving.get) → 2026-06-17 (PR #5475 deployed the degraded-finalize tail). Sentry WEB-PLATFORM-35 firstSeen 2026-06-12T19:32:50Z, lastSeen 2026-06-17T13:56:01Z, count 5."
recovery_at: "2026-06-17 (PR #5475 merge — silent-NULL defect resolved; FULL mail-class restoration pending the receiving-key provision in #5480)"
suspected_change: "fetch-received-email.ts used process.env.RESEND_API_KEY (send-scoped/restricted) for resend.emails.receiving.get, which requires receiving-read scope — every non-probe inbound email threw restricted_api_key on HOP F, exhausted retries:1, and left mail_class/summary permanently NULL with no compensating degraded write."
brand_survival_threshold: single-user incident
status: resolved
closed_via: "PR #5475 (degraded-finalize tail + receiving-key read); full classification restored by the IaC provision tracked in #5480"
triggers:
  - inbound mail mail_class null
  - email_triage_items summary null
  - restricted_api_key
  - resend receiving get
  - HOP F summarizer tail
  - silent permanent NULL
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach. The two stranded rows were SYNTHETIC direct-to-inbound diagnostic emails (no real personal data); real operator mail never reached HOP F because the upstream Proton-Sieve forward (#5467) was dead and masked this defect. The risk was a FUTURE missed GDPR Art. 12 response clock once #5467 was fixed (availability/processing-detection failure), never unauthorized access/disclosure/exposure of personal data."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The email-triage pipeline (`email-on-received.ts`) fetches an inbound email's body in the fused `fetch-sanitize-summarize` step (HOP F) via `resend.emails.receiving.get(id)`. That call requires Resend **receiving-read** scope, but `fetch-received-email.ts` read the shared `RESEND_API_KEY`, which is **send-scoped (restricted)**. Every non-probe inbound email therefore threw `restricted_api_key` on the body fetch, exhausted the `retries: 1` budget, and left the claim-inserted row at `mail_class=NULL` / `summary=NULL` **forever** — with no compensating degraded write and no `matchStatutoryBody` pass. A body-only statutory letter (DSAR / breach notice) would have had its GDPR Art. 12 response clock silently eaten.

The defect was **masked** by #5467: the upstream Proton-Sieve forward was broken, so no real operator mail reached HOP F. Only two SYNTHETIC direct-to-inbound diagnostic emails ever hit the path (2026-06-12 and 2026-06-17), both stranded at NULL. It was discovered **incidentally** while diagnosing #5467.

## Status

resolved — PR #5475 ships the code-resilience fix (degraded-finalize tail + receiving-key read). Full mail-class classification is restored once the receiving-scoped key is provisioned via IaC (#5480).

## Symptom

`select id, mail_class, summary from email_triage_items where mail_class is null and statutory_class is null` returned 2 rows stuck NULL for up to 5 days; Sentry issue WEB-PLATFORM-35 (`Error: fetch-received-email failed: restricted_api_key`, culprit `POST /api/inngest`) firing on each non-probe inbound delivery.

## Incident Timeline

- **Start time (detected):** 2026-06-17 (during #5467 diagnosis)
- **End time (recovered):** 2026-06-17 (PR #5475 merge)
- **Duration (MTTR):** ~hours (same-day fix once detected)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-12T19:32Z | First non-probe diagnostic email throws `restricted_api_key` on HOP F (WEB-PLATFORM-35 firstSeen); row stranded NULL. |
| human | 2026-06-17 | Second diagnostic email strands NULL; defect noticed during #5467 inbound-chain diagnosis; #5468 filed. |
| agent | 2026-06-17 | Sentry RCA confirmed root cause (restricted send key reused for receiving fetch); PR #5475 implemented the degraded tail + receiving-key read. |
| agent | 2026-06-17 | PR #5475 merged — silent-NULL defect resolved. |

## Participants and Systems Involved

`email-on-received.ts` (Inngest fn), `fetch-received-email.ts` (Resend `receiving.get` wrapper), Resend (inbound body retrieval), Anthropic (summarizer), Supabase `email_triage_items` (WORM-frozen), Sentry (WEB-PLATFORM-35).

## Detection (+ MTTD)

- **How detected:** incidental — surfaced while diagnosing the dead inbound chain (#5467); the stranded NULL rows + Sentry WEB-PLATFORM-35 were the evidence.
- **MTTD:** ~5 days from firstSeen to detection (the defect was masked by #5467, so it produced no user-visible symptom until investigated).

## Triggered by

system — a least-privilege scope mismatch (send-scoped key used for a receiving-scoped API call), latent until an inbound email reached HOP F.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Egress drop / Resend 404 / generic code error | issue #5468's three initial hypotheses | Sentry WEB-PLATFORM-35 message is the deterministic `error.name` branch = `restricted_api_key` (a Resend auth-scope error, not egress/404) | rejected |
| Send-scoped key reused for receiving fetch | WEB-PLATFORM-35 = `restricted_api_key`; `fetch-received-email.ts` read `RESEND_API_KEY`; `receiving.get` needs receiving scope | none | confirmed |

## Resolution

PR #5475: (1) `fetch-received-email.ts` reads a dedicated `RESEND_RECEIVING_API_KEY` (no send-key fallback); (2) a final-attempt-gated degraded-finalize tail writes a visible `mail_class='other'` row + sentinel summary + (statutory-grade-when-body-unavailable) notify + Sentry mirror instead of a silent NULL — independent fetch/LLM catches, a disjoint-column WORM race guard, and a daily-LLM-ceiling exclusion for the sentinel. The IaC provisioning of the receiving key (operator mint + `doppler_secret`) is split to #5480 per ADR-065 (auto-apply-on-merge cannot tolerate the unprovisioned no-default TF var).

## Recovery verification

`vitest run test/server/inngest/email-on-received.test.ts` 43/43 (incl. the two-attempt recovery + disjoint-column race). Post-#5480 (key apply): `select … where mail_class is null and statutory_class is null and created_at > now() - interval '7 days'` trends to zero for mail received after the apply (Supabase MCP read; AC13). Until #5480, real inbound mail degrades visibly (`other` + sentinel + statutory-grade notify) instead of stranding NULL.

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did inbound mail stay NULL?** HOP F's body fetch threw and exhausted retries with no compensating write.
2. **Why did it throw?** `resend.emails.receiving.get` returned `restricted_api_key`.
3. **Why `restricted_api_key`?** The call used the send-scoped `RESEND_API_KEY`, which lacks receiving-read scope.
4. **Why was a send-scoped key used for a receiving call?** `fetch-received-email.ts` reused the one existing Resend key without recognizing the receiving fetch needs a distinct scope (no least-privilege split at build time).
5. **Why was the failure silent (NULL forever)?** The pipeline had no degraded-finalize tail — a throw left the one-time-set columns NULL with no visible row, no notify, and `matchStatutoryBody` unreached.

## Versions of Components

- **Version(s) that triggered the outage:** the build that first shipped `email-on-received.ts` / `fetch-received-email.ts` (feat-operator-inbox-delegation).
- **Version(s) that restored the service:** PR #5475 (code-resilience); full restoration at #5480 (receiving-key provision).

## Impact details

### Services Impacted

Inbound email-triage classification (the sole operator-inbox ingress). Probe path unaffected (probe finalizes before HOP F).

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user (operator): would have seen blank/unclassified inbound rows once #5467's forward was live; in practice masked (no real mail reached HOP F). Two synthetic diagnostic rows stranded.
- Legal-document signer / DSAR sender: latent risk — a body-only statutory letter's Art. 12 clock would have been silently un-detected once real mail flowed; never realized (masked).
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

~hours of agent time (Sentry RCA + fix). No operator-facing outage (masked).

## Lessons Learned

### Where we got lucky

The defect was masked by #5467, so no real operator mail (and no real DSAR) was processed during the window — the only victims were two synthetic diagnostic emails. Had #5467 been fixed first, a real body-only DSAR could have been silently dropped.

### What went well

Sentry Layer-1 capture (WEB-PLATFORM-35) recorded the exact error name (`restricted_api_key`) on every throw, making the RCA deterministic at plan time rather than hypothesised.

### What went wrong

The original pipeline had no degraded-finalize tail — a HOP F throw produced a silent permanent NULL rather than a visible degraded row. And the receiving fetch was wired to a send-scoped key with no least-privilege split.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5480 | Provision the least-privilege `RESEND_RECEIVING_API_KEY` via IaC (operator mint + `doppler_secret`) to restore full inbound mail classification (the degraded tail in #5475 is the interim compensating control). | open |
