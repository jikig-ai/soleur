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
deepened: 2026-06-11 (10-agent pass — data-integrity, security, architecture, observability, test-design, user-impact, agent-native, patterns, learnings, verify-the-negative; 2 P0 design contradictions + 9 P1s folded; see Enhancement Summary)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: Operator Inbox Delegation — Read-Only Email Triage

## Enhancement Summary

**Deepened on:** 2026-06-11 (10 parallel agents: data-integrity-guardian, security-sentinel, architecture-strategist, observability-coverage-reviewer, test-design-reviewer, user-impact-reviewer, agent-native-reviewer, pattern-recognition-specialist, learnings-researcher, verify-the-negative sweep)

### Key corrections (load-bearing — the plan body below is already amended)

1. **P0 — WORM freeze vs stub→finalize contradiction resolved.** The original column-freeze list would have made the pipeline's own finalize UPDATE throw P0001 on 100% of emails. Replaced with an explicit per-column mutation matrix (see `## WORM Mutation Matrix`): hard-frozen vs one-time-set (NULL→value, mig 075 `accepted_at` shape). Stubs insert SQL NULL, never `''`.
2. **P0 — `ON DELETE CASCADE` + WORM contradiction resolved.** CASCADE either aborts the owner's Art. 17 deletion (if a no-delete trigger exists) or silently destroys statutory evidence. Now `ON DELETE RESTRICT` + GUC-gated anonymise RPC (mig 087 pattern — NOT `session_replication_role`, which is superuser-only on managed Supabase).
3. **Factual fixes:** the summarizer precedent is NOT `cron-compound-promote.ts` (it uses raw `fetch`, verified at `cron-compound-promote.ts:423-427`); SDK precedent is `agent-on-spawn-requested.ts`, mock precedent `test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts:198-203`. The sanitizer import is `sanitizePromptString` from `server/inngest/leader-prompts/prompt-assembly.ts:32` (exported, uncapped) — NOT the file-private 256-char-capped local in `soleur-go-runner.ts:1200`, which would truncate email bodies.
4. **TR3 was structurally violated by Layer 1:** the Inngest sentry-correlation middleware ships full event payloads (subject+sender) to Sentry as `extra` on every captured error; the key-name scrubber has no `subject`/`sender` keys. Fixed via `SENSITIVE_KEY_NAMES` additions + tri-ban (body, sender, subject) + Inngest event-store disclosure in the PA row.
5. **Webhook hardening parity:** fail-closed 500 on unset secret (verify() THROWS — it does not return false), 413 size cap before verify, `sendInngestWithRetry`, three-way dedup-release classification (transient→release+5xx; deterministically-unprocessable→keep+200; malformed→release+400), PUBLIC_PATHS registration (signature-authed routes 307 to /login otherwise).
6. **Statutory fast-path blind spots closed:** EN+FR keyword sets, HTML strip/decode before the body pass, attachment-filename keyword pass + thin-body+attachments escalation, `legal-review` distinct UI treatment, T-7d/T-2d deadline re-pin for acknowledged-but-unresolved statutory items.
7. **Agent-native parity:** the feature's premise is "agents triage email" yet shipped zero agent surface — added `server/email-triage-tools.ts` MCP tools (list/get, auto-approve tier) + prompt block; status writes stay UI-only in v1 (boundary written into FR9, honoring #4671/#4672).
8. **Naming/pattern fixes:** `processed_resend_events` (not `processed_inbound_emails`), `email-on-received.ts` (not `email-received-triage.ts`), event `email/inbound.received` + `v:"1"` + exported constant, POST `acknowledge`/`archive` subresources (not PATCH `/status`), `[emailId]` segment, happy-dom (not jsdom).
9. **DoS/abuse bounds added:** notification coalescing for statutory pings, Inngest throttle + daily LLM-call ceiling, per-run unguessable probe token (probe marker was a forgeable mail-suppression channel), fetched-body truncation cap.
10. **Five-registry lockstep + missing edits:** `.github/workflows/apply-sentry-infra.yml` `-target` line, `public/sw.js` notification-tag namespace (invisible to `tsc` — the planned sweep tooling cannot catch it), probe `retries: 0` (default retries silently turn a late probe into a green run).

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
| FR2: "dedup via migration-052 `messages.source_ref` primitive" | mig 052's primitive is on `messages` (draft-scoped partial-unique). Triage items are NOT outbound drafts — forcing them into `messages` would make them reachable by send/approve routes | Mirror the *pattern*, not the table: `processed_resend_events(svix_id)` plain-insert dedup in the route **with the GitHub route's release-on-failure step** (`webhooks/github/route.ts` Step 8 — without it a transient `inngest.send` failure after the dedup insert makes Resend retries 200 as "duplicate" and the email is dropped forever) + claim-insert on `claim_key` as the pipeline's first step (graceful short-circuit on conflict — deepen: adopt-and-resume on unfinalized stubs) |
| "Parse-and-discard keeps third-party PII out at rest" | True for OUR storage. But Resend retains received email content **30 days, all plans, no DELETE endpoint exists** ([pricing](https://resend.com/pricing) + API index, fetched 2026-06-10) | Art. 30 PA row discloses BOTH 30-day windows (Resend + Anthropic); `email_triage_items` schema has **no body column** (structural guarantee); the Proton mailbox local copy (Sieve keep) is the durable original |
| Open Q1: "server-side Slack vs web push" | Zero server-side Slack code exists; `server/notifications.ts:99 notifyOfflineUser` implements WS > web-push > email hierarchy — **but `NotificationPayload` is hardcoded to `{type: "review_gate"; conversationId; ...}` with deep link `/dashboard/chat/{conversationId}`** (notifications.ts:32-37,146) | Reuse the hierarchy, but the payload widening is **unconditionally required**: discriminated-union `email_triage` variant deep-linking to the triage detail page, swept per `cq-union-widening-grep-three-patterns` + `tsc --noEmit` exhaustiveness; email-fallback link parity |
| "Resend Inbound webhook delivers the email" | Webhook is **metadata-only**: "Webhooks do not include the email body, headers, or attachments" ([docs](https://resend.com/docs/webhooks/emails/received)). Body via `GET /emails/receiving/{id}` | Statutory check runs on webhook metadata (subject + sender) BEFORE the body fetch; body fetched transiently for the body-text statutory pass + summary, never persisted |
| "Webhook secret provisioned in dashboard" | Fully API-provisionable: `POST /domains` accepts `capabilities.receiving`, `POST /webhooks` returns `signing_secret` ([docs](https://resend.com/docs/api-reference/webhooks/create-webhook)) | Idempotent bootstrap script `infra/resend-inbound-bootstrap.sh`, run BEFORE merge (it mints the MX value + secret the Terraform apply consumes) |
| Open Q3: sender scoping allowlist-first vs all-mail | ops@ is a NEW address; its senders are exactly the long tail we migrate there (#5135) — an allowlist recreates the per-sender onboarding bottleneck. Also: Sieve forwarding strips original sender authentication, so any sender-derived trust signal is spoofable | **Resolved: all-mail.** Statutory fast-path scans everything; LLM is read-only/no-tools so unknown-sender injection is bounded to a misleading summary. **No `sender_known` badge** (review-cut: spoofable trust signal, no source of truth — operator stays uniformly skeptical) |
| LLM client availability | `@anthropic-ai/sdk@^0.92.0` in `apps/web-platform/package.json:61`. **Deepen correction:** `cron-compound-promote.ts:423-427` uses raw `fetch("https://api.anthropic.com/v1/messages")`, NOT the SDK — copying it literally would force a global-fetch mock that collides with the body-fetch mock in tests | Summarizer uses the SDK directly; client precedent `server/inngest/functions/agent-on-spawn-requested.ts`; test mock precedent `test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts:198-203` (`vi.mock("@anthropic-ai/sdk")` + `messages.create` spy, zero-call assertions at :450,:473). Body fetch gets its OWN mocked module — never a shared global fetch mock |
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

- `apps/web-platform/infra/dns.tf`: add `cloudflare_record`(s) for
  `inbound.soleur.ai` — **the full record set the Resend Domains API response returns**,
  not MX alone: Resend subdomain verification uses non-obvious names (DKIM at
  `resend._domainkey.<sub>`, possible SPF/bounce records, MX priority 10 — learning
  `2026-04-06-resend-subdomain-verification-dns-patterns.md`). The bootstrap script
  prints ALL records; dns.tf mirrors them. Use FQDN, never `@` (learning
  `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`).
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
  by `POST /webhooks` — **the bootstrap script must NEVER print it to stdout**: it pipes
  the value into Doppler directly behind the prod-write defer-gate ack and prints only a
  masked confirmation `whsec_***…last4`; terminal scrollback + agent transcripts are the
  exposure class `hr-never-paste-secrets-via-bang-prefix` exists for, on the output
  side), `EMAIL_TRIAGE_OWNER_USER_ID` (the founder user UUID — triage rows are
  RLS-scoped to this user; the pipeline check is **existence + role**: matches a `users`
  row AND that row is the founder/owner — a Doppler typo holding any other valid user
  UUID would otherwise route third-party PII into another account's RLS scope and push
  pings to their devices. On unset/invalid the pipeline **throws a retriable error**
  (NOT silent skip, NOT NonRetriableError) so Inngest's retry window self-heals a
  transient misconfig; terminal exhaustion → loud Sentry. A skip would 200-and-drop
  mail forever — Resend never retries after the route ACKs). Prod Doppler writes go
  through the existing prod-write defer-gate with explicit ack.

### Apply path

Cloud-init not applicable (no new host). **Order fixed at plan-review (DHH P0 — the
previous order consumed the MX value before it existed):**

1. *(pre-merge)* Execute the idempotent `resend-inbound-bootstrap.sh`: **first verifies
   the API key belongs to the account owning the verified `soleur.ai` domain** (two
   Resend accounts have existed — learning
   `2026-04-06-resend-duplicate-account-consolidation.md`; a wrong-account key 403s as
   "domain not verified"), enables `capabilities.receiving` via the Domains API,
   creates the `email.received` webhook pointing at
   `https://app.soleur.ai/api/webhooks/resend-inbound`, **writes the `signing_secret`
   straight into Doppler (defer-gate ack) and prints only the masked tail + the full
   DNS record set** (MX + any DKIM/SPF records the API returns). Safe before code
   ships: a webhook pointing at a 404 route just retries (5s→10h schedule), and no
   mail flows until the Sieve rule exists. This also makes AC9's `terraform plan`
   checkable in the PR.
2. Store `EMAIL_TRIAGE_OWNER_USER_ID` in Doppler (prod-write defer-gate ack;
   `RESEND_INBOUND_WEBHOOK_SECRET` was written by step 1).
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
  what: "daily synthetic ingress probe — cron-email-ingress-probe sends a marker email via Resend outbound to ops@soleur.ai, step.sleeps 15 min, then asserts ITS OWN row landed (same-run assertion — no previous-run bookkeeping, no first-run ambiguity); Sentry cron monitor asserts the check-in. Probe function pins retries: 0 (or throws NonRetriableError from the assertion) — under default Inngest retries a 16-min-late landing would retry-to-green and NEVER alarm, silently degrading the 15-min SLA to 15-min-plus-retry-window"
  cadence: "daily; in-run SLA 15 min; monitor checkin margin 60 min. Accepted dark window: worst case ~25.5h (24h cadence + 15min SLA + 60min margin) between Sieve breaking and founder email — explicitly accepted against the shortest statutory clock (Art. 33 72h): detection consumes ≤35% of the clock and the Proton keep-copy preserves the mail for recovery; raise cadence to 2x/day if this ever bites"
  alert_target: "Sentry issue alert → founder email (existing alert routing). Triage note: probe-sender-down vs ingress-broken is distinguished WITHOUT SSH by the failing step name in the Sentry event breadcrumbs (probe-send vs probe-assert). Known-correlated alarm: probe sender and the email-notification fallback share the Resend outbound dependency"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (full house shape: checkin_margin 60, max_runtime_minutes ≥ 20 — the 15-min sleep is INSIDE the run, the small-cron default 10 would mark every run errored; failure_issue_threshold, recovery_threshold, timezone, in-file comment justifying the 60-min margin deviation from the 30-min Inngest-fired precedent) + .github/workflows/apply-sentry-infra.yml -target line (hardcoded allowlist — a new monitor resource without its -target entry is silently never created) + apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "webhook route: 500 + Sentry op:secret on UNSET secret BEFORE touching svix (resend.webhooks.verify THROWS — it does not return false; an unset secret throws from the standardwebhooks constructor and would otherwise be indistinguishable from a signature failure); 401 on svix-verify throw or missing svix-* headers (Layer 2: route-level logger.error → pino logMethod hook → Sentry mirror); 413 on oversized body before verify; 500 on dedup-insert failure (GitHub-route precedent incl. release-on-failure). Inngest pipeline failures: Layer 1 — sentry-correlation middleware transformOutput captures function-final errors automatically with fn_id/run_id tags + per-step breadcrumbs (server/inngest/middleware/sentry-correlation.ts:107-151; no per-function captureException needed, PROVIDED the function is registered in app/api/inngest/route.ts). notifyOfflineUser failure on a STATUTORY item mirrors to Sentry via explicit captureException (cq-silent-fallback-must-mirror-to-sentry — the existing notifications.ts catch passes err as a STRING so the Layer 2 hook's err-instanceof-Error path never captures; the explicit mirror is necessary, not redundant); owner-env misconfiguration → retriable throw → Layer 1 on exhaustion; mail_class allowlist coercion → reportSilentFallback/logger.warn op:mail-class-coerced (Layer 2 — a bare Sentry tag attached to no captured event reaches no one). PII discipline: SENSITIVE_KEY_NAMES gains subject/sender/from/to so the Layer 1 middleware's setExtra(inngest.event_data) is scrubbed — without this, every pipeline error event ships third-party PII to Sentry and falsifies the sub-processor disclosures"

failure_modes:
  - mode: "Sieve forward silently broken / Proton address deleted (quiet mailbox indistinguishable from broken chain)"
    detection: "daily probe fails its own 15-min assertion (retries: 0) → failed/error Sentry check-in → monitor alert"
    alert_route: "Sentry monitor alert → founder email"
  - mode: "webhook signing-secret drift (rotation, re-created webhook)"
    detection: "401 responses logged at route level → Layer 2 pino→Sentry mirror as tagged events; Resend retries (5s→10h schedule) keep events replayable; the daily probe email also traverses the webhook, so drift on a quiet mailbox still surfaces within 24h"
    alert_route: "Sentry issue alert"
  - mode: "Resend body-fetch failures (GET /emails/receiving/{id} 5xx)"
    detection: "Inngest step retries; terminal failure → Layer 1 middleware captureException tagged feature:email-triage op:body-fetch; statutory metadata-matches still produce a degraded row + ping BEFORE the fetch, so a DSAR is never silently dropped by a fetch failure"
    alert_route: "Sentry issue alert"
  - mode: "retention purge wedged (Art. 5(1)(e) obligation silently stops)"
    detection: "purge is a distinct step.run, FIRST in the probe function (before send/sleep/assert — a broken ingress chain must not starve the purge); its failure fails the run → check-in posts error (not missed) → Layer 1 captureException op:retention-purge; the step breadcrumb disambiguates purge-broken from ingress-broken on the shared monitor"
    alert_route: "Sentry monitor alert + issue alert"
  - mode: "Inngest function not registered / cron dark"
    detection: "EXPECTED_CRON_FUNCTIONS registry test fails at CI for the cron; the EVENT function (email-on-received) is guarded only by the hand-bumped count test — AC6 therefore explicitly asserts emailOnReceived appears in the app/api/inngest/route.ts array; cron-inngest-cron-watchdog covers runtime desync; the daily probe catches a dark event-function within 24h post-merge"
    alert_route: "CI failure pre-merge; watchdog Sentry heartbeat + probe monitor post-merge"

logs:
  where: "pino → journald → Better Stack. PII tri-ban per TR3 (deepen-hardened): no raw bodies, no sender values, AND no subject values — subject is the likeliest special-category carrier; the ban covers log args, Sentry tags/extras, AND Error-message strings (the scrubber walks keyed containers only — new Error(`...${subject}`) leaks into the issue title unscrubbed)"
  retention: "Better Stack free-tier window (post-#5105 reduced volume)"

discoverability_test:
  command: curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST https://app.soleur.ai/api/internal/trigger-cron
  command_note: "401 unauthenticated proves the SSH-free trigger surface is live; with INNGEST_MANUAL_TRIGGER_SECRET the operator fires cron/email-ingress-probe.manual-trigger (allowlist auto-derives from EXPECTED_CRON_FUNCTIONS) and reads the probe row via GET /api/inbox/emails?include_probes=1 (probe rows excluded by default; the explicit param resolves the visibility contradiction)"
  expected_output: "401 (the authenticated full loop: probe completes within 15 min; probe-marked row visible with include_probes=1; Sentry monitor shows OK check-in)"
```

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/102_email_triage_items.sql` (+ `.down.sql`) | `email_triage_items` (NO body column — structural parse-and-discard). Columns: `id, user_id (FK users ON DELETE RESTRICT — CASCADE would either abort the owner's Art. 17 deletion via the no-delete trigger or silently destroy statutory evidence; erasure goes through the anonymise RPC), claim_key (text NOT NULL UNIQUE — COALESCE(message_id, 'resend:'∥resend_email_id): RFC 5322 Message-ID is optional + sender-controlled, and Postgres UNIQUE treats NULLs as distinct, so naked UNIQUE(message_id) defeats dedup), message_id (display field, nullable), resend_email_id, sender (raw From header value), subject, summary, mail_class, statutory_class (nullable — non-NULL ⟺ deterministic-path provenance; LLM can never write it), rule_id (nullable — matched statutory rule, renders in detail view), status ('new'∣'acknowledged'∣'archived'), status_changed_at, acknowledged_at (one-time-set — when-the-operator-saw-it is itself WORM), received_at (timestamptz NOT NULL, NO default — sourced from the RESEND EVENT PAYLOAD receive timestamp, never insert time; on missing/unparseable payload field fall back to the svix-timestamp header captured in the event envelope + Sentry mirror + received_at_source ('payload'∣'envelope') provenance column; CHECK (received_at <= created_at + interval '5 minutes') catches epoch-unit bugs at insert instead of immortalizing them), created_at`. WORM trigger per the `## WORM Mutation Matrix` section (adapt mig 075 — TWO freeze classes: hard-frozen + one-time-set NULL→value per 075's `accepted_at` shape at 075:117-120; whole-row copy breaks the pipeline's own finalize). Bypass mechanism for purge/anonymise: **GUC-gated SECURITY DEFINER RPCs (mig 087 `SET LOCAL app.<table>_<op>_in_progress` pattern)** — NOT `session_replication_role` (superuser-only on managed Supabase) and NOT `current_user = 'service_role'` checks (always-false under PostgREST; learnings 2026-05-18/-31). Write-path RPCs: `set_email_triage_status(p_id, p_status)` (auth.uid() pin, `SET search_path = public, pg_temp` per cq-pg-security-definer-search-path-pin-pg-temp, enforces one-way `new → acknowledged∣archived` IN the DB — RLS cannot express transitions and a route-only matrix leaves `acknowledged → new` DB-legal), `purge_email_triage_items()`, `anonymise_email_triage_items(p_user_id)` (NULLs user_id/sender; wired into the account-delete flow). No owner-INSERT/UPDATE RLS policy alongside the RPCs (the policy itself is a bypass path — learning 2026-05-21). Partial index `(user_id, received_at DESC) WHERE status <> 'archived'`. PII columns carry `-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA per Phase 7)` annotations (gdpr-gate). Plus `processed_resend_events(svix_id)` dedup table (pattern `processed_<source>_events` per migs 030/052) WITH its pg_cron 90-day retention sweep + timestamp index mirroring mig `094_dedup_tables_retention.sql:42-70` (the plan previously left it growing unbounded). `.down.sql` drops trigger functions + RPCs + pg_cron job, not just tables. Re-verify 102 is still free at write time vs `git ls-tree origin/main` (duplicate migration numbers have shipped before — learning 2026-05-30) |
| `apps/web-platform/server/email-triage/statutory-rules.ts` | Code-static rule registry: `{ruleId, class, senderPatterns, keywordPatterns, dueRule (e.g. calendar-month for DSAR per Art. 12(3), 72h for breach), catalogAnchor, catalogExcerpt}` for DSAR / breach / service-of-process / regulator / probe-marker; **deterministic first-match priority order** (breach > service-of-process > DSAR > regulator > probe) for multi-class emails; pure function, no I/O. **Language scope: EN + FR statutory vocabulary minimum** (accès/effacement/RGPD; a French DSAR to a French-founded EU-facing company is the base case, not an edge — DE Auskunft/DSGVO optional). **Input normalization before the body pass: HTML-only bodies get tag-strip + entity-decode** (raw-HTML matching lets entities/soft-hyphens/tag-interleaved spans split keywords). **Attachment blind-spot closure: the keyword pass ALSO runs over attachment filenames (already-captured metadata), and a deterministic rule escalates thin/stub body + attachments present to `legal-review`** (a PDF-only DSAR letter must not slip through as a vague summary — the deferral re-evaluation criterion can't fire if the system itself is what failed to see it). Clock display derives from `received_at` + registry `dueRule` — no clock columns in the DB (registry is the single system-of-record for statutory periods) |
| `apps/web-platform/server/email-triage/summarize.ts` | Read-only LLM summarizer: sanitization via **`sanitizePromptString` imported from `server/inngest/leader-prompts/prompt-assembly.ts:32` (exported, strips `\x00-\x08\x0b-\x1f\x7f`/U+2028/U+2029, NO length cap)** — do NOT copy the file-private local in `soleur-go-runner.ts:1200`, whose `.slice(0, 256)` identifier cap would silently truncate email bodies. **Fetched body hard-truncated to a pinned constant (64 KiB) before sanitize/summarize** — a multi-MB body is otherwise unbounded Anthropic token spend + an Inngest worker memory spike. Direct `@anthropic-ai/sdk` call (client precedent `agent-on-spawn-requested.ts` — NOT `cron-compound-promote.ts`, which uses raw fetch), prompt instructs omission of special-category personal details (gdpr-gate Art. 9 note; residual risk that the LLM ignores the instruction is named in the DPIA memo — prompt-instruction-only is a claim, not a mechanism, and WORM makes any leak immutable). **Output `mail_class` is validated against a closed allowlist (`vendor∣billing∣security∣newsletter∣legal-review∣other`) that excludes ALL statutory classes and `probe`** — the LLM structurally cannot forge a statutory appearance or hide mail as a probe; out-of-allowlist output coerces to `other` + `reportSilentFallback` op:mail-class-coerced (Layer 2 — a bare tag on no event reaches no one) |
| `apps/web-platform/app/api/webhooks/resend-inbound/route.ts` | 3rd ingress, hardened to full GitHub-route parity: **size cap → 413 BEFORE verify** (copy `MAX_WEBHOOK_BODY_BYTES`; 64-256 KiB is generous for a metadata-only payload); **unset `RESEND_INBOUND_WEBHOOK_SECRET` → 500 + Sentry op:secret BEFORE touching svix** (`resend.webhooks.verify` THROWS — boolean-return assumption breaks the route; an empty secret throws from the standardwebhooks constructor, indistinguishable from a signature failure without the explicit guard; copy `github/route.ts:107-118`, not Stripe's `!` assertion); raw-body read (`await req.text()` BEFORE parse — svix requirement); verify via installed `resend.webhooks.verify` (resend@6.12.3, index.d.mts:2108; takes `{payload, headers:{id,timestamp,signature}, webhookSecret}`, timing-safe via standardwebhooks, hard ±5-min replay tolerance) in try/catch → **401 on throw or on any missing `svix-*` header**; `processed_resend_events` plain-insert dedup via new `lib/webhook-dedup.ts` helper (500 on insert failure, NO ON CONFLICT — supabase-js `data:null` quirk); **three-way release classification (GitHub-route nuance the original plan under-specified):** (1) transient failure post-insert (`inngest.send`, DB error) → release dedup row + 5xx (retry is wanted); (2) **signature-valid but deterministically unprocessable (missing receiving-email id) → KEEP dedup row + 200 + Sentry warn** (`github/route.ts:216-219` precedent — a svix retry is byte-identical; release+500 here is a 10-hour poison-retry storm); (3) malformed JSON after verify → release + 400 (`github/route.ts:202-208`); dispatch via **`sendInngestWithRetry`** (both existing ingresses use it); emit event **`email/inbound.received`** (exported constant + `v: "1"` envelope per the `WORKSPACE_RECONCILE_REQUESTED_EVENT` pattern; `email/received` would collide with Resend's own outbound `email.*` taxonomy) carrying `{svixId, resendEmailId, subject, sender, receivedAt}` — subject/sender stay in the payload because the metadata-first statutory check MUST NOT depend on a body fetch; the Inngest event-store PII consequence is handled via SENSITIVE_KEY_NAMES + PA-row disclosure (see Files to Edit). **Route MUST be added to `PUBLIC_PATHS` in `lib/routes.ts`** — signature-authed routes otherwise 307 to /login via Supabase session middleware (learning 2026-05-29) |
| `apps/web-platform/server/inngest/functions/email-on-received.ts` | (Renamed from `email-received-triage.ts` — event handlers follow `<domain>-on-<event>.ts`: `github-on-event.ts`, `cfo-on-payment-failed.ts`.) Pipeline with **pinned step boundaries (ADR-033 I1/I5 — step.run returns are CHECKPOINTED in the Inngest run store, so the body must never be a step return value or event field, or parse-and-discard is defeated):** (a) `step.run("claim-insert")` — stub row on `claim_key` conflict→short-circuit, **but only if the existing row is finalized (`mail_class IS NOT NULL OR statutory_class IS NOT NULL`); an unfinalized stub is adopted and the pipeline resumes from (b)** — otherwise a run that dies mid-pipeline leaves a permanent blank stub that every redelivery short-circuits against: the exact "DSAR rots with a WORM trail proving receipt" scenario. Stub populates ALL hard-frozen columns (claim_key, message_id, sender, subject, resend_email_id, received_at) and SQL **NULL — never `''`** — for the one-time-set columns (an empty-string stub makes the freeze trigger reject the finalize); supabase-js 23505-catch idiom, not literal ON CONFLICT (mig 052:55-60 quirk); (b) **statutory check on event METADATA (subject + sender) — pure/inline, no IO, before any body fetch**; metadata-match → `step.run("finalize-statutory")` + notify + return (LLM and body fetch unreachable; a fetch outage can only degrade the row, never drop the DSAR); (c) **ONE fused `step.run("fetch-sanitize-summarize")`** — body fetch (`GET /emails/receiving/{id}`), body-text statutory pass (on the HTML-normalized text), truncate, sanitize, LLM call — returning ONLY `{summary, mailClass, bodyStatutoryRuleId}`; the body never crosses a step boundary; accepted tradeoff: a transient failure inside re-runs one LLM call, bounded by `retries: 1` (precedent `cfo-on-payment-failed.ts:260`); (d) `step.run("finalize-row")`; (e) `step.run("notify")` LAST and separate — a notify-failure retry must not re-run the LLM, a finalize retry must not double-ping. **Inngest `throttle` config + daily LLM-call ceiling for feature:email-triage** (anyone on the internet controls our Anthropic spend otherwise; on breach, row lands as `mail_class: other`, summary "deferred — volume cap" + Sentry — degraded triage is acceptable, unbounded spend is not). Body discarded — never persisted, never logged. `notifyOfflineUser` failures on statutory items mirror to Sentry. Owner-env unset/invalid → **retriable throw** (see Secrets bullet) |
| `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` | Daily, **steps in this order:** (1) `step.run("retention-purge")` FIRST — Art. 5(1)(e) must not be starved by a broken ingress chain: calls `purge_email_triage_items()` RPC (GUC-bypass; predicates key on **`statutory_class IS NULL`** — the provenance column the LLM structurally cannot write — never on `mail_class`): probe rows > 7d, non-statutory > 365d, statutory retained per the PA-row accountability period; **plus T-7d/T-2d deadline-approach re-pin + ping for acknowledged-but-unresolved statutory items** (acknowledge is workflow state, not legal resolution — without a mechanical backstop the UI copy is a claim; the clock derives from `received_at` + registry `dueRule`); (2) `step.run("send-probe")` — marker email (Resend outbound `notifications@soleur.ai` → `ops@soleur.ai`) **carrying a per-run unguessable token `SOLEUR-PROBE-{uuid}` recorded in a `probe_tokens` row** — a static marker is a forgeable mail-suppression channel (any sender stamping it gets their mail auto-hidden + auto-purged in 7d, violating the ADR's own unauthenticated-sender sentence); the pipeline's probe rule matches the SHAPE, but `mail_class='probe'` is finalized only on token-match against a recent `probe_tokens` row — shape-without-token classifies `other` (visible) + Sentry; (3) `step.sleep` 15 min; (4) assert THIS run's probe row exists → Sentry cron check-in. **Function pins `retries: 0`** (or NonRetriableError from the assertion) — default retries silently convert a late probe into a green run. Same-run assertion: no previous-run bookkeeping, manual-trigger works standalone. Probe identity is synthetic content from our own outbound address — no real-user data transits, sanctioned vs `hr-dev-prd-distinct-supabase-projects` (learning 2026-05-16 prod-synthetic-users) |
| `apps/web-platform/app/api/inbox/emails/route.ts` | List triage items (auth: `withUserRateLimit` + **user-context Supabase client — never the service client, which silently bypasses RLS**): full rows (small by construction — no body), unacknowledged statutory pinned first (server-side ordering contract, tested server-side); **excludes unfinalized stub rows (`mail_class IS NOT NULL OR statutory_class IS NOT NULL`)** — between claim-insert and finalize a NULL-summary stub must not render; excludes probe rows unless `?include_probes=1` (strict `=== "1"`); excludes `archived` unless `?status=archived` (strict equality, anything else = default view) |
| `apps/web-platform/app/api/inbox/emails/[id]/acknowledge/route.ts` + `.../archive/route.ts` | **POST verb-subresources (replaces the planned PATCH `/status` hybrid — the codebase's lifecycle-transition family is POST-on-verb: `dashboard/today/[id]/cancel∣discard`; the only PATCH routes are field updates, never `/status` subresources.)** Each calls the `set_email_triage_status` SECURITY DEFINER RPC — the one-way transition matrix (`new → acknowledged∣archived`) is enforced IN the DB, route checks are defense-in-depth; `withUserRateLimit` + user-context client; HTTP-only exports. **No detail GET route** (review-cut): the detail page is a server component querying Supabase directly |
| `apps/web-platform/components/inbox/email-triage-row.tsx` | List rows per wireframes `knowledge-base/product/design/inbox/operator-email-triage.pen`: standard row (class pill, summary, sender, received-at, Archive action) + statutory variant (pinned while unacknowledged, red accent, inline due-date derived from `received_at` + registry `dueRule`, Acknowledge action — acknowledgment unpins but the item stays visible with its clock; acknowledgment is workflow state, NOT legal resolution, stated in the UI). **`legal-review` class gets a distinct warning treatment + "rules did not match — verify against the Proton original" copy** — it is the declared second net for statutory false-negatives and currently renders identically to vendor mail, i.e. mitigates nothing. **All attacker-controlled strings (subject, sender, summary) pass through `sanitizeDisplayString` (lib/sanitize-display.ts) at render: bidi/Cf strip (U+202A–U+202E, U+2066–U+2069 — `sanitizePromptString` does NOT remove these; an RLO in a subject visually spoofs the row) + ~200-char cap; summary renders as plain text nodes ONLY — `markdown-renderer.tsx` is forbidden for triage content (component test asserts no anchors/dangerouslySetInnerHTML from item content)** |
| `apps/web-platform/app/(dashboard)/dashboard/inbox/email/[emailId]/page.tsx` | (Segment renamed `[id]`→`[emailId]` — page params are descriptive: `chat/[conversationId]`; matches the notification payload field.) Detail views per wireframes (server component mirroring `audit/page.tsx`: **cookie-scoped `createClient` — never service client — + `redirect("/login")` + belt-and-suspenders `.eq("user_id", user.id)` + `export const dynamic = "force-dynamic"`**; stable deep-link target for the push ping): read-only; headers shown = sender/subject/received-at/message-id (FR6 wording aligned — full headers are NOT persisted). **SPF/DKIM/DMARC badges: pre-decided contingency — if Phase 0 finds auth results in the Resend payload, an `auth_results` column joins the migration column list + WORM hard-frozen set + FR6 wording + list payload; otherwise the badges are CUT (a direct-Supabase page cannot render data with no column — don't discover this mid-Phase 5)**; honesty notice states the body was discarded AND that the original is retained in the Proton ops@ mailbox; statutory: due-date block + matched `rule_id` + inline `catalogExcerpt` + link to the legal-threshold catalog entry |
| `apps/web-platform/server/email-triage-tools.ts` | **Agent-native parity (deepen CRITICAL: the feature's premise is "agents triage email instead of the operator", yet no agent surface was planned — in-product agents consume in-process MCP tools via `createSdkMcpServer` at `agent-runner.ts:1540`, NOT cookie-authed HTTP routes; both new read surfaces were agent-invisible).** `email_triage_list` (params mirroring the list route: includeProbes, status; userId closure via `getFreshTenantClient` per `conversations-tools.ts:18-21`) + `email_triage_get(id)` returning the row **plus server-side-derived dueDate/catalogExcerpt from the statutory registry** (if the tool returned the raw row the agent would have to invent statutory periods — the registry exists to prevent exactly that). Registered in `agent-runner.ts` + `TOOL_TIER_MAP` (`auto-approve` — reads) + a `## Email triage inbox` system-prompt block (tools without a prompt section are undiscoverable — `agent-runner.ts:1259-1261`; the block carries the same honesty caveats the human detail page gets: statutory items carry a legal clock, bodies are discarded, Proton holds originals). **Status transitions are UI-only in v1 — no agent write tool; boundary recorded in spec FR9** (a prompt-injected agent auto-acknowledging a DSAR would silently unpin a statutory clock; if a write tool ever ships it must be `gated`-tier, never auto-approve — cite #4671) |
| `apps/web-platform/lib/webhook-dedup.ts` | `claimDelivery(table, key)` / `releaseDelivery(table, key)` — rule-of-three extraction (this PR creates the third verbatim copy of the claim/release idiom after `stripe/route.ts:118-160` and `github/route.ts:147-190`). **New route only** — migrating the two existing brand-critical routes is a separate scope-out issue (distinct from #3739, which is the `reportSilentFallbackWithUser` extraction — a different helper; the plan's overlap note previously conflated them) |
| `apps/web-platform/lib/sanitize-display.ts` | `sanitizeDisplayString`: bidi/Cf control strip + length cap for render sinks (row, detail, notification title/body); `escapeHtml` already exists at the email sink (`notifications.ts:223-228`) — reuse it there, plus CR/LF strip near any email `subject:` field (header-injection hygiene) |
| `apps/web-platform/infra/resend-inbound-bootstrap.sh` | Idempotent: account-ownership preflight, enable `capabilities.receiving`, create `email.received` webhook, **write signing_secret into Doppler (defer-gate ack) — print masked tail only** + the full DNS record set; `set -euo pipefail`, stdout for action signals |
| `apps/web-platform/test/server/resend-inbound-route.test.ts` | Svix-verify (deterministic — direct route invocation with svix-lib-computed signatures via `Webhook.sign` (svix@1.92.2, `webhook.d.ts:21`), NO LLM in assertion path; copy the `vi.hoisted` mock-bundle shape from `test/server/webhooks/github-route.test.ts:7-78`), **unset-secret → 500 + Sentry (before svix)**, missing `svix-*` headers → 401, **oversized body → 413 before verify**, dedup 500-path, **three-way release: transient → released + 5xx; signature-valid-but-no-email-id → dedup row KEPT + 200 + Sentry warn; malformed JSON → released + 400**, happy-path emits exactly one `email/inbound.received` |
| `apps/web-platform/test/server/statutory-rules.test.ts` | Synthesized fixtures only (`cq-test-fixtures-synthesized-only`): DSAR/breach/SoP/regulator positives (subject-only, body-only, **non-English: FR DSAR positive**, **HTML-only body positive**, **attachment-filename positive + thin-body+attachment escalation**), **multi-class priority as ≥4 adjacent PAIRWISE fixtures (breach+SoP, SoP+DSAR, DSAR+regulator, regulator+probe) — one all-keywords fixture only proves breach wins overall and passes under a wrong middle ordering**, vendor-mail negatives, probe marker (token-match + shape-without-token→other). **Due-date computation contract lives HERE (pure function — calendar-month vs naive +30d discriminating fixtures: received Jan 29/30/31 → due Feb 28/29; leap year; 72h breach rule); the component test asserts only that the computed string renders** (AC3e previously had no test home) |
| `apps/web-platform/test/server/inngest/email-on-received.test.ts` | Pipeline (handler-direct invocation with eager mock `step` — precedent `test/server/inngest/cfo-on-payment-failed.test.ts` + `event-scheduled-reminder.test.ts:46-66`): metadata statutory match produces row + notify with **body fetch never called**; body-fetch terminal failure after metadata match still yields the statutory row (degraded); statutory short-circuits LLM (**`vi.mock("@anthropic-ai/sdk")` `messages.create` spy zero calls — precedent `agent-on-spawn-requested-leader-loop.test.ts:198-203`; body fetch behind its OWN mocked module, never a shared global fetch mock**); duplicate `claim_key` vs FINALIZED row short-circuits gracefully; **claim conflict vs UNFINALIZED stub resumes and finalizes**; **stub inserts NULL (not '') one-time-set columns; finalize succeeds once, second finalize → P0001**; sanitization applied (subject+sender fixtures, not body only); LLM `mail_class` allowlist coercion; no insert payload or log call contains body, **sender, or subject** fixtures; statutory notify failure mirrors to Sentry; **owner-env unset → retriable throw (not skip)**; probe-shape-without-token → `other` |
| `apps/web-platform/test/server/inbox-emails-route.test.ts` | **List route (previously zero planned tests):** default excludes archived + probe + unfinalized stubs; `?status=archived` / `?include_probes=1` strict-equality opt-ins; **server-side statutory-pinned-first ordering** (a server regression with a correct component otherwise passes the suite); second-user → empty (owner-scope); HTTP-only exports |
| `apps/web-platform/test/server/inbox-email-status-routes.test.ts` | **Acknowledge/archive routes (previously zero planned tests):** valid transitions succeed; `acknowledged → new` / `archived → acknowledged` / unknown status → 4xx; another user's item → 404/403; RPC invoked (not direct table UPDATE); HTTP-only exports |
| `apps/web-platform/test/server/inngest/cron-email-ingress-probe.test.ts` | **Probe cron (previously no dedicated file):** purge step runs FIRST and calls the RPC; boundary fixtures — non-statutory at 364d/365d/366d, probe at 6d/7d/8d (the `>` vs `>=` one-character bug is invisible without exact-boundary fixtures; state intended semantics: strictly-older deleted), statutory at 400d RETAINED; deadline re-pin at T-7d/T-2d; probe row present → OK check-in, absent → failed check-in (no retry — `retries: 0` asserted); probe pipeline fixture: zero Anthropic calls (probe is NOT a statutory class — AC3c's statutory-path assertion does not cover it); `makeStep` must add a no-op `sleep` recording the 15-min duration (`event-scheduled-reminder.test.ts` precedent lacks `sleep`) |
| `apps/web-platform/test/components/inbox/email-triage-row.test.tsx` | (happy-dom component project — NOT jsdom; `test/**/*.test.tsx` glob; style precedent `test/components/conversation-row.test.tsx`.) Row variants render; statutory pinned-first while unacknowledged; `legal-review` warning treatment renders; acknowledge/archive actions fire the POSTs and the list reflects the transition (DOM contract primary, fired-request spy secondary per learning 2026-05-06); **summary/subject/sender render as text nodes — no anchors, no dangerouslySetInnerHTML from item content; bidi-spoof fixture neutralized** |
| `apps/web-platform/test/server/email-triage-worm.test.ts` | **WORM/RLS integration tier (`TENANT_INTEGRATION_TEST=1`-gated, precedent `test/server/action-sends-worm.test.ts`):** mutation-matrix enforcement per class (hard-frozen reject, one-time-set NULL→value once then P0001, status via RPC only); RESTRICT + anonymise RPC path; purge RPC bypass works (GUC) while direct DELETE rejects; **behavioral RLS deny: second user SELECT → 0 rows + INSERT denied with a TYPE-VALID payload paired with an owner positive control** (a 22P02/23503 masquerades as an RLS deny otherwise — learning 2026-05-16) |
| `knowledge-base/legal/` LIA + DPIA screening memo (directory + topic only; exact filenames at write time — match the existing LinkedIn-Page LIA + PA-22 brief conventions, locate via grep at Phase 0) | FR8 legal bundle artifacts |
| ADR via `/soleur:architecture` ("Inbound email ingress: Proton auto-forward → Resend Inbound — 3rd multi-source ingress") | CTO-recommended decision record alongside ADR-036; one sentence records that forwarded-mail sender identity is unauthenticated (Sieve forwarding strips SPF/DKIM context) so no future feature may derive trust from `sender` |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/dns.tf` | + full `inbound.soleur.ai` record set from the Domains API response (MX + any DKIM/SPF — see Infrastructure section; additive-only; TR1 single-purpose diff; values minted by the pre-merge bootstrap run) |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | + monitor for `cron-email-ingress-probe` — full house shape: `checkin_margin = 60`, **`max_runtime_minutes ≥ 20`** (the 15-min sleep is inside the run; the small-cron 10 would error every run), `failure_issue_threshold`, `recovery_threshold`, `timezone`, in-file comment justifying the 60-min margin deviation from the 30-min Inngest-fired precedent (`cron-monitors.tf:28-35` file culture) |
| `.github/workflows/apply-sentry-infra.yml` | **+ `-target=sentry_cron_monitor.<new resource>` line** — the apply uses a hardcoded target allowlist; a new .tf resource without its line is silently never created (this exact gap left a prior monitor absent; learning 2026-06-05 five-registry lockstep) |
| `apps/web-platform/server/inngest/cron-manifest.ts` | + `cron-email-ingress-probe` in `EXPECTED_CRON_FUNCTIONS` (the manual-trigger allowlist auto-derives via `manualTriggerEventFor` — no second list to edit) |
| `apps/web-platform/app/api/inngest/route.ts` | register `email-on-received` + probe cron in the functions array (`route.ts:85`); **AC6 explicitly asserts the event function appears here** — the registry tests guard `cron-*` files only; a forgotten event-function registration + forgotten count bump passes CI and ships dark |
| `apps/web-platform/lib/routes.ts` | **+ `/api/webhooks/resend-inbound` in `PUBLIC_PATHS`** — signature-authed routes are otherwise 307'd to /login by the Supabase session middleware (learning 2026-05-29; the webhook must also target `app.soleur.ai`, never the apex — apex is Cloudflare static and 405s POSTs) |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | render email-triage rows in the inbox list (unacknowledged statutory pinned first) |
| `apps/web-platform/server/notifications.ts` | **Unconditional (spec-flow P1):** widen `NotificationPayload` to a discriminated union with an `email_triage` variant `{type: "email_triage"; emailId; title; isStatutory}`; deep link `/dashboard/inbox/email/{emailId}` **built exclusively from the server-generated DB uuid — never from `resend_email_id` or any email-derived value (it lands inside `href` at notifications.ts:218,229)**; `title` (= subject, attacker-controlled) passes `escapeHtml` at the email sink (`notifications.ts:223-228` precedent) + `sanitizeDisplayString` + CR/LF strip. Sweep ALL consumers via `tsc --noEmit` TS2322 rails + `cq-union-widening-grep-three-patterns` (`.type === "`, `?.type === "`, `_exhaustive: never`) — enumerated: `permission-callback.ts:45,167-169,301,787,929`, `agent-runner.ts:31,1811`, `cc-dispatcher.ts:155,1715`, `sendPushNotifications`/`sendEmailNotification` in notifications.ts itself, + the test-file family (TS rails enumerate); email-fallback link parity; statutory-path failures mirror to Sentry |
| `apps/web-platform/public/sw.js` | **Invisible to the planned sweep tooling — plain JS in `public/`, outside the TS program, reads `payload.data` not `payload.type`, so neither `tsc` nor the three grep patterns reach it.** `sw.js:105` derives the notification tag as `review-gate[-{conversationId}]`; an `email_triage` push has no conversationId → every triage ping collapses to the single tag `"review-gate"` and browsers REPLACE same-tag notifications — a statutory ping can silently overwrite a pending review-gate notification (or vice versa). Fix: per-variant tag namespace (`email-triage-${emailId}`); `data.url` flows through the existing origin-validated `notificationclick` path (`sw.js:111-118` — already generic, only the tag is broken) |
| `apps/web-platform/server/sensitive-keys.ts` | **+ `subject`, `sender`, `from`, `to` in `SENSITIVE_KEY_NAMES`** — the Inngest sentry-correlation middleware ships `ctx.event.data` to Sentry as `extra` on every captured pipeline error (`sentry-correlation.ts:76,135`) and the scrubber is key-name-based only; without this, TR3 is violated by Layer 1 itself and the sub-processor disclosures are falsified. Also hardens pino's derived `REDACT_PATHS` |
| `apps/web-platform/server/agent-runner.ts` + `apps/web-platform/server/tool-tiers.ts` | register `email-triage-tools` (`platformTools.push` + `platformToolNames.push` + `## Email triage inbox` system-prompt block at the kb-share precedent site `agent-runner.ts:1259-1261`) + `TOOL_TIER_MAP` entries (`auto-approve` for the two read tools — unmapped tools fail closed to `gated`, which would throw a review gate on every list call) |
| `apps/web-platform/.env.example` | + `# --- Resend ---` section: **`RESEND_API_KEY` backfill (currently absent from .env.example entirely while `notifications.ts:69-70` throws without it and this feature makes it load-bearing)** + `RESEND_INBOUND_WEBHOOK_SECRET`, `EMAIL_TRIAGE_OWNER_USER_ID` |
| `apps/web-platform/server/dsar-export-allowlist.ts` | + `email_triage_items` entry in `DSAR_TABLE_ALLOWLIST` (`Readonly<Record<string, DsarTableSpec>>` at :59 — `{ownerField: "user_id", article: "15+20"}`; filename verified at deepen, Phase 0 check resolved) |
| `knowledge-base/legal/article-30-register.md` | + new PA row (next free PA number — grep `^## Processing Activity` tail before naming; Anthropic + Resend recipients, both 30-day windows disclosed, **+ the Inngest event-store window (~24h) — subject/sender transit it in the `email/inbound.received` payload; the GitHub route's own comment block names the Inngest store "a third PII surface" (`github/route.ts:350-358`), and the metadata-first invariant requires keeping subject/sender in the event (fetching them on demand would make the statutory check depend on a body fetch — destroying the fetch-outage-can-only-degrade guarantee)**; retention cells: probe 7d / non-statutory 365d / statutory per accountability period; TOMs incl. statutory fast-path + WORM + Art. 9 summarizer-prompt omission + SENSITIVE_KEY_NAMES scrub. Prose grep-validated against the actual migration body (learning 2026-05-23 — disclosures have invented nonexistent columns before); Resend (US) entry carries SCC/DPF transfer mechanism (learning 2026-02-21) |
| `knowledge-base/legal/data-processing-agreements/anthropic.md` | scope-cell amendment (+ email-triage purpose); §(g) residual-risk names prompt-injection honestly (precedent #4954) |
| Resend vendor DPA row (locate at Phase 0 — `compliance-posture.md` Vendor DPA table and/or `data-processing-agreements/resend.md`) | scope amendment: Resend now custodian of inbound raw third-party mail, 30-day retention, no delete API (gdpr-gate Chapter V finding) |
| `knowledge-base/legal/compliance-posture.md` | Active Items update per gdpr-gate output |
| `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/` mirrors | lockstep: AI-assisted triage of mail to company addresses disclosed; Art. 14(5)(b) notice |
| `knowledge-base/project/specs/feat-inbound-email-action-bus/spec.md` | `status: superseded-in-part` + pointer note (buy path shipped `dns.tf:94`; the operator slice is now `feat-operator-inbox-delegation`) |
| `knowledge-base/project/specs/feat-operator-inbox-delegation/spec.md` | FR6 wording fix (persisted = summary, subject, sender, received-at, message-id — NOT full headers; prevents a reviewer "fixing" it with a JSONB headers column); + FR9 item lifecycle (acknowledge/archive) **including the agent-write boundary: status transitions are UI-only in v1 — no agent tool for the writer path; any future write tool must be `gated`-tier, statutory acknowledge never auto-approve (cite #4671; the gate approval IS the human seeing the item — the entire signal the pin protects)**; FR3 notes metadata-first ordering; AC3's negative dead-man test restored (see AC-P3) |

## WORM Mutation Matrix

(Deepen 2026-06-11 — every P0/P1 the data-integrity pass found falls out of this
matrix being absent: the original freeze list would have P0001'd the pipeline's own
finalize on 100% of emails, and CASCADE either deadlocked Art. 17 or destroyed
statutory evidence. This table is the contract Phase 1 implements and tests.)

| Column | Class | Writers (mechanism) |
|---|---|---|
| `claim_key, message_id, sender, subject, resend_email_id, received_at, received_at_source, created_at` | **Hard-frozen** (any change → P0001; all knowable at claim time, so the stub INSERT populates all of them) | claim-insert only |
| `summary, mail_class, statutory_class, rule_id` | **One-time-set** (NULL→value permitted once — mig 075 `accepted_at` shape at 075:117-120; subsequent change → P0001). Stub inserts SQL **NULL, never `''`** | finalize step only |
| `acknowledged_at` | **One-time-set** | `set_email_triage_status` RPC |
| `status, status_changed_at` | **Transition-constrained** (one-way `new → acknowledged∣archived`, enforced in the RPC — RLS cannot express transitions; a route-only matrix leaves `acknowledged → new` DB-legal from any path holding the owner's JWT) | `set_email_triage_status` RPC only (no owner-UPDATE grant/policy) |
| `user_id, sender` | **Anonymise-only** (NOT NULL→NULL permitted under the GUC bypass) | `anonymise_email_triage_items` RPC (account-delete flow; Art. 17 path for involuntary subjects = row deletion via the same GUC gate, documented in the LIA with the accountability-period override) |
| row DELETE | Rejected except under GUC bypass | `purge_email_triage_items` RPC (probe >7d, non-statutory >365d via `statutory_class IS NULL`) |

Bypass mechanism for all RPCs: `SET LOCAL app.email_triage_<op>_in_progress = 'on'`
checked by the trigger via `current_setting(..., true)` — mig 087 precedent. NOT
`session_replication_role` (superuser-only on managed Supabase), NOT
`current_user = 'service_role'` (always-false under PostgREST).

## Implementation Phases

Ordering is dependency-directed (contract before consumer). Every code phase is
RED-first (`cq-write-failing-tests-before`).

**Phase 0 — Preconditions (verify, pin results in tasks.md):**
1. ~~cron-compound-promote client shape~~ **Resolved at deepen: it uses raw fetch, NOT the SDK.** Read `agent-on-spawn-requested.ts` (SDK client precedent) + its leader-loop test (mock precedent). Registry array located: `app/api/inngest/route.ts:85`.
2. Read mig 075 `workspace_invitations_no_mutate` + mig 052 + **mig 087 (GUC bypass) + mig 094 (dedup retention)** + the 2 most recent migrations (transactional runner — no `CREATE INDEX CONCURRENTLY`). Re-verify 102 still free vs `git ls-tree origin/main`.
3. `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail -3` — next free PA number; locate the Resend vendor DPA row; locate the LIA precedent (`git grep -ln "legitimate interest" knowledge-base/legal/ | head`). (~~dsar-export-allowlist filename~~ — verified at deepen: `server/dsar-export-allowlist.ts`, `DSAR_TABLE_ALLOWLIST` at :59.)
4. Live-probe the Resend API forms used by the bootstrap script (**account-ownership check first** — learning 2026-04-06 duplicate accounts) AND fetch one received-email payload shape: auth-results exposure (decides the badges per the pre-decided contingency), receive-timestamp field name, **text vs html body field shapes (decides the HTML-normalization input)**, attachment metadata shape.
5. Confirm `resend.webhooks.verify` usage shape against the installed package (pinned: resend@6.12.3 index.d.mts:2108 — takes `{payload, headers, webhookSecret}`, THROWS on failure; svix@1.92.2 present, `Webhook.sign` at webhook.d.ts:21 for test signatures).

**Phase 1 — Migration:** failing tests for the **full WORM Mutation Matrix** (hard-frozen reject; one-time-set NULL→value once, second write P0001; stub-NULL-not-empty-string; RESTRICT + anonymise path; purge RPC bypass works while direct DELETE rejects; transition RPC one-way), UNIQUE(claim_key), **behavioral RLS deny (type-valid payload + owner positive control)**, then `102_email_triage_items.sql` + down (column list + RPCs + pg_cron dedup sweep + annotations per Files to Create).

**Phase 2 — Statutory rules (contract):** RED fixtures (subject-only, body-only, **FR-language, HTML-only, attachment-filename, thin-body+attachment escalation, pairwise priority set, probe token-match**, vendor negatives, **due-date calendar-month/leap-year discriminators**) → `statutory-rules.ts` with `ruleId`/`dueRule`/`catalogExcerpt` and first-match priority order.

**Phase 3 — Webhook route:** RED (unset-secret 500, missing-header 401, svix verify-throw 401, 413 cap, dedup 500, **three-way release classification**, happy-path `email/inbound.received` emit) → `resend-inbound/route.ts` + `lib/webhook-dedup.ts` + **`PUBLIC_PATHS` entry**. Deterministic tests: direct route invocation with svix-computed signatures — no LLM anywhere near the assertion path.

**Phase 4 — Inngest pipeline + notification widening:** RED → `email-on-received.ts` (**pinned step boundaries per Files to Create — body never crosses a step boundary; `retries: 1`; throttle + LLM ceiling**; claim-adopt-resume semantics) and the `NotificationPayload` discriminated-union widening in `notifications.ts` (consumer sweep via `tsc --noEmit` + the enumerated list **+ `public/sw.js` tag namespace — outside the TS program, manual edit**; statutory-failure Sentry mirror) + `sensitive-keys.ts` additions. Mock the Anthropic SDK throughout (dedicated body-fetch mock, never shared global fetch).

**Phase 5 — API routes + UI + agent tools:** RED component/route tests → `email-triage-row.tsx` (+ `sanitizeDisplayString`, plain-text invariant, legal-review treatment), detail page (server component per `audit/page.tsx` shape), list route + **POST acknowledge/archive routes (RPC-backed)**, dashboard wiring, **`email-triage-tools.ts` + agent-runner/tool-tiers registration + prompt block**. Match wireframe frames 05-08 minus the review-cut badge; theme tokens, no literal hex.

**Phase 6 — Liveness probe + IaC:** probe cron (**purge-first step order, probe token, `retries: 0`, deadline re-pin**, same-run assertion) + cron-manifest + Sentry monitor TF (full house shape) + **apply-sentry-infra.yml `-target` line** + dns.tf record set + bootstrap script (Doppler-write, masked stdout). Registry-count test updated + **event-function presence assertion**.

**Phase 7 — Legal bundle + ADR + doc amendments:** invoke `legal-document-generator` (PA row incl. **Inngest event-store disclosure**, LIA incl. **Art. 17 path for involuntary subjects (row deletion via GUC gate) + accountability-period override**, DPIA screening memo **naming "Art. 9 content surviving into the persisted summary despite prompt instruction" as accepted residual risk**, lockstep policy edits, Anthropic + Resend scope cells), then `legal-compliance-auditor` cross-consistency pass (both inline at /work per `wg-plan-prescribed-skills-must-run-inline`; output marked draft-requiring-professional-review; **prose grep-validated against the migration body**). `/soleur:architecture` ADR (**+ AP-001 deviation recorded: webhook provisioned by script because no Resend TF provider exists; + AP-009 carve-out: purge deletions tied to Art. 5(1)(e) with statutory carve-out**); supersede-in-part note on the old spec; this spec's FR6/FR9 amendments (incl. agent-write boundary); `.env.example`.

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

- [ ] **AC1** Migration: `email_triage_items` has NO body/html/raw column (grep of the migration file for `body|html|raw_content` returns only comments); **WORM Mutation Matrix enforced per class** — hard-frozen UPDATE → `P0001`; one-time-set NULL→value succeeds exactly once, second finalize → `P0001`; stub with `''` instead of NULL is unrepresentable (tests insert NULL); status transitions only via `set_email_triage_status` RPC and only one-way; UNIQUE(claim_key) enforced; `user_id` FK has **`ON DELETE RESTRICT`** + anonymise RPC path tested; purge RPC deletes under GUC bypass while direct DELETE rejects; RLS: `pg_policy` shape test **+ behavioral second-user deny with type-valid payload + owner positive control**; `LAWFUL_BASIS` annotations present on PII columns.
- [ ] **AC2** Webhook route: **unset secret → 500 + Sentry before svix is touched**; invalid/missing svix signature or missing `svix-*` headers → 401; **oversized body → 413 before verify**; dedup-insert failure → 500; **three-way release: transient (`inngest.send`/DB) → row released + 5xx; signature-valid-but-missing-email-id → row KEPT + 200 + Sentry warn; malformed JSON → released + 400**; valid request emits exactly one `email/inbound.received` event (`v: "1"`) via `sendInngestWithRetry`. All tests invoke the route directly with synthetic signatures (no LLM, no network). Route present in `PUBLIC_PATHS`.
- [ ] **AC3** Statutory fast-path: (a) subject-metadata DSAR fixture produces a statutory row + notify with the body fetch **never invoked**; (b) body-fetch terminal failure after a metadata match still yields the (degraded) statutory row; (c) Anthropic mock asserts zero invocations on every statutory path **and on the probe path (probe is NOT a statutory class — separately asserted)**; (d) statutory `notifyOfflineUser` failure mirrors to Sentry; (e) due date is a calendar-month computation from `received_at` per registry `dueRule` — **contract tested in `statutory-rules.test.ts` with month-end/leap-year discriminating fixtures; the component test asserts only that the computed string renders**; (f) **FR-language, HTML-only, and attachment-filename statutory positives pass; thin-body+attachments escalates**.
- [ ] **AC4** Summarizer: input passes through `prompt-assembly.ts` sanitization (test asserts `\x7f`/U+2028/U+2029 stripped before the mocked client sees it — **subject and sender fixtures, not body only**); body truncated to the pinned cap before the client; LLM `mail_class` output outside the closed allowlist coerces to `other` + `reportSilentFallback` (statutory classes + `probe` unreachable); no insert payload and no log call contains the fixture **body, sender, or subject** strings.
- [ ] **AC5** UI: email-triage row renders as a sibling of conversation rows; unacknowledged statutory pinned first with due-date text (**server-side ordering also tested in the list-route test**); `legal-review` distinct warning treatment renders; Acknowledge (statutory) and Archive (standard) actions fire the **POST subresource routes** and the list reflects the transition; **summary/subject/sender render as text nodes only — no anchors/`dangerouslySetInnerHTML` from item content; bidi-spoof fixture neutralized via `sanitizeDisplayString`**; detail view shows the parse-and-discard notice including the Proton-original pointer; tests under `apps/web-platform/test/components/inbox/` (**happy-dom component project**).
- [ ] **AC6** Registries: `EXPECTED_CRON_FUNCTIONS` count test passes with `cron-email-ingress-probe` added; **`emailOnReceived` asserted present in the `app/api/inngest/route.ts` functions array** (event functions are outside the cron-glob guard); manifest manual-trigger event present (auto-derived allowlist); retention purge covered by unit tests **with exact-boundary fixtures (364/365/366d, 6/7/8d) + statutory-at-400d retained + purge-first step order + `retries: 0` asserted**; deadline re-pin at T-7d/T-2d tested.
- [ ] **AC7** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (this is also the exhaustiveness enumerator for the `NotificationPayload` widening — every TS2322 never-rail widened) **+ `public/sw.js` tag-namespace edit verified by grep (outside the TS program — the rails cannot see it)**; full suite green via the package's own runner.
- [ ] **AC8** Legal bundle committed and cross-consistent: new PA row (number verified free at write time, retention cells per plan, **Inngest event-store window disclosed**), LIA (**incl. Art. 17 involuntary-subject path + accountability override**), DPIA screening memo (**Art. 9 persisted-summary residual named**), lockstep edits in BOTH doc locations, Anthropic + Resend scope cells; `legal-compliance-auditor` pass recorded; **disclosure prose grep-validated against the migration body**.
- [ ] **AC9** `terraform plan` (prd_terraform, canonical triplet) shows an additive-only diff: exactly the new `inbound.soleur.ai` record set (values from the pre-merge bootstrap run) + new Sentry monitor (**full house shape incl. `max_runtime_minutes ≥ 20`**); zero diff on apex Proton MX/SPF/DKIM/`_dmarc`; **`apply-sentry-infra.yml` carries the new `-target` line**.
- [ ] **AC10** ADR committed (incl. the unauthenticated-forwarded-sender sentence + AP-001/AP-009 notes); old spec carries `superseded-in-part`; this spec carries the FR6/FR9 amendments (incl. agent-write boundary); PR body uses `Ref #5103` + `## Changelog` + `semver:minor`.
- [ ] **AC11** Agent-native parity: `email_triage_list` + `email_triage_get` registered (agent-runner + `TOOL_TIER_MAP` auto-approve + system-prompt block); `email_triage_get` returns registry-derived `dueDate`/`catalogExcerpt` server-side; **no agent write tool exists** (grep asserts no `email_triage_set_status`/acknowledge tool registration) per the FR9 boundary.

### Post-merge

- [ ] **AC-P1** Bootstrap executed pre-merge (idempotency re-run is a no-op); secrets in Doppler; receiving enabled; webhook live.
- [ ] **AC-P2** Proton: `ops@soleur.ai` exists; Sieve **forward-and-keep** active (keep-copy verified — original visible in the Proton mailbox after a probe); ops@ is NOT a recovery/login address for any vendor in `knowledge-base/operations/expenses.md` (checklist swept).
- [ ] **AC-P3** Probe loop green AND alert path proven: manual-trigger probe produces a row within the 15-min SLA + OK check-in (positive arm); the one-time chaos check confirms a failed run raises the Sentry alert → founder email (negative arm — spec AC3 restored); synthetic DSAR email produces pinned statutory item + working deep-link ping with zero LLM involvement.
- [ ] **AC-P4** #5103 closed with verification evidence; the #4788 comment already records the override.

## Test Scenarios

- Given a forwarded vendor email, when the webhook fires, then a summarized item appears in the inbox with a class badge and the raw body exists nowhere in our DB or logs.
- Given an email whose SUBJECT contains DSAR-class keywords, when ingested, then the statutory row exists even if the body fetch fails terminally, the due date derives from the payload receive timestamp, and the Anthropic client was never invoked.
- Given the same `claim_key` delivered twice (same or different svix ids), when both deliveries process, then exactly one item row exists and no terminal error is raised — and if the first run died mid-pipeline leaving an unfinalized stub, the second delivery ADOPTS the stub and finalizes it (a permanent blank stub on a DSAR is the brand-survival failure).
- Given an email with no Message-ID header (RFC 5322 optional), when ingested twice, then the `resend:`-prefixed claim_key still dedups it (NULL UNIQUE columns are distinct in Postgres — naked UNIQUE(message_id) would double-process).
- Given `inngest.send` fails after the dedup insert, when Resend retries, then the retry is processed (release-on-failure) rather than swallowed as a duplicate.
- Given a svix-valid payload missing the receiving-email id, when the route classifies it, then the dedup row is KEPT and 200 returned (byte-identical retries make release+500 a 10-hour poison-retry storm).
- Given 50 emails with DSAR keywords arrive in an hour, when the pipeline notifies, then statutory pings coalesce (max 1 per window + "+N more" aggregation) and rows still pin individually — alert fatigue on the statutory channel is the failure the pin exists to prevent.
- Given an external sender stamps the probe marker shape on real mail, when classified, then without a matching `probe_tokens` row it lands as `other` (visible) + Sentry — never auto-hidden/auto-purged.
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
- **#3739** (extract `reportSilentFallbackWithUser` helper across webhook sites) overlaps the new `api/webhooks/resend-inbound` route conceptually. **Acknowledge:** the new route uses the existing `reportSilentFallback`/Sentry helper conventions so it is trivially migratable when #3739 lands; the 11-site extraction stays its own issue. **Deepen correction: #3739 does NOT cover the dedup claim/release idiom** — that is a different helper, and this PR creates its third verbatim copy. Resolution: `lib/webhook-dedup.ts` ships in this PR for the NEW route only; migrating the two existing brand-critical routes gets its own scope-out issue at the deferral sweep (distinct from #3739).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Statutory rule false-negative (DSAR phrased unusually) | Keyword set errs broad (recall over precision — a false positive costs one extra escalation); the LLM path ALSO labels legal-looking mail `mail_class: legal-review` as a second net (advisory only — allowlist-validated, it can never write `statutory_class`); rules reviewed in the legal-compliance-auditor pass |
| Prompt injection via email body | Read-only client, no tools, sanitization parity, summary rendered as plain text (no markdown execution surface in the row); LLM output constrained to the closed `mail_class` allowlist |
| Forwarded-mail SPF/ARC handling at Resend undocumented | Empirical: the post-merge probe IS the test (Proton-forwarded synthetic mail); if Resend drops forwards, the probe fails loudly on day one before any real mail depends on the chain |
| PII in observability | TR3: no body/sender values in pino/Sentry payloads; op-tags only; test asserts the log mock never sees the body fixture |
| Resend/Anthropic 30-day retention misrepresented in policies | PA row discloses both windows explicitly; legal-compliance-auditor cross-checks DPD claims |
| Webhook secret leak | Single rotatable svix secret; rotation = re-run bootstrap + Doppler update; no mailbox credential exists by design |
| Alarm fatigue on the statutory pin | Acknowledge transition unpins handled items (spec-flow P0); pin slot reserved for unacknowledged statutory only. **Deepen: acknowledge-unpin does not survive volume — anyone on the internet can mass-mail DSAR keywords. Notification coalescing (max 1 statutory ping per window, "+N more" aggregation) + Inngest throttle bound the blast radius; rows still pin individually** |
| **Anthropic cost DoS (attacker controls our LLM spend at zero cost)** | Inngest `throttle` on `email/inbound.received` + daily LLM-call ceiling for feature:email-triage; on breach, rows land `mail_class: other` / summary "deferred — volume cap" + Sentry — degraded triage acceptable, unbounded spend not |
| **Probe marker as forgeable mail-suppression channel** | Per-run unguessable token + `probe_tokens` match required to finalize `mail_class='probe'`; shape-without-token → `other` (visible) + Sentry |
| **Third-party PII transiting the Inngest event store + Sentry extras** | `SENSITIVE_KEY_NAMES` additions scrub the Layer 1 `setExtra(event_data)`; body never crosses a step boundary (fused fetch-sanitize-summarize step); Inngest window disclosed in the PA row |
| **Acknowledged statutory item missed anyway (workflow state ≠ legal resolution)** | T-7d/T-2d deadline-approach re-pin + ping in the daily cron — the UI copy's distinction gets a mechanical backstop |
| **Sieve keep-copy silently drifts to redirect-and-discard later** | Accepted (scope-out): keep-copy drift is not continuously detectable without Proton-side automation beyond the auth gate; AC-P2 verifies it at provisioning, and the detail-view honesty notice words the Proton pointer as "normally retained" rather than an unconditional promise |
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
| Cutting `processed_resend_events` for Inngest idempotency keys | Rejected at review: route-level dedup stops duplicate deliveries before they cost a body fetch + LLM call + double ping; vendor idempotency semantics is the weaker guarantee at this threshold |
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
  WORM trigger makes a wrong value permanent. On a missing/unparseable payload field:
  svix-timestamp-header fallback + `received_at_source` provenance + Sentry — never a
  `DEFAULT now()` (the silent insert-time clock is the exact failure, frozen forever).
- The WORM trigger implements the `## WORM Mutation Matrix` — TWO freeze classes
  (hard-frozen + one-time-set), not one. The original single freeze list would have
  P0001'd the pipeline's own finalize on every email; a whole-row no-mutate trigger
  (the mig-075 shape verbatim) additionally breaks the acknowledge/archive lifecycle.
  Adapt the trigger per the matrix, don't copy it.
- `resend.webhooks.verify` THROWS (`WebhookVerificationError`) — it does not return a
  boolean. An unset secret throws from the standardwebhooks constructor
  (`"Secret can't be empty."`) and without the explicit pre-check is indistinguishable
  from a signature failure. Copy `github/route.ts:107-118`, never Stripe's `!` idiom.
- Inngest `step.run` return values are CHECKPOINTED in the run store. If the body
  fetch is its own step, the raw third-party email body persists in Inngest state and
  parse-and-discard is defeated. The fused fetch-sanitize-summarize step returning
  only `{summary, mailClass, bodyStatutoryRuleId}` is load-bearing, not stylistic.
- `public/sw.js` is invisible to every planned sweep tool (`tsc`, the three grep
  patterns) — it is plain JS outside the TS program reading `payload.data`. The
  notification-tag fix there is a manual, grep-verified edit (AC7).
- Probe function MUST pin `retries: 0` (or NonRetriableError from the assertion) —
  under default Inngest retries, a late-landing probe row turns the failed assertion
  into a retry-then-green run and the monitor never alarms.
- supabase-js cannot express `ON CONFLICT DO NOTHING` reliably — the claim-insert
  uses the house 23505-catch idiom (mig 052:55-60 `data:null` quirk), and the
  conflict branch must distinguish finalized (short-circuit) from unfinalized stub
  (adopt + resume).
