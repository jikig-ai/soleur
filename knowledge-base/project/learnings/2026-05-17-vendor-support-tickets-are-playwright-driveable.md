---
title: "Vendor support tickets are Playwright-driveable; OTP is the only legitimate operator-handoff gate"
date: 2026-05-17
pr: 3946
category: workflow
status: encoded
encoded_in: plugins/soleur/skills/work/SKILL.md (Phase 4 Playwright-First Audit)
---

## Symptom

In PR #3946 PR-γ (Sentry residency A2 Branch C cleanup), the original §17 task framing said two Sentry support tickets (billing refund + forensics) were "NOT Playwright-driveable" because "Sentry's support form requires the operator (account holder) to compose + submit." The agent drafted ticket bodies to a markdown file and handed off to the operator with paste-and-submit instructions.

Operator pushback: "you should fill them out for me, I shouldn't have to do this and improve the workflow so it's encoded for future soleur users."

## Root cause

Two reasoning errors:

1. **"Compose + submit" was treated as one indivisible unit.** It's not. Compose is the agent's job (already done in the drafts file). Submit-to-Intercom is Playwright work. There's no joint atomicity constraint — these can decompose.

2. **"Operator account holder" was treated as a hard authentication gate.** It's not. The vendor's chat widget (Intercom in this case) recognizes the operator via browser cookie + email entry; OTP verification is sent to the operator's inbox. Playwright drives the entire flow EXCEPT the OTP-paste step, which is a legitimate authentication boundary (the OTP is sent to the operator's email, which Playwright cannot — and should not — access).

The instinct to label vendor support submissions as "operator-only" comes from a pre-Intercom mental model where support tickets were submitted via signed-in dashboard forms that genuinely required operator identity proof inline. Modern vendor support is overwhelmingly chat-widget-mediated and Playwright-tractable up to the OTP gate.

## Resolution

PR #3946 retroactively drove both tickets via Playwright at `https://help.sentry.io/`:

- **Ticket 1 (billing refund):** opened Intercom messenger, sent the body, AI returned standard non-refund policy reply, sent escalation follow-up explaining IaC-error context, AI requested email for routing, OTP (`<otp-redacted>` — 6-digit, single-session, consumed at submission time) sent to `jean.deruelle@jikigai.com` (operator pasted the code back into chat), conversation routed to Sentry Foundations team. Conversation auto-titled "Billing refund request" by Intercom.
- **Ticket 2 (forensics):** opened a SEPARATE Intercom conversation (per brainstorm Decision #9 non-threading requirement), sent forensics body, AI returned substantive non-disclosure-policy statement citing Sentry help articles (which is itself the residual ceiling we needed for PIR Phase 8 Gate 3c), sent escalation follow-up requesting citable policy + escalation-path inquiry, routed to Foundations team without re-prompting OTP (cookie session already verified).

Total operator interaction: paste one 6-digit OTP into chat. Zero "compose and submit a ticket" cognitive load.

## Encoded rule

Updated `plugins/soleur/skills/work/SKILL.md` Phase 4 Playwright-First Audit to explicitly list vendor support submissions as Playwright-driveable and enumerate the legitimate manual gates: email-OTP, payment-card iframe, CAPTCHA, hardware MFA tap. Anti-pattern phrases ("the operator pastes + submits", "manually submit at vendor URL") added to the trigger list.

## Trigger phrases to watch for in future plans

- "operator submits via [vendor] support form"
- "operator pastes the ticket body into [vendor] portal"
- "the agent should draft the ticket bodies and hand off the final paste-and-submit step"
- "this is NOT Playwright-driveable — [vendor]'s form requires the operator"

All four are wrong by default. Each should trigger a Playwright-first attempt at the vendor's chat widget (`help.<vendor>.io` / `support.<vendor>.com` / `<vendor>.zendesk.com`) before declaring operator-handoff.

## Caveats

- Some vendor support flows are dashboard-internal (signed-in form inside the product UI) — these are still Playwright-driveable if the operator's session cookie is available; same OTP-as-gate pattern.
- Sales-managed accounts (enterprise vendors with named CSMs) may route through email instead of chat; in that case, the agent drafts the email body, the operator sends from their MUA. This is a different shape and a legitimate exception — capture in the plan that "this vendor's support flow is email-only" before defaulting to operator-handoff.
- "Submit" buttons that POST cross-origin to a closed external system (e.g., Stripe billing card entry) remain operator-side per the existing PAYG / payment-card guidance — those are not support-ticket submissions but separate decision-and-ack surfaces.

## Cross-references

- PR #3946 PR-γ scope: `knowledge-base/project/specs/feat-sentry-residency-a2-branch-c-1/tasks.md` §17
- Ticket drafts file (updated to reflect submitted state): `knowledge-base/engineering/ops/runbooks/sentry-support-ticket-drafts.md`
- PIR Phase 8 Gate 3 anchor: `knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md`
- Related hard rules: `hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, `hr-mcp-tools-playwright-etc-resolve-paths`.
