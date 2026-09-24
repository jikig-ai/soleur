---
title: "Outbound-email refusals wrote the recipient address into log sinks"
date: 2026-09-23
incident_pr: 8617
incident_window: "2026-06-09 (#5325 ship) until the deploy of PR #8617"
recovery_at: "pending — the deploy of PR #8617"
suspected_change: "71758cc2b6 (#5325) — OutboundComplianceError messages interpolated ${addr} / ${to}"
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - privacy-commitment-contradiction
  - third-party-personal-data-in-logs
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — CLO determination 2026-09-23: not an Art. 4(12) breach (every recipient is a processor under DPA; no unauthorised access). Recorded in knowledge-base/legal/breach-register.md."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The published privacy policy (§4.14) and GDPR policy (§3.11) stated that the plaintext
recipient address of an outbound cold email is never stored. From the day the outbound-email
feature shipped, a REFUSED send broke that: two `OutboundComplianceError` throws in
`apps/web-platform/server/email-triage/outbound-compliance.ts` interpolated the address, and
the `email_send` catch mirrored the error through `reportSilentFallback` into pino (journald on
the web host's unencrypted root disk), Better Stack, and Sentry (where `err.message` becomes
the issue title). The fix review found three further stores of the same data the policy did
not list: offline review-gate notifications (push + a Resend email Resend retains for 30 days),
aborted-turn summaries in `messages.usage.completed_actions`, and the drafting agent
conversation itself.

## Status

ongoing — the code fix is in PR #8617 and takes effect at its deploy. Pre-fix copies expire on
their disclosed bounds (Better Stack 90 days, journald 1G cap, Resend 30 days), with two
exceptions. Sentry is purged after the merge. The four Hetzner snapshot images of web-1's root
disk (2026-06-18 to 2026-07-23) copy the journal as of their dates and persist until deleted;
their disposition and hard expiry (2026-10-06) are recorded under #8532. **[Superseded 2026-09-24 (#8532), as to "Better Stack 90 days" and "Sentry is purged after the merge": measured 2026-09-24 (counts only), no Sentry issue or event and no Better Stack row matches either pre-fix refusal message, so the Sentry purge was discharged without a deletion. Better Stack's retained span began 2026-08-13 15:14Z, not 90 days back, so earlier pre-fix copies had already expired there. journald was not measured. The mechanism described above (the error message becomes the Sentry issue title) still stands; the measurement found no such title retained. PA-28 §(c) records this by the 2026-09-24 amendment that lands with the merge of PR #8626.]**

## Symptom

No user-visible symptom. The defect is a mismatch between a published privacy commitment and
what the log sinks hold. It was found by reading code, not by an alert.

## Incident Timeline

- **Start time (detected):** 2026-09-23
- **End time (recovered):** pending the deploy of PR #8617
- **Duration (MTTR):** open

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-06-09 | #5325 shipped outbound email; two refusal throws interpolate the recipient address. |
| agent | 2026-06-15 | Privacy-policy sentence "the plaintext recipient address is never stored" published. |
| agent | 2026-09-23 | #8532 plan review traces the refusal path from the throw sites to journald, Better Stack and Sentry. |
| agent | 2026-09-23 | PR #8617 opened; an 11-agent review finds the offline-notification and aborted-turn stores. |
| agent | 2026-09-23 | CLO rules the sentence must be scoped; corrections drafted and applied in PR #8617. |

## Participants and Systems Involved

Web platform server (`outbound-compliance.ts`, `email-triage-tools.ts`, `observability.ts`,
`logger.ts`, `notifications.ts`, `agent-runner.ts`, `permission-callback.ts`); journald on the
web host; Better Stack; Sentry; Resend; Supabase (`messages`).

## Detection (+ MTTD)

- **How detected:** manual — a plan review for #8532 traced the refusal path.
- **MTTD (mean time to detect):** about 106 days from ship (2026-06-09 to 2026-09-23).

## Triggered by

system — a code defect present since the feature shipped.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Refusal messages interpolated the address and the catch mirrored the raw error | `${addr}` / `${to}` in both throws at `71758cc2b6`; `reportSilentFallback(error, …)` in the `email_send` catch | none | confirmed |
| Key-name redaction would have caught it | `SENSITIVE_KEY_NAMES` redacts by key | the address sat inside a string value (`err.message`), which key-name redaction cannot see | ruled out |

## Resolution

PR #8617: the throw sites name the field instead of the value; a value-redaction layer
(`server/pii-redact.ts`) runs at every emitter, in the `logger.ts` `logMethod` hook and in
`sentry-scrub.ts`; the offline gate notification and aborted-turn summaries for outbound-email
tools no longer carry the recipient or body; the three published documents are scoped by CLO
ruling with dated Corrected notices.

## Recovery verification

Pre-merge: `test/server/outbound-refusal-no-address.test.ts`, `test/server/pii-redact.test.ts`
and `test/server/logger-address-redaction.test.ts`, with a 15-row mutation battery all killed.
Post-deploy verification (a refused send's emitted record carries no address) is tracked in #8532.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was the address in the logs? The refusal message interpolated it.
2. Why did that reach every sink? The catch mirrored the raw error, and Sentry uses the message as the issue title.
3. Why did redaction not catch it? Redaction was key-name based; an address inside a string value is invisible to it.
4. Why did review of #5325 not catch it? The privacy sentence was written six days after the code, and nothing checked the sentence against the code paths.
5. Why were three more stores unknown? The sentence was scoped to the whole platform while it was only ever true of the two outbound tables; nothing enumerated every store of the value.

## Versions of Components

- **Version(s) that triggered the outage:** every web-platform release since `71758cc2b6` (#5325).
- **Version(s) that restored the service:** the release carrying PR #8617.

## Impact details

### Services Impacted

Log and error-tracking sinks only. No send path, approval gate or opt-out behaviour changed.

### Customer Impact (by role)

- Prospect: outbound recipients whose send was REFUSED had their address written to journald, Better Stack and Sentry; recipients reviewed while the operator was offline had their address and the start of the body sent in a Resend email to the operator.
- Authenticated app user: the account holder's own address was logged under the `email` key on notification sends (now key-redacted).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

One plan-review session plus the PR #8617 cycle.

## Lessons Learned

### Where we got lucky

Refused sends are rare (the refusal path fires on malformed or internal/role addresses), and
every sink is a processor under DPA, so no third party beyond disclosed processors received the data.

### What went well

The plan review traced the path end to end from a single published sentence, and the review
panel enumerated the stores the plan had not listed.

### What went wrong

The first fix introduced an O(n²) redaction regex and overstated its own coverage; both were
caught only by review. See
`knowledge-base/project/learnings/security-issues/2026-09-23-my-redaction-fix-was-quadratic-and-the-sentence-it-defended-was-still-false.md`.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #8532 | Purge the refusal-path Sentry issues after the merge (CLO ruling); update Article 30 PA-28 §(c) when done; verify in production that a refused send's record carries no address (AC-0c-i). **[2026-09-24 (#8532): Sentry purge discharged without a deletion (0 matching issues or events); PA-28 §(c) is updated by PR #8626 on its merge; the AC-0c-i production check is recorded separately.]** | open |
| #3418 | Disclose and bound the agent-conversation session transcripts, the one store the scoped sentence names as holding the recipient and body. | open |
