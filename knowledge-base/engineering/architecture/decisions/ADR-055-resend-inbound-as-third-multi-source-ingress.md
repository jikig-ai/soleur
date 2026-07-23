---
title: "Inbound email ingress: Proton Sieve auto-forward → Resend Inbound — third multi-source ingress"
status: accepted
date: 2026-06-11
related: [5103]
related_adrs: [ADR-030, ADR-033, ADR-036, ADR-037]
related_plans:
  - knowledge-base/project/plans/2026-06-10-feat-operator-inbox-delegation-plan.md
related_specs:
  - knowledge-base/project/specs/feat-operator-inbox-delegation/spec.md
brand_survival_threshold: single-user incident
---

# ADR-055: Inbound email ingress: Proton Sieve auto-forward → Resend Inbound — third multi-source ingress

> Shape note: rich (8-section) per the adr-template rubric — trigger 4
> (principle deviation: AP-001 and AP-009 both require documented exceptions)
> and trigger 5 (teeth-bearing alternatives: Bridge/IMAP and paid shared-inbox
> vendors were seriously evaluated; the rejection rationale is load-bearing).
> Diagram section omitted per template guidance.

## Context

Operator inbox delegation (#5103) needs agents to triage inbound email to
`ops@soleur.ai` instead of the operator. The mailbox provider is Proton, and
the premise correction recorded at brainstorm is decisive: **Proton exposes no
public API, no OAuth, and no JMAP** (verified; learning
`2026-06-10-proton-capability-facts-and-deferral-override-recording.md`).
Programmatic IMAP access exists only through Proton Bridge, and a Bridge
credential is **send-capable** — holding it anywhere in our infrastructure
creates a standing send-authority secret for a feature whose contract
(#4671/#4672) is read-only triage with no send path.

The platform already operates two push ingresses on one shared shape: Stripe
(ADR-030, the Inngest durable-trigger substrate and first ingress) and the
GitHub App webhook (ADR-036, the second). Both follow the same load-bearing
ordering — signature verify FIRST, dedup insert SECOND
(`processed_<source>_events`, 23505-catch idiom per ADR-037's
migration-052 quirk), `inngest.send` via retry wrapper, release-the-dedup-row
on dispatch failure. A third ingress that mirrors this shape inherits the
tests, the audit posture, and the operational intuition of the first two.

## Considered Options

- **Option A: Proton Bridge / IMAP polling.** Pros: no third-party custody of
  mail beyond Proton. Cons: requires running Bridge as a daemon; the IMAP
  credential is send-capable (a leak grants send authority, violating the
  read-only contract); polling reintroduces the latency-drift and
  idle-cost failure modes ADR-036 already rejected for GitHub. No OAuth or
  scoped-read credential exists on Proton.
- **Option B: Paid shared-inbox vendor (Front/Missive class).** Pros: triage UI
  for free. Cons: a new paid subscription; a new Art. 28 processor with
  full-body custody and its own retention; an inbox UI we would not use — the
  landing surface is our existing conversation inbox; no agent-native API
  parity guarantee.
- **Option C (chosen): Proton Sieve auto-forward (forward-and-keep) → Resend
  Inbound (`inbound.soleur.ai`) → svix-verified webhook → Inngest.** Pros: zero
  standing mailbox credential anywhere; Resend is an existing vendor (outbound
  transactional email, free tier, inbound included on all plans); the webhook
  is metadata-only, so parse-and-discard is enforceable at the ingress
  boundary; reuses the ADR-030/ADR-036 ingress shape wholesale. Cons: Resend
  retains received content 30 days with no delete API (disclosed, see
  Consequences); forwarding strips sender authentication (made load-bearing in
  the Decision below).

## Decision

**Adopt Option C. Resend Inbound is the third multi-source ingress, alongside
Stripe (ADR-030) and the GitHub App webhook (ADR-036).** The route at
`apps/web-platform/app/api/webhooks/resend-inbound/route.ts` mirrors the
canonical GitHub route's ordering: bounded body read (413) → fail-closed 500 on
unset `RESEND_INBOUND_WEBHOOK_SECRET` → svix signature verify on the raw bytes
(svix `Webhook` directly, not `resend.webhooks.verify`, which couples
verification to `RESEND_API_KEY`) → JSON.parse before claim → plain-insert
dedup into `processed_resend_events(svix_id)` → `sendInngestWithRetry` →
**three-way release classification**: (1) transient dispatch failure → release
the dedup row + 5xx (the svix retry is wanted); (2) deterministically
unprocessable payload → KEEP the row + 200 + Sentry warn (a retry is
byte-identical; release+5xx is a poison-retry storm); (3) malformed JSON →
400 with nothing claimed.

**Forwarded-mail sender identity is unauthenticated — Sieve forwarding strips SPF/DKIM context — so no current or future feature may derive trust from the `sender` value.** This sentence is the ADR's load-bearing constraint. It is
why there is no sender allowlist, no `sender_known` badge, and why the daily
probe authenticates by per-run unguessable token rather than by marker shape
or sender match (a static marker would be a forgeable mail-suppression
channel). Any future proposal that branches on `sender` for authorization,
suppression, or auto-action violates this ADR.

**Parse-and-discard is structural, not behavioral.** Resend's
`email.received` webhook is metadata-only (no body, headers, or attachment
content); the body is fetched transiently (`GET /emails/receiving/{id}`)
inside **one fused Inngest step** (`fetch-sanitize-summarize` in
`apps/web-platform/server/inngest/functions/email-on-received.ts`) that
returns only `{summary, mailClass, …}` — the body never crosses a step
boundary, because step.run returns are CHECKPOINTED in the Inngest run store
(ADR-033 I1/I5) and a checkpointed body would defeat the discard. The
`email_triage_items` table (migration 102) **has no body column** — the
guarantee survives any future code change that forgets the rule.

## Consequences

- **The dominant risk is silent ingestion failure** — a broken Sieve rule, a
  dropped Resend capability flag, or a dead webhook all fail quietly, with no
  user-visible error. Mitigation: the daily synthetic probe
  (`cron-email-ingress-probe.ts`) sends a tokenized marker email through the
  full Proton → Resend → webhook → Inngest chain and asserts its own row
  exists in the same run (`retries: 0` so a late probe cannot turn green),
  reporting to the Terraform-managed Sentry cron monitor
  (`infra/sentry/cron-monitors.tf` → `cron_email_ingress_probe`).
- **Resend retains received email content (body + headers + attachments) for
  30 days on all plans, and no delete API exists** — Jikigai cannot shorten
  the window, only let it expire. Disclosed in the Art. 30 register as PA-27
  (`knowledge-base/legal/article-30-register.md`).
- **The Proton keep-copy is the durable original.** The Sieve rule MUST
  forward-and-keep, never redirect-and-discard: our triage rows are summaries,
  and Resend's copy expires — the Proton mailbox is the archival home of the
  original mail.
- Anyone on the internet can mail `ops@soleur.ai`, so the pipeline carries an
  Inngest throttle + daily LLM-call ceiling; on breach, triage degrades
  (`mail_class: other`, deferred summary) rather than spend becoming
  unbounded.
- New ingresses keep getting cheaper: this is the third consumer of the
  verify → dedup → send → release shape and the second consumer of the
  release-on-failure step, with `lib/webhook-dedup` now shared.
- **Leader-prompts coupling:** `server/email-triage/summarize.ts` imports
  `sanitizePromptString` and `HAIKU_MODEL` from
  `server/inngest/leader-prompts/{prompt-assembly,constants}` — extracting
  these shared LLM utilities to a neutral module is deliberate follow-up
  scope, not an oversight.

## Cost Impacts

No new vendor. Resend is already in `knowledge-base/operations/expenses.md`
(free tier: 3,000 emails/mo, 100/day; inbound included on all plans —
verified 2026-06-10). Current ops-mail volume is ≪100/day; the probe adds
1/day. Upgrade trigger unchanged ($20/mo at volume). The summarizer adds one
Anthropic `messages.create` call per non-statutory inbound email under the
Jikigai key, bounded by the daily LLM-call ceiling. Option B (paid
shared-inbox vendor) was rejected partly on this line item.

## NFR Impacts

- **NFR-013 (Synthetic Monitoring):** improved — the daily probe is true
  end-to-end synthetic coverage of an external chain (Proton → Resend →
  webhook → Inngest → DB), asserted same-run.
- **NFR-003 (Service-Level Monitoring):** improved — Sentry cron monitor on
  the probe; webhook failures mirror to Sentry per
  `cq-silent-fallback-must-mirror-to-sentry`.
- **NFR-025 (Rate Limiting):** improved on this surface — 413 size cap before
  verify, Inngest throttle, daily LLM ceiling.
- **NFR-040 (Data Retention Policy):** implemented for this surface — probe
  rows 7d, non-statutory rows 365d, statutory rows held for the
  accountability period, `processed_resend_events` 90d (pg_cron, mig-094
  pattern).

## Principle Alignment

- **AP-001 (Terraform-only infrastructure provisioning): Deviation —
  documented exception.** The Resend webhook and the domain's
  `capabilities.receiving` flag are provisioned by the idempotent operator
  script `apps/web-platform/infra/resend-inbound-bootstrap.sh`, not Terraform,
  because **no Resend Terraform provider exists** (verified at plan time via
  registry search). The script is the secret-minting step: it writes the svix
  signing secret straight into Doppler (never tfstate, AP-008-aligned) and
  prints the DNS record set. Everything Terraform CAN own stays in Terraform:
  the inbound DNS records in `apps/web-platform/infra/dns.tf` (authored from
  the bootstrap output) and the Sentry cron monitor in
  `apps/web-platform/infra/sentry/cron-monitors.tf`. The deviation collapses
  the day a Resend provider ships.
- **AP-009 (Never delete user data): Deviation — documented carve-out.** The
  retention purge (`purge_email_triage_items()`) DELETEs triage rows: this is
  not data loss but GDPR Art. 5(1)(e) storage-limitation compliance — third-
  party correspondents' personal data may not be kept indefinitely. Statutory
  rows (DSAR / breach / service-of-process / regulator) are exempt from the
  purge for the accountability period under Art. 17(3)(b) (the predicate keys
  on `statutory_class IS NULL` — the provenance column the LLM structurally
  cannot write). Deletion is possible ONLY via the GUC-gated `SECURITY
  DEFINER` RPC (mig-087 pattern; the WORM trigger rejects all other DELETEs),
  so every purge is an auditable, named code path — and the Proton keep-copy
  means no original is ever destroyed.
- **AP-012 (New vendor checklist): N/A** — Resend is an existing vendor; the
  inbound scope amendment is recorded against PA-27 in the Art. 30 register.
- **AP-005 (Email for ops): Aligned** — probe and notification email ride the
  existing `notifications@soleur.ai` outbound surface.
