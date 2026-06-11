# Tasks: Operator Inbox Delegation — Read-Only Email Triage

Plan: `knowledge-base/project/plans/2026-06-10-feat-operator-inbox-delegation-plan.md`
(post-review revision: DHH + code-simplicity + spec-flow applied; gdpr-gate folded).
Lane: cross-domain. Threshold: single-user incident (`requires_cpo_signoff` satisfied
at plan time). **Run `/soleur:deepen-plan` before starting Phase 1** (Sharp Edge).

## Phase 0 — Preconditions (pin every result here before coding)

- [ ] 0.1 Read `server/inngest/functions/cron-compound-promote.ts` — pin client construction + model for the summarizer; read one `cron-*.ts` + locate the Inngest function registry array (pin the 6 cron test gotchas)
- [ ] 0.2 Read migrations 075 (`workspace_invitations_no_mutate`), 052, and the 2 most recent — pin the trigger shape to adapt (column-scoped, NOT whole-row) and DDL constraints
- [ ] 0.3 Legal locations: next free PA number (`grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3`); Resend vendor DPA row location; LIA precedent file; `dsar-export-allowlist.ts` exact filename
- [ ] 0.4 Live-probe Resend API: bootstrap call shapes (`POST/PATCH /domains`, `POST /webhooks`); fetch one received-email payload — pin the receive-timestamp field name (feeds `received_at`) and whether auth results (SPF/DKIM) exist for forwarded mail (decides detail-view badges)
- [ ] 0.5 Confirm `resend.webhooks.verify` call shape against installed resend@6.12.3 (pinned: index.d.mts:2108; svix@1.92.2 present for test signatures)

## Phase 1 — Migration (RED → GREEN)

- [ ] 1.1 RED: tests — WORM trigger freezes content fields (`message_id, sender, subject, summary, mail_class, statutory_class, rule_id, received_at`) with `P0001`-class rejection; allows `status`/`status_changed_at`; UNIQUE(message_id); `user_id` FK ON DELETE CASCADE; `pg_policy` RLS shape
- [ ] 1.2 GREEN: `102_email_triage_items.sql` + `.down.sql` — 14 columns per plan (NO body column), `LAWFUL_BASIS` annotations on PII columns, `processed_inbound_emails(svix_id)` table
- [ ] 1.3 Add `email_triage_items` to the DSAR export allowlist

## Phase 2 — Statutory rules (contract first)

- [ ] 2.1 RED: synthesized fixtures — subject-only / body-only / multi-class priority (breach > SoP > DSAR > regulator > probe) positives, vendor negatives, probe marker
- [ ] 2.2 GREEN: `server/email-triage/statutory-rules.ts` — `{ruleId, class, senderPatterns, keywordPatterns, dueRule, catalogAnchor, catalogExcerpt}`, pure, code-static, first-match priority

## Phase 3 — Webhook route

- [ ] 3.1 RED: 401 on bad/missing svix signature (svix-lib-computed signatures, direct route invocation, no LLM/network); 500 on dedup-insert failure; release-on-failure (inngest.send throws → dedup row deleted → 500); happy path emits exactly one `email/received` event
- [ ] 3.2 GREEN: `app/api/webhooks/resend-inbound/route.ts` — raw `req.text()` BEFORE parse; `resend.webhooks.verify`; plain-insert dedup (NO ON CONFLICT, `data:null` quirk); release-on-failure

## Phase 4 — Pipeline + notification widening

- [ ] 4.1 RED: claim-insert short-circuit on duplicate `message_id` (graceful, no terminal error); metadata statutory match → row + notify with body fetch NEVER called; body-fetch terminal failure after metadata match → degraded statutory row persists; statutory paths: Anthropic mock zero calls; sanitizer strips `\x7f`/U+2028/U+2029 before mocked client; LLM `mail_class` outside allowlist coerces to `other`; no insert/log payload contains body fixture; statutory notify failure mirrors to Sentry; owner-env unset → Sentry + skip
- [ ] 4.2 GREEN: `server/inngest/functions/email-received-triage.ts` (order: claim-insert → metadata statutory → body fetch → body statutory → sanitize → summarize → finalize → notify; `received_at` from payload receive time; body discarded)
- [ ] 4.3 GREEN: `server/email-triage/summarize.ts` (client/model per 0.1; Art. 9 omission instruction; closed allowlist `vendor|billing|security|newsletter|legal-review|other`)
- [ ] 4.4 `notifications.ts`: widen `NotificationPayload` to discriminated union + `email_triage` variant (deep link `/dashboard/inbox/email/{emailId}`); sweep consumers via `tsc --noEmit` TS2322 rails + `cq-union-widening-grep-three-patterns`; email-fallback link parity; statutory-failure Sentry mirror
- [ ] 4.5 Register `email-received-triage` in the Inngest function registry

## Phase 5 — API + UI (wireframes: operator-email-triage.pen frames 05-08)

- [ ] 5.1 RED: component tests — row variants; unacknowledged statutory pinned first; due date derives from `received_at` + registry `dueRule` (calendar-month for DSAR); Acknowledge/Archive fire PATCH; detail shows parse-and-discard notice + Proton-original pointer
- [ ] 5.2 GREEN: `components/inbox/email-triage-row.tsx`; detail page `app/(dashboard)/dashboard/inbox/email/[id]/page.tsx` (server component, direct query — NO detail GET route); list route `app/api/inbox/emails/route.ts` (`?include_probes=1`, `?status=archived`); PATCH `app/api/inbox/emails/[id]/status/route.ts`
- [ ] 5.3 Dashboard wiring in `app/(dashboard)/dashboard/page.tsx`; theme tokens, no literal hex; no sender-trust badge (review-cut); SPF/DKIM badges only if 0.4 confirmed availability

## Phase 6 — Probe + IaC

- [ ] 6.1 `server/inngest/functions/cron-email-ingress-probe.ts`: send marker → `step.sleep` 15 min → assert OWN row → Sentry check-in; retention purge (probe >7d, non-statutory >365d, statutory retained); register + `EXPECTED_CRON_FUNCTIONS` + manual-trigger event; registry-count test
- [ ] 6.2 `infra/resend-inbound-bootstrap.sh` (idempotent; prints signing_secret + MX; `set -euo pipefail`)
- [ ] 6.3 `infra/dns.tf` MX `inbound.soleur.ai` (FQDN, additive-only) + `infra/sentry/cron-monitors.tf` monitor (daily, 60-min margin)
- [ ] 6.4 `.env.example`: `RESEND_INBOUND_WEBHOOK_SECRET`, `EMAIL_TRIAGE_OWNER_USER_ID`

## Phase 7 — Legal bundle + ADR + doc amendments

- [ ] 7.1 Invoke `legal-document-generator`: PA row (number per 0.3; Anthropic + Resend recipients; retention cells probe 7d / non-statutory 365d / statutory accountability period; TOMs), LIA, DPIA screening memo, Privacy Policy + DPD + GDPR Policy lockstep (BOTH doc locations), Anthropic scope cell + §(g), Resend scope amendment
- [ ] 7.2 Invoke `legal-compliance-auditor` cross-consistency pass; record result
- [ ] 7.3 `/soleur:architecture` ADR (3rd ingress; unauthenticated-forwarded-sender sentence)
- [ ] 7.4 Old spec `superseded-in-part` note; verify this spec's FR6/FR9 amendments committed
- [ ] 7.5 Deferral sweep: tracking issue for attachment download + hardened parser (re-evaluation: first real ops-mail whose meaning lives in an attachment)

## Exit (pre-merge)

- [ ] E.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; full suite green (package's own runner)
- [ ] E.2 Pre-merge bootstrap run (mints MX + secret) → Doppler (defer-gate ack) → `terraform plan` additive-only check (AC9)
- [ ] E.3 All AC1-AC10 verified; PR body `Ref #5103` + `## Changelog` + `semver:minor`

## Post-merge (sequence per plan)

- [ ] P.1 Pipeline deploy + migration (automated); `terraform apply` (automated via ship)
- [ ] P.2 Proton: ops@ address + Sieve **forward-and-keep** (Playwright to auth gate); recovery-address sweep vs expenses.md (AC-P2)
- [ ] P.3 Probe positive arm (`/soleur:trigger-cron email-ingress-probe` → row + check-in) AND negative chaos arm (disable Sieve once → alert fires → re-enable); synthetic DSAR email end-to-end with deep-link ping
- [ ] P.4 `gh issue close 5103` with evidence
