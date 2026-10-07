# Resend Inboxes vs. the current inbound-email stack — Brainstorm

**Date:** 2026-10-03
**Lane:** cross-domain
**Status:** decided (Approach A)

## What We're Building

An evaluation of Resend Inboxes (private beta, enabled via resend.com/settings/labs) as a replacement for, or complement to, the current inbound-email stack, for two capabilities: (a) an email inbox per Soleur user and (b) email inboxes for key agents.

**Decision:** keep the current stack (ADR-055). Do the stack-neutral preparation that makes either future path cheap. Do not adopt Resend Inboxes now. Revisit at Resend GA or after three founders ask for an inbox.

## Premise Correction

The operator's framing said the current solution uses Amazon SNS. It does not.

- `git grep` on main finds no SNS, SES or `@aws-sdk` usage in `apps/web-platform` or infra.
- The stack is Resend Inbound (ADR-055): Proton Sieve forward → Resend (`inbound.soleur.ai`) → svix-verified webhook → Inngest `email-on-received` → summary-only `email_triage_items`, with a daily synthetic probe (`cron-email-ingress-probe`) and a Sentry cron monitor.
- Only Resend's own receiving MX host (`inbound-smtp.eu-west-1.amazonaws.com`) is AWS, and that is Resend's infrastructure.

## Resend Inboxes — verified facts (2026-10-03, live docs)

- Private beta. "The response shape might change before GA". Requires preview SDK `resend@6.28.1-preview-inboxes.2` or CLI `resend-cli@2.22.0-preview-inboxes.2`.
- `POST /inboxes` takes `email_address` (on a verified domain), optional `name`, `from_name` and `forwarding` (provisions a receiving address with no MX change).
- API surface: threads (`GET /inboxes/:id/threads?query=`), drafts (`POST /inboxes/:id/drafts`), replies on threads, labels, folders, read state, assignment and notes. An MCP server is offered for Claude Code, Cursor, Codex, Grok and Gemini.
- Not published: pricing, rate limits, data retention, delete semantics, region of storage, webhooks for Inboxes. The Resend DPA states US primary processing under SCCs and the DPF. The 30-day, no-delete-API finding in ADR-055 covers Resend Inbound and is unverified for Inboxes.

## Why This Approach

All three mandatory leaders (CPO, CLO, CTO) independently recommended against migrating now.

- **No demand signal.** The roadmap holds every email item (#5103, #5527, #5183, #9311) in Post-MVP / Later. Alpha recruitment is 1 of 10 founders. Cofounder bundling agent inboxes is competitive pressure, not demand evidence.
- **Custody inversion.** ADR-055 made parse-and-discard structural (no body column). Inboxes makes Resend the system of record for full third-party mail. ADR-055's rejection of shared-inbox vendors on custody grounds (Option B) still holds.
- **Compliance.** Per-user inboxes make each user a controller, Jikigai a processor and Resend a sub-processor. DPIA screening triggers 1 (non-operator owners) and 2 (send/act authority) both fire. No Resend DPA exists under `knowledge-base/legal/data-processing-agreements/`. Agent-autonomous replies overturn the human-approved send assumption in PA-28 and its LIA.
- **Maturity.** Preview SDK, unstable API, no SLA, no Terraform provider (AP-001 deviation).
- **Preparation is stack-neutral.** The same routing table, columns and interface serve either future path, so waiting costs little.

## Key Decisions

| Decision | Choice |
|---|---|
| Adopt Resend Inboxes now | No |
| Stack-neutral prep | Yes: address→workspace routing table, `agent_id` and `thread_key` columns, `InboxProvider` interface |
| Vendor questions | Ask Resend in writing for storage region, retention, delete semantics, pricing, sub-processor list; also send feedback in reply to their email |
| Revisit trigger | Resend GA with published retention, pricing and delete semantics, or 3 or more founders ask for an inbox |
| Agent-only spike | Deferred until Resend's written answers arrive (flag-gated, subdomain, `forwarding: true`, sends through `sendCompliantOutbound`) |
| Visual design | None (no UI surface in this decision) |

## User-Brand Impact

- **Artifact:** the per-user and per-agent email inbox surface, including any vendor-held copy of inbound mail.
- **Vector:** a user's or a third-party correspondent's mail exposed, retained past a promise, or answered by an agent without approval.
- **Threshold:** single-user incident.

## Open Questions

- Where does Resend Inboxes store data, for how long, and can it be deleted? (Ask Resend in writing.)
- Does Inboxes emit webhooks, and with what signature scheme?
- Pricing and rate limits for Inboxes.
- Address-to-workspace routing shape: plus-address, per-tenant subdomain or per-user local part. (Plan-time decision.)
- Do any Phase 4 interviewees want an inbox at all? (Ask in #1440 and #1441 conversations.)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Do not adopt now. No founder demand evidence; a mailbox product is a different category from "AI organization for solo founders". Spike only after 3 or more founders ask, and only for agent-owned addresses.

### Legal

**Summary:** Not adoptable for per-user inboxes as it stands: full DPIA, Art. 28 chain, new Art. 30 rows, LIA rework for agent sends, and Resend DPA on file are all prerequisites. Verify Inboxes region, retention and delete semantics in writing first.

### Engineering

**Summary:** Keep the current stack as system of record. Add routing, `agent_id` and `thread_key` columns plus an `InboxProvider` interface. Spike one agent inbox only after GA-grade answers. No SNS exists in the repo.

## Capability Gaps

- **No address→workspace routing.** Evidence: `git grep -n EMAIL_TRIAGE_OWNER_USER_ID main -- apps/web-platform` shows a single env-pinned owner in `email-on-received.ts`.
- **No email threading.** Evidence: `email_triage_items` (migration 102) has no thread key; items are one row per message.
- **No Resend DPA on file.** Evidence: `knowledge-base/legal/data-processing-agreements/` contains only anthropic, flagsmith and openai.

## Productize Candidate

None.
