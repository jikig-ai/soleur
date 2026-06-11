---
title: "feat: operator inbox delegation — read-only email triage (3rd ingress)"
type: feat
date: 2026-06-10
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5103
spec: knowledge-base/project/specs/feat-operator-inbox-delegation/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-10-operator-inbox-delegation-brainstorm.md
reviewed: 2026-06-10 (DHH + code-simplicity + spec-flow applied; Kieran agent hit session limit — its two load-bearing checks executed directly: resend@6.12.3 exposes webhooks.verify (index.d.mts:2108), svix@1.92.2 installed)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: Operator Inbox Delegation — Read-Only Email Triage

## Overview

Agents triage inbound email to `ops@soleur.ai` instead of the operator. Pipeline:
Proton Sieve auto-forward (**keep local copy** — the Proton mailbox remains the
archival home of original mail) → Resend Inbound (`inbound.soleur.ai`, 3rd
multi-source ingress alongside Stripe/GitHub per ADR-036 lineage) → svix-verified
webhook → Inngest. Statutory-class mail (DSAR / breach / service-of-process /
regulator) is detected by a **deterministic, metadata-first, pre-LLM fast-path** and
escalated with the clock stated; everything else gets a read-only LLM summary
(sanitized input, no tools, parse-and-discard) surfaced as items in the existing
conversation inbox with a push-notification ping. Items carry an
acknowledge/archive lifecycle so the pinned statutory slot keeps its signal value. A
daily synthetic probe email exercises the full chain end-to-end and asserts its own
completion (same-run `step.sleep`). The GDPR bundle (Art. 30 PA row, LIA, DPIA
screening memo, policy lockstep, Anthropic + Resend DPA scope amendments) ships in
the same PR.

Overrides recorded: this implements the operator-dogfood slice that explicitly
overturns the #4788 deferral (override comment posted on #4788; conditions 2+3
satisfied by design, condition 1 operator-overridden). Draft PR: #5125.

**Premise Validation:** all cited references verified this session — #5103 OPEN,
#4788 OPEN (override recorded), #4671/#4672 OPEN (constraints honored: no LLM act
path, no send authority), #1690 CLOSED (conversation inbox shipped — landing surface
exists). Issue-body premises corrected at brainstorm: Proton has no JMAP/OAuth/API;
IMAP requires Bridge (send-capable credential) — forwarding architecture chosen
instead. No stale premises remain.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality (verified 2026-06-10) | Plan response |
|---|---|---|
| FR2: "dedup via migration-052 `messages.source_ref` primitive" | mig 052's primitive is on `messages` (draft-scoped partial-unique). Triage items are NOT outbound drafts — forcing them into `messages` would make them reachable by send/approve routes | Mirror the *pattern*, not the table: `processed_inbound_emails(svix_id)` plain-insert dedup in the route **with the GitHub route's release-on-failure step** (`webhooks/github/route.ts` Step 8 — without it a transient `inngest.send` failure after the dedup insert makes Resend retries 200 as "duplicate" and the email is dropped forever) + claim-insert on `message_id` as the pipeline's first step (graceful short-circuit on conflict) |
| "Parse-and-discard keeps third-party PII out at rest" | True for OUR storage. But Resend retains received email content **30 days, all plans, no DELETE endpoint exists** ([pricing](https://resend.com/pricing) + API index, fetched 2026-06-10) | Art. 30 PA row discloses BOTH 30-day windows (Resend + Anthropic); `email_triage_items` schema has **no body column** (structural guarantee); the Proton mailbox local copy (Sieve keep) is the durable original |
| Open Q1: "server-side Slack vs web push" | Zero server-side Slack code exists; `server/notifications.ts:99 notifyOfflineUser` implements WS > web-push > email hierarchy — **but `NotificationPayload` is hardcoded to `{type: "review_gate"; conversationId; ...}` with deep link `/dashboard/chat/{conversationId}`** (notifications.ts:32-37,146) | Reuse the hierarchy, but the payload widening is **unconditionally required**: discriminated-union `email_triage` variant deep-linking to the triage detail page, swept per `cq-union-widening-grep-three-patterns` + `tsc --noEmit` exhaustiveness; email-fallback link parity |
| "Resend Inbound webhook delivers the email" | Webhook is **metadata-only**: "Webhooks do not include the email body, headers, or attachments" ([docs](https://resend.com/docs/webhooks/emails/received)). Body via `GET /emails/receiving/{id}` | Statutory check runs on webhook metadata (subject + sender) BEFORE the body fetch; body fetched transiently for the body-text statutory pass + summary, never persisted |
| "Webhook secret provisioned in dashboard" | Fully API-provisionable: `POST /domains` accepts `capabilities.receiving`, `POST /webhooks` returns `signing_secret` ([docs](https://resend.com/docs/api-reference/webhooks/create-webhook)) | Idempotent bootstrap script `infra/resend-inbound-bootstrap.sh`, run BEFORE merge (it mints the MX value + secret the Terraform apply consumes) |
| Open Q3: sender scoping allowlist-first vs all-mail | ops@ is a NEW address; its senders are exactly the long tail we migrate there (#5135) — an allowlist recreates the per-sender onboarding bottleneck. Also: Sieve forwarding strips original sender authentication, so any sender-derived trust signal is spoofable | **Resolved: all-mail.** Statutory fast-path scans everything; LLM is read-only/no-tools so unknown-sender injection is bounded to a misleading summary. **No `sender_known` badge** (review-cut: spoofable trust signal, no source of truth — operator stays uniformly skeptical) |
| LLM client availability | `@anthropic-ai/sdk@^0.92.0` in `apps/web-platform/package.json:61`; direct-call Inngest-cron precedent: `server/inngest/functions/cron-compound-promote.ts` | Summarizer copies the cron-compound-promote client/model shape (verify at Phase 0) |
| Open Q4: supersede vs amend old spec | `feat-inbound-email-action-bus/spec.md` Non-Goals prohibit exactly this; its buy-path FRs already shipped (`dns.tf:91-94` multi-rua confirmed) | **Amend**: mark `status: superseded-in-part`, note buy-path shipped + pointer to this spec |

## User-Brand Impact

(Carried forward from brainstorm `## User-Brand Impact` — locked, do not re-author.)

- **If this lands broken, the user experiences:** statutory-clock mail (DSAR Art. 12,
  breach Art. 33, service of process) silently mis-triaged or a silent ingestion
  outage — the operator believes the agent watches the inbox while deadline-bearing
  mail rots, with a WORM audit trail proving the system received it.
- **If this leaks, the user's data is exposed via:** inbound senders' PII (involuntary
  data subjects, special-category content will arrive) transiting Resend (30-day
  retention), Anthropic (30-day default retention), and our summaries; or PII leaking
  into observability sinks (Sentry/Better Stack), falsifying sub-processor disclosures.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: CPO assessed at brainstorm (Phase 0.5 + override decision);
`user-impact-reviewer` runs at review time per review/SKILL.md conditional block.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/dns.tf`: add `cloudflare_record` MX for
  `inbound.soleur.ai` (value/priority from the Resend Domains API response, minted by
  the bootstrap script which runs FIRST — see Apply path). Use FQDN, never `@`.
  **Additive-only diff**; zero change to apex Proton MX/SPF/DKIM/`_dmarc` (spec TR1,
  brand-critical — same root as Proton mail).
- `apps/web-platform/infra/sentry/cron-monitors.tf`: add `sentry_cron_monitor` for
  `cron-email-ingress-probe` — daily schedule, **checkin margin 60 min** (paired with
  the probe's pinned 15-min in-run SLA; one constant, two sites, both stated here so
  they cannot be invented independently).
- Sensitive variables: `TF_VAR` flow unchanged; canonical invocation triplet per the
  drift-runbook Sharp Edge (AWS R2 exports + `terraform init` + `doppler run -p soleur
  -c prd_terraform --name-transformer tf-var -- terraform plan`).
- Secrets (Doppler `prd`): `RESEND_INBOUND_WEBHOOK_SECRET` (svix `whsec_...`, returned
  by `POST /webhooks`), `EMAIL_TRIAGE_OWNER_USER_ID` (the founder user UUID — triage
  rows are RLS-scoped to this user; the pipeline **fails loud to Sentry and skips
  processing** if unset or not matching a `users` row). Prod Doppler writes go through
  the existing prod-write defer-gate with explicit ack.

### Apply path

Cloud-init not applicable (no new host). **Order fixed at plan-review (DHH P0 — the
previous order consumed the MX value before it existed):**

1. *(pre-merge)* Execute the idempotent `resend-inbound-bootstrap.sh`: enables
   `capabilities.receiving` on the domain via the Domains API, creates the
   `email.received` webhook pointing at
   `https://app.soleur.ai/api/webhooks/resend-inbound`, prints the `signing_secret` +
   MX value. Safe before code ships: a webhook pointing at a 404 route just retries
   (5s→10h schedule), and no mail flows until the Sieve rule exists. This also makes
   AC9's `terraform plan` checkable in the PR.
2. Store the two Doppler secrets (prod-write defer-gate ack).
3. Merge → release pipeline restarts the container (route live); migration applies
   via the pipeline.
4. `terraform apply` (DNS MX with the now-known value + Sentry monitor) via the
   existing apply path.
5. Proton-side config (see non-IaC remainder below), then probe verification.

### Distinctness / drift safeguards

- dev ≠ prd: webhook + domain capability provisioned for prd only in this increment;
  dev uses test fixtures (no live inbound). `hr-dev-prd-distinct-supabase-projects`
  honored — migration applies to both via the standard pipeline.
- Secret values land in Doppler, not tfstate (webhook created by API script, not TF —
  no Resend Terraform provider exists; verified via registry search at research time).

### Vendor-tier reality check

Resend inbound is included on ALL plans including free ("All plans include: …
inbound emails" — [pricing](https://resend.com/pricing), fetched 2026-06-10). Free
tier: 3,000 emails/mo, 100/day, 1 domain — soleur.ai is already the verified domain;
receiving is a capability flag on it. Whether inbound counts against the monthly
quota is undocumented — at current ops-mail volume (≪100/day) this is immaterial;
the probe adds 1/day.

### Genuinely non-IaC remainder (no API exists — verified)

Proton Workspace exposes no public API or Terraform provider for address creation or
Sieve filters (verified at brainstorm; learning
`2026-06-10-proton-capability-facts-and-deferral-override-recording.md`). The two
Proton-side steps — create `ops@soleur.ai` additional address ($0, included) and the
Sieve auto-forward rule to the Resend address — are in-product Proton admin config,
executed in-session via Playwright browser automation up to any CAPTCHA/login gate
(`hr-exhaust-all-automated-options-before`), then verified end-to-end by the probe.
**The Sieve rule MUST forward-and-keep (never redirect-and-discard):** the Proton
mailbox local copy is the only durable original once Resend's 30-day window closes,
and it is the operator's recovery path when a summary is insufficient (the detail
view's honesty notice states this).

## Observability

```yaml
liveness_signal:
  what: "daily synthetic ingress probe — cron-email-ingress-probe sends a marker email via Resend outbound to ops@soleur.ai, step.sleeps 15 min, then asserts ITS OWN row landed (same-run assertion — no previous-run bookkeeping, no first-run ambiguity); Sentry cron monitor asserts the check-in"
  cadence: "daily; in-run SLA 15 min; monitor checkin margin 60 min"
  alert_target: "Sentry issue alert → founder email (existing alert routing)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf + apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "webhook route returns 401 on svix-verify failure and 500 on dedup-insert failure (GitHub-route precedent incl. release-on-failure), both mirrored to Sentry; Inngest pipeline failures exhaust retries then captureException with op tags; notifyOfflineUser failure on a STATUTORY item mirrors to Sentry (cq-silent-fallback-must-mirror-to-sentry — the existing log-only catch is insufficient for FR3 fail-loud); owner-env misconfiguration mirrors to Sentry (no PII in payloads per TR3)"

failure_modes:
  - mode: "Sieve forward silently broken / Proton address deleted (quiet mailbox indistinguishable from broken chain)"
    detection: "daily probe fails its own 15-min assertion → failed Sentry check-in → monitor alert"
    alert_route: "Sentry monitor alert → founder email"
  - mode: "webhook signing-secret drift (rotation, re-created webhook)"
    detection: "401 responses mirrored to Sentry as tagged events; Resend retries (5s→10h schedule) keep events replayable"
    alert_route: "Sentry issue alert"
  - mode: "Resend body-fetch failures (GET /emails/receiving/{id} 5xx)"
    detection: "Inngest step retries; terminal failure → Sentry captureException tagged feature:email-triage op:body-fetch; statutory metadata-matches still produce a degraded row + ping BEFORE the fetch, so a DSAR is never silently dropped by a fetch failure"
    alert_route: "Sentry issue alert"
  - mode: "Inngest function not registered / cron dark"
    detection: "EXPECTED_CRON_FUNCTIONS registry test fails at CI; cron-inngest-cron-watchdog covers runtime desync"
    alert_route: "CI failure pre-merge; watchdog Sentry heartbeat post-merge"

logs:
  where: "pino → journald → Better Stack (PII-stripped: no raw bodies, no sender values per TR3)"
  retention: "Better Stack free-tier window (post-#5105 reduced volume)"

discoverability_test:
  command: "/soleur:trigger-cron email-ingress-probe (POST /api/internal/trigger-cron, no remote shell) then read the probe row via GET /api/inbox/emails?include_probes=1 (probe rows are excluded by default; the explicit param resolves the visibility contradiction)"
  expected_output: "probe completes the loop within 15 min; probe-marked row visible with include_probes=1; Sentry monitor shows OK check-in"
```

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/102_email_triage_items.sql` (+ `.down.sql`) | `email_triage_items` (NO body column — structural parse-and-discard). Columns: `id, user_id (FK users ON DELETE CASCADE), message_id (UNIQUE), resend_email_id, sender (raw From header value), subject, summary, mail_class, statutory_class (nullable — non-NULL ⟺ deterministic-path provenance; LLM can never write it), rule_id (nullable — matched statutory rule, renders in detail view), status ('new'∣'acknowledged'∣'archived'), status_changed_at, received_at (WORM — sourced from the RESEND EVENT PAYLOAD receive timestamp, never insert time: a 10h webhook retry must not eat an Art. 12 clock), created_at`. WORM trigger (precedent: mig 075 `workspace_invitations_no_mutate`) freezes content fields (`message_id, sender, subject, summary, mail_class, statutory_class, rule_id, received_at`) while ALLOWING `status`/`status_changed_at` updates. PII columns carry `-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA per Phase 7)` annotations (gdpr-gate). Plus `processed_inbound_emails(svix_id)` dedup table (precedent: `processed_github_events`, mig 052) |
| `apps/web-platform/server/email-triage/statutory-rules.ts` | Code-static rule registry: `{ruleId, class, senderPatterns, keywordPatterns, dueRule (e.g. calendar-month for DSAR per Art. 12(3), 72h for breach), catalogAnchor, catalogExcerpt}` for DSAR / breach / service-of-process / regulator / probe-marker; **deterministic first-match priority order** (breach > service-of-process > DSAR > regulator > probe) for multi-class emails; pure function, no I/O. Clock display derives from `received_at` + registry `dueRule` — no clock columns in the DB (registry is the single system-of-record for statutory periods) |
| `apps/web-platform/server/email-triage/summarize.ts` | Read-only LLM summarizer: sanitization parity (`sanitizePromptString` treatment incl. `\x7f`, U+2028/U+2029 — precedent `server/soleur-go-runner.ts`), direct `@anthropic-ai/sdk` call (client/model shape copied from `cron-compound-promote.ts`), prompt instructs omission of special-category personal details (gdpr-gate Art. 9 note). **Output `mail_class` is validated against a closed allowlist (`vendor∣billing∣security∣newsletter∣legal-review∣other`) that excludes ALL statutory classes and `probe`** — the LLM structurally cannot forge a statutory appearance or hide mail as a probe; out-of-allowlist output coerces to `other` + Sentry tag |
| `apps/web-platform/app/api/webhooks/resend-inbound/route.ts` | 3rd ingress: raw-body read (`await req.text()` BEFORE parse — svix requirement), verify via installed `resend.webhooks.verify` (resend@6.12.3, index.d.mts:2108; svix@1.92.2 available for in-test signature computation) → 401 on fail; `processed_inbound_emails` plain-insert dedup (500 on insert failure, NO ON CONFLICT — GitHub-route precedent incl. supabase-js `data:null` quirk) **+ release-on-failure: if the subsequent `inngest.send` fails, DELETE the dedup row before returning 500 so Resend's retry is not swallowed as a duplicate** (GitHub route Step 8); emit Inngest event `email/received` with metadata |
| `apps/web-platform/server/inngest/functions/email-received-triage.ts` | Pipeline, in order: (1) claim-insert stub row keyed on `message_id` (ON CONFLICT short-circuit — graceful duplicate handling, no retry-to-terminal-error); (2) **statutory check on webhook METADATA (subject + sender) — before any body fetch**; metadata-match → finalize statutory row (+ rule_id, received_at from payload) + notify + return (LLM and body fetch unreachable; a fetch outage can only degrade the row, never drop the DSAR); (3) body fetch (`GET /emails/receiving/{id}`); (4) body-text statutory pass (body-only matches); (5) sanitize → summarize (allowlist-validated) → finalize row → notify. Body discarded — never persisted, never logged. `notifyOfflineUser` failures on statutory items mirror to Sentry. Owner-env unset/invalid → Sentry + skip |
| `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` | Daily: send marker email (Resend outbound `notifications@soleur.ai` → `ops@soleur.ai`) → `step.sleep` 15 min → assert THIS run's probe row exists → Sentry cron check-in (fail check-in otherwise). Same-run assertion: no previous-run bookkeeping, manual-trigger works standalone. Probe rows: matched by the deterministic probe rule before the LLM (zero Anthropic calls), excluded from the default list, `mail_class='probe'`. Also runs the Art. 5(1)(e) retention purge: DELETE probe rows > 7 days and non-statutory items > 365 days (statutory items retained per the PA-row accountability period) |
| `apps/web-platform/app/api/inbox/emails/route.ts` | List triage items (RLS-scoped): full rows (they are small by construction — no body), unacknowledged statutory pinned first; excludes probe rows unless `?include_probes=1`; excludes `archived` unless `?status=archived` |
| `apps/web-platform/app/api/inbox/emails/[id]/status/route.ts` | PATCH only: `new → acknowledged∣archived` transitions (statutory: acknowledge; standard: archive). HTTP-only exports. **No detail GET route** (review-cut): the detail page is a server component querying Supabase directly |
| `apps/web-platform/components/inbox/email-triage-row.tsx` | List rows per wireframes `knowledge-base/product/design/inbox/operator-email-triage.pen`: standard row (class pill, summary, sender, received-at, Archive action) + statutory variant (pinned while unacknowledged, red accent, inline due-date derived from `received_at` + registry `dueRule`, Acknowledge action — acknowledgment unpins but the item stays visible with its clock; acknowledgment is workflow state, NOT legal resolution, stated in the UI) |
| `apps/web-platform/app/(dashboard)/dashboard/inbox/email/[id]/page.tsx` | Detail views per wireframes (server component, direct Supabase query; stable deep-link target for the push ping): read-only; headers shown = sender/subject/received-at/message-id (FR6 wording aligned — full headers are NOT persisted; SPF/DKIM/DMARC badges from the wireframe render ONLY if the Resend received-email payload exposes auth results for forwarded mail — Phase 0 check; omit otherwise); honesty notice states the body was discarded AND that the original is retained in the Proton ops@ mailbox; statutory: due-date block + matched `rule_id` + inline `catalogExcerpt` + link to the legal-threshold catalog entry |
| `apps/web-platform/infra/resend-inbound-bootstrap.sh` | Idempotent: enable `capabilities.receiving`, create `email.received` webhook, print `signing_secret` + MX value; `set -euo pipefail`, stdout for action signals |
| `apps/web-platform/test/server/resend-inbound-route.test.ts` | Svix-verify (deterministic — direct route invocation with svix-lib-computed signatures, NO LLM in assertion path), dedup 500-path, **release-on-failure path (inngest.send throws → dedup row deleted → 500)**, malformed payload |
| `apps/web-platform/test/server/statutory-rules.test.ts` | Synthesized fixtures only (`cq-test-fixtures-synthesized-only`): DSAR/breach/SoP/regulator positives (subject-only, body-only, multi-class priority), vendor-mail negatives, probe marker |
| `apps/web-platform/test/server/email-received-triage.test.ts` | Pipeline: metadata statutory match produces row + notify with **body fetch never called**; body-fetch terminal failure after metadata match still yields the statutory row (degraded); statutory short-circuits LLM (Anthropic mock: zero calls); duplicate `message_id` short-circuits gracefully (no error); sanitization applied; LLM `mail_class` allowlist coercion; no insert payload or log call contains body text; statutory notify failure mirrors to Sentry |
| `apps/web-platform/test/components/inbox/email-triage-row.test.tsx` | Row variants render; statutory pinned-first while unacknowledged; acknowledge/archive actions fire the PATCH |
| `knowledge-base/legal/` LIA + DPIA screening memo (directory + topic only; exact filenames at write time — match the existing LinkedIn-Page LIA + PA-22 brief conventions, locate via grep at Phase 0) | FR8 legal bundle artifacts |
| ADR via `/soleur:architecture` ("Inbound email ingress: Proton auto-forward → Resend Inbound — 3rd multi-source ingress") | CTO-recommended decision record alongside ADR-036; one sentence records that forwarded-mail sender identity is unauthenticated (Sieve forwarding strips SPF/DKIM context) so no future feature may derive trust from `sender` |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/dns.tf` | + MX `inbound.soleur.ai` (additive-only; TR1 single-purpose diff; value minted by the pre-merge bootstrap run) |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | + monitor for `cron-email-ingress-probe` (daily, 60-min margin) |
| `apps/web-platform/server/inngest/cron-manifest.ts` | + `cron-email-ingress-probe` in `EXPECTED_CRON_FUNCTIONS` + manual-trigger event |
| Inngest function registry (locate at Phase 0) | register `email-received-triage` + probe cron |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | render email-triage rows in the inbox list (unacknowledged statutory pinned first) |
| `apps/web-platform/server/notifications.ts` | **Unconditional (spec-flow P1):** widen `NotificationPayload` to a discriminated union with an `email_triage` variant `{type: "email_triage"; emailId; title; isStatutory}`; deep link `/dashboard/inbox/email/{emailId}` (current shape hardcodes `conversationId` + `/dashboard/chat/` at notifications.ts:32-37,146 — reused as-is the ping dead-links). Sweep ALL consumers via `tsc --noEmit` TS2322 rails + `cq-union-widening-grep-three-patterns` (`.type === "`, `?.type === "`, `_exhaustive: never`); email-fallback link parity; statutory-path failures mirror to Sentry |
| `apps/web-platform/.env.example` | + `RESEND_INBOUND_WEBHOOK_SECRET`, `EMAIL_TRIAGE_OWNER_USER_ID` |
| `apps/web-platform/server/dsar-export-allowlist.ts` (verify filename at Phase 0) | + `email_triage_items` (Art. 20 export scope; gdpr-gate) |
| `knowledge-base/legal/article-30-register.md` | + new PA row (next free PA number — grep `^## Processing Activity` tail before naming; Anthropic + Resend recipients, both 30-day windows disclosed, retention cells: probe 7d / non-statutory 365d / statutory per accountability period; TOMs incl. statutory fast-path + WORM + Art. 9 summarizer-prompt omission) |
| `knowledge-base/legal/data-processing-agreements/anthropic.md` | scope-cell amendment (+ email-triage purpose); §(g) residual-risk names prompt-injection honestly (precedent #4954) |
| Resend vendor DPA row (locate at Phase 0 — `compliance-posture.md` Vendor DPA table and/or `data-processing-agreements/resend.md`) | scope amendment: Resend now custodian of inbound raw third-party mail, 30-day retention, no delete API (gdpr-gate Chapter V finding) |
| `knowledge-base/legal/compliance-posture.md` | Active Items update per gdpr-gate output |
| `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/` mirrors | lockstep: AI-assisted triage of mail to company addresses disclosed; Art. 14(5)(b) notice |
| `knowledge-base/project/specs/feat-inbound-email-action-bus/spec.md` | `status: superseded-in-part` + pointer note (buy path shipped `dns.tf:94`; the operator slice is now `feat-operator-inbox-delegation`) |
| `knowledge-base/project/specs/feat-operator-inbox-delegation/spec.md` | FR6 wording fix (persisted = summary, subject, sender, received-at, message-id — NOT full headers; prevents a reviewer "fixing" it with a JSONB headers column); + FR9 item lifecycle (acknowledge/archive); FR3 notes metadata-first ordering; AC3's negative dead-man test restored (see AC-P3) |

## Implementation Phases

Ordering is dependency-directed (contract before consumer). Every code phase is
RED-first (`cq-write-failing-tests-before`).

**Phase 0 — Preconditions (verify, pin results in tasks.md):**
1. Read `cron-compound-promote.ts` client construction + model choice; the summarizer copies it. Read one `cron-*.ts` + locate the Inngest function registry array (the 6 cron test gotchas).
2. Read mig 075 `workspace_invitations_no_mutate` + mig 052 + the 2 most recent migrations (transactional runner — no `CREATE INDEX CONCURRENTLY`).
3. `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3` — next free PA number; locate the Resend vendor DPA row; locate the LIA precedent (`git grep -ln "legitimate interest" knowledge-base/legal/ | head`); verify `dsar-export-allowlist.ts` filename.
4. Live-probe the Resend API forms used by the bootstrap script AND fetch one received-email payload shape to check whether auth results (SPF/DKIM) are exposed for forwarded mail (decides the detail-view badges) and confirm the receive-timestamp field name for `received_at`.
5. Confirm `resend.webhooks.verify` usage shape against the installed package (pinned: resend@6.12.3 index.d.mts:2108; svix@1.92.2 present).

**Phase 1 — Migration:** failing tests for the WORM trigger (content fields frozen, status fields mutable), UNIQUE(message_id), CASCADE, RLS shape (read-only `pg_policy` assertions), then `102_email_triage_items.sql` + down (column list + annotations per Files to Create).

**Phase 2 — Statutory rules (contract):** RED fixtures (subject-only, body-only, multi-class priority, probe, vendor negatives) → `statutory-rules.ts` with `ruleId`/`dueRule`/`catalogExcerpt` and first-match priority order.

**Phase 3 — Webhook route:** RED (svix verify 401, dedup 500, release-on-failure, happy-path event emit) → `resend-inbound/route.ts`. Deterministic tests: direct route invocation with svix-computed signatures — no LLM anywhere near the assertion path.

**Phase 4 — Inngest pipeline + notification widening:** RED → `email-received-triage.ts` (claim-insert → metadata statutory → body fetch → body statutory → sanitize → allowlist-validated summarize → finalize → notify) and the `NotificationPayload` discriminated-union widening in `notifications.ts` (consumer sweep via `tsc --noEmit`; statutory-failure Sentry mirror). Mock the Anthropic client throughout.

**Phase 5 — API routes + UI:** RED component tests → `email-triage-row.tsx`, detail page (server component), list route + status PATCH route, dashboard wiring. Match wireframe frames 05-08 minus the review-cut badge; theme tokens, no literal hex.

**Phase 6 — Liveness probe + IaC:** probe cron (same-run assertion + retention purge) + cron-manifest + Sentry monitor TF + dns.tf MX + bootstrap script. Registry-count test updated.

**Phase 7 — Legal bundle + ADR + doc amendments:** invoke `legal-document-generator` (PA row, LIA, DPIA screening memo, lockstep policy edits, Anthropic + Resend scope cells), then `legal-compliance-auditor` cross-consistency pass (both inline at /work per `wg-plan-prescribed-skills-must-run-inline`; output marked draft-requiring-professional-review). `/soleur:architecture` ADR; supersede-in-part note on the old spec; this spec's FR6/FR9 amendments; `.env.example`.

### Post-merge sequence

(Bootstrap + Doppler secrets happen PRE-merge per the Apply path above.)

1. *(automated)* Release pipeline restarts the container; migration applies via the pipeline.
2. *(automated via ship)* `terraform apply` (DNS + Sentry monitor) through the existing apply path.
3. *(in-session browser automation)* Proton admin: create the `ops@soleur.ai` address + Sieve **forward-and-keep** rule to the Resend inbound address. Automation: Playwright up to the Proton login/CAPTCHA gate; `Automation: not feasible beyond the auth gate because Proton has no API` (verified).
4. *(automated)* Fire `/soleur:trigger-cron email-ingress-probe`; verify the probe row (`?include_probes=1`) + Sentry check-in (AC-P3 positive arm).
5. *(one-time chaos check — restores spec AC3's negative invariant)* Temporarily disable the Sieve rule (or fire the probe with a corrupted marker), confirm the missed/failed check-in actually raises the Sentry alert → founder email, then re-enable. A green check-in alone proves the happy chain, not the alert path.
6. Send a synthetic DSAR-keyword email to ops@; verify pinned statutory item + push ping deep-links to the detail page, with zero LLM calls (the pre-merge mock test is the invariant of record; the log-op-tag absence check here is corroboration only).
7. `gh issue close 5103` after AC-P1..P3 pass (PR body uses **`Ref #5103`**, not `Closes` — post-merge provisioning gates the actual resolution, ops-remediation pattern).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** Migration: `email_triage_items` has NO body/html/raw column (grep of the migration file for `body|html|raw_content` returns only comments); WORM trigger blocks UPDATE of content fields (test expects `P0001`-class rejection) while allowing `status` transitions; UNIQUE(message_id) enforced; `user_id` FK has `ON DELETE CASCADE`; RLS policy present (`pg_policy` shape test); `LAWFUL_BASIS` annotations present on PII columns.
- [ ] **AC2** Webhook route: invalid/missing svix signature → 401; dedup-insert failure → 500; `inngest.send` failure → dedup row released + 500 (release-on-failure test); valid request emits exactly one `email/received` event. All tests invoke the route directly with synthetic signatures (no LLM, no network).
- [ ] **AC3** Statutory fast-path: (a) subject-metadata DSAR fixture produces a statutory row + notify with the body fetch **never invoked**; (b) body-fetch terminal failure after a metadata match still yields the (degraded) statutory row; (c) Anthropic mock asserts zero invocations on every statutory path; (d) statutory `notifyOfflineUser` failure mirrors to Sentry; (e) due date renders as a calendar-month computation from `received_at` per registry `dueRule` (not a naive +30d when the rule says calendar month).
- [ ] **AC4** Summarizer: input passes through sanitization (test asserts `\x7f`/U+2028/U+2029 stripped before the mocked client sees it); LLM `mail_class` output outside the closed allowlist coerces to `other` (statutory classes + `probe` unreachable); no insert payload and no log call contains the fixture body string.
- [ ] **AC5** UI: email-triage row renders as a sibling of conversation rows; unacknowledged statutory pinned first with due-date text; Acknowledge (statutory) and Archive (standard) actions fire the PATCH and the list reflects the transition; detail view shows the parse-and-discard notice including the Proton-original pointer; tests under `apps/web-platform/test/components/inbox/` (vitest jsdom glob).
- [ ] **AC6** Cron registry: `EXPECTED_CRON_FUNCTIONS` count test passes with `cron-email-ingress-probe` added; manifest manual-trigger event present; retention purge covered by a unit test (probe >7d and non-statutory >365d deleted; statutory retained).
- [ ] **AC7** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (this is also the exhaustiveness enumerator for the `NotificationPayload` widening — every TS2322 never-rail widened); full suite green via the package's own runner.
- [ ] **AC8** Legal bundle committed and cross-consistent: new PA row (number verified free at write time, retention cells per plan), LIA, DPIA screening memo, lockstep edits in BOTH doc locations, Anthropic + Resend scope cells; `legal-compliance-auditor` pass recorded.
- [ ] **AC9** `terraform plan` (prd_terraform, canonical triplet) shows an additive-only diff: exactly the new MX record (value from the pre-merge bootstrap run) + new Sentry monitor; zero diff on apex Proton MX/SPF/DKIM/`_dmarc`.
- [ ] **AC10** ADR committed (incl. the unauthenticated-forwarded-sender sentence); old spec carries `superseded-in-part`; this spec carries the FR6/FR9 amendments; PR body uses `Ref #5103` + `## Changelog` + `semver:minor`.

### Post-merge

- [ ] **AC-P1** Bootstrap executed pre-merge (idempotency re-run is a no-op); secrets in Doppler; receiving enabled; webhook live.
- [ ] **AC-P2** Proton: `ops@soleur.ai` exists; Sieve **forward-and-keep** active (keep-copy verified — original visible in the Proton mailbox after a probe); ops@ is NOT a recovery/login address for any vendor in `knowledge-base/operations/expenses.md` (checklist swept).
- [ ] **AC-P3** Probe loop green AND alert path proven: manual-trigger probe produces a row within the 15-min SLA + OK check-in (positive arm); the one-time chaos check confirms a failed run raises the Sentry alert → founder email (negative arm — spec AC3 restored); synthetic DSAR email produces pinned statutory item + working deep-link ping with zero LLM involvement.
- [ ] **AC-P4** #5103 closed with verification evidence; the #4788 comment already records the override.

## Test Scenarios

- Given a forwarded vendor email, when the webhook fires, then a summarized item appears in the inbox with a class badge and the raw body exists nowhere in our DB or logs.
- Given an email whose SUBJECT contains DSAR-class keywords, when ingested, then the statutory row exists even if the body fetch fails terminally, the due date derives from the payload receive timestamp, and the Anthropic client was never invoked.
- Given the same `message_id` delivered twice (same or different svix ids), when both deliveries process, then exactly one item row exists and no terminal error is raised (claim-insert short-circuit).
- Given `inngest.send` fails after the dedup insert, when Resend retries, then the retry is processed (release-on-failure) rather than swallowed as a duplicate.
- Given a broken Sieve rule, when the daily probe runs, then the probe's own 15-min assertion fails, the Sentry check-in fails, and the monitor alert fires.
- Given a statutory item is acknowledged, then it unpins but remains visible with its clock, `received_at` unchanged (WORM holds through the status transition).
- Given an email with attachments, when ingested, then attachment metadata appears in the summary context and no attachment content is ever downloaded (v1 scope note below).
- **API verify:** `doppler run -p soleur -c prd -- curl -s -X POST https://app.soleur.ai/api/internal/trigger-cron ...` with `event=cron/email-ingress-probe.manual-trigger` → probe row via `GET /api/inbox/emails?include_probes=1`.

**v1 scope note — attachments:** the pipeline records attachment metadata (filename,
content_type) but NEVER downloads attachment content (the `download_url` is unused).
This removes the zip-bomb/XXE parser surface from v1 entirely (K6's hardened-parser
requirement attaches to the deferred attachment feature; tracking issue created at the
deferral sweep with re-evaluation criteria: first real ops-mail whose meaning lives in
an attachment).

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Operations (carried forward from brainstorm `## Domain Assessments`, 2026-06-10 — same session)

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Operator-self-use reduces but doesn't zero the load: new Art. 30 PA required (involuntary data subjects); DPIA → screening memo; one Art. 6(1)(f) LIA; three-document lockstep; Anthropic scope amendment; ZR disclose-and-launch (decision K6); statutory floor non-negotiable (carried into FR3/Phase 2); runtime escalations hard-link the legal-threshold catalog.

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Forwarding chain over Bridge/IMAP (no credential anywhere); 3rd-ingress precedent + dedup + cron substrate all exist; dominant risk is silent ingestion failure → probe + Sentry monitor (Phase 6); injection mitigated to read-only/no-tools; DNS low-risk additive on the brand-critical root; ADR required.

### Operations (COO)

**Status:** reviewed (carry-forward)
**Assessment:** $0 marginal (Proton address included; Resend inbound on the existing plan); paid shared-inbox + OAuth shapes rejected; companion increments #5134/#5135 filed; ledger hygiene flagged separately (not in this PR).

### Product/UX Gate

**Tier:** blocking (mechanical override: new `components/**/*.tsx` + dashboard page)
**Decision:** reviewed
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55 — committed `.pen`, 4 frames, page-design level not idea level), cpo (brainstorm + override decision; `requires_cpo_signoff: true` satisfied at plan time), spec-flow-analyzer (plan-review pass — P0/P1 findings folded throughout this revision: status lifecycle, metadata-first statutory ordering, notification payload widening, Sieve keep-copy, probe semantics)
**Skipped specialists:** none (no leader recommended copywriter)
**Pencil available:** yes
**Brainstorm-recommended specialists:** legal-document-generator + legal-compliance-auditor → scheduled as Phase 7 inline at /work (not skipped); `/soleur:architecture` → Phase 7; gdpr-gate → run at plan Phase 2.7 (4 Important findings folded); ux-design-lead → completed at brainstorm.

#### Findings

Wireframes cover both item classes incl. the statutory treatment and honesty notice.
spec-flow P0s (statutory acknowledge state, Archive writer-path, metadata-first
statutory check) and P1s (ping deep-link widening, Sentry mirror on statutory notify
failure, dead-man negative test, original-mail recovery path, dedup release-on-failure)
are folded into this revision. Wireframe deltas vs. plan: the `sender_known`-style
badge is cut (spoofable); SPF/DKIM/DMARC badges render only if the Resend payload
exposes auth results (Phase 0 check); Acknowledge action added to the statutory frames'
implementation (wireframe shows Archive on standard detail only — the `.pen` is not
re-opened for this addition; the row/detail components follow the existing frame
language).

## Open Code-Review Overlap

Checked 63 open `code-review` issues against the Files lists (2026-06-10):

- **#2590** (extract `useFirstRunAttachments` + `FirstRunComposer` from DashboardPage) touches `dashboard/page.tsx`, which this plan edits. **Acknowledge:** different concern (first-run composer extraction vs. adding inbox list rendering); folding a refactor into a brand-critical feature PR violates scope discipline. The scope-out remains open.
- **#3739** (extract `reportSilentFallbackWithUser` helper across webhook sites) overlaps the new `api/webhooks/resend-inbound` route conceptually. **Acknowledge:** the new route uses the existing `reportSilentFallback`/Sentry helper conventions so it is trivially migratable when #3739 lands; the 11-site extraction stays its own issue.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Statutory rule false-negative (DSAR phrased unusually) | Keyword set errs broad (recall over precision — a false positive costs one extra escalation); the LLM path ALSO labels legal-looking mail `mail_class: legal-review` as a second net (advisory only — allowlist-validated, it can never write `statutory_class`); rules reviewed in the legal-compliance-auditor pass |
| Prompt injection via email body | Read-only client, no tools, sanitization parity, summary rendered as plain text (no markdown execution surface in the row); LLM output constrained to the closed `mail_class` allowlist |
| Forwarded-mail SPF/ARC handling at Resend undocumented | Empirical: the post-merge probe IS the test (Proton-forwarded synthetic mail); if Resend drops forwards, the probe fails loudly on day one before any real mail depends on the chain |
| PII in observability | TR3: no body/sender values in pino/Sentry payloads; op-tags only; test asserts the log mock never sees the body fixture |
| Resend/Anthropic 30-day retention misrepresented in policies | PA row discloses both windows explicitly; legal-compliance-auditor cross-checks DPD claims |
| Webhook secret leak | Single rotatable svix secret; rotation = re-run bootstrap + Doppler update; no mailbox credential exists by design |
| Alarm fatigue on the statutory pin | Acknowledge transition unpins handled items (spec-flow P0); pin slot reserved for unacknowledged statutory only |
| Wrong/insufficient summary (incl. injection-distorted) | Detail view names the recovery path: original retained in the Proton ops@ mailbox (Sieve keep-copy mandated); `resend_email_id` stored for the 30-day Resend window |

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| IMAP polling via Proton Bridge | No read-only credential exists (send-capable, full-mailbox); unofficial images; egress widening — brainstorm K2 |
| OAuth into the operator's mailbox | Proton has no OAuth/API; legally rejected (CLO) |
| Paid shared inbox (Front/Missive) | $300-348/yr pre-revenue; new US sub-processor + DPA chain — brainstorm K12/COO |
| Items as `messages` drafts (literal mig-052 reuse) | Drafts are reachable by send/approve routes; read-only items must be structurally unsendable |
| New Slack server transport for pings | `notifyOfflineUser` hierarchy exists; YAGNI (the payload widening is required either way) |
| Single merged class enum (`mail_class` absorbing statutory values) | Rejected at review: `statutory_class IS NOT NULL` ⟺ deterministic-path provenance; merging would let LLM output forge statutory rows |
| Cutting `processed_inbound_emails` for Inngest idempotency keys | Rejected at review: route-level dedup stops duplicate deliveries before they cost a body fetch + LLM call + double ping; vendor idempotency semantics is the weaker guarantee at this threshold |
| `sender_known` badge | Cut at review: no source of truth, and Sieve forwarding makes sender identity an unauthenticated claim — a spoofable trust badge is worse than uniform skepticism |
| Attachment download + hardened parser in v1 | Removes the largest parser attack surface from v1; **deferred with a tracking issue** (created at the deferral sweep) |
| Draft-then-approve replies | Blocked on #4672; must reuse PR #4077 send invariants — already a spec Non-Goal |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  deepen-plan Phase 4.6 — the section above is carried from brainstorm, locked.
- `brand_survival_threshold: single-user incident` → **run `/soleur:deepen-plan` before
  `/work`** (exit-gate recommendation): plan-review (style/scope) is structurally blind
  to SQL atomicity, clock semantics, and security-primitive issues that the
  data-integrity-guardian + security-sentinel + architecture-strategist triad catches.
- The svix raw-body requirement (`await req.text()` before any parse) is load-bearing;
  a `req.json()` first read silently breaks verification.
- The Supabase migration runner is transactional — no `CREATE INDEX CONCURRENTLY`.
- Probe emails MUST short-circuit before the LLM (deterministic probe rule) or every
  probe burns an Anthropic call and pollutes the inbox.
- `received_at` comes from the RESEND EVENT PAYLOAD receive timestamp — never
  `now()` at insert. A 10-hour webhook retry must not eat an Art. 12 clock, and the
  WORM trigger makes a wrong value permanent.
- The WORM trigger is column-scoped: content fields frozen, `status`/`status_changed_at`
  mutable. A whole-row no-mutate trigger (the mig-075 shape verbatim) would break the
  acknowledge/archive lifecycle — adapt the trigger, don't copy it.
