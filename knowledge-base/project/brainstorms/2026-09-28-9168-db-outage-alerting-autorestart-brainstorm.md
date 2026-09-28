# Brainstorm: #9168 — DB-outage paging path + bounded auto-restart

**Date:** 2026-09-28
**Issue:** #9168 (OPEN, p1-high, type/bug, domain/engineering)
**Branch:** `feat-9168-db-outage-followup`
**PR:** #9184 (draft)
**Lane:** cross-domain (USER_BRAND_CRITICAL unconditional per #5175)
**Status:** Decided — ready for plan

## What We're Building

Follow-up remediation for the 2026-09-28 production database outage — the second
identical Supabase Postgres hang in 13 days (first: 09-15, postmortem
`knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md`).
Two defect classes:

- **A. Detection without delivery.** `betteruptime_monitor.app_health` (id
  4226366, "soleur app database readiness", `apps/web-platform/infra/uptime-alerts.tf`)
  opened a Better Stack incident 7 min after onset — but its channels are
  `email = true`, `call/sms/push = false`, and `policy_id` is gated on
  `var.betterstack_paid_tier`, which is **not set in Doppler** (verified
  2026-09-28: `TF_VAR_BETTERSTACK_PAID_TIER` absent from `prd_terraform`;
  live monitor `policy_id: null` via read-only API). The alert sat in an inbox
  ~16 min; recovery began only when an agent noticed `/health` while chasing an
  unrelated failed deploy job.
- **B. Recovery requires a human who was never paged.** The platform-side
  Postgres hang recurs with an exact signature (Postgres logs stop mid-stream;
  `db`/`auth`/`rest` go UNHEALTHY; the pooler stays healthy; only a Management
  API project restart recovers). Even a paged human is the wrong long-term
  answer for a signature this crisp.

## User-Brand Impact

- **Artifact:** the `app.soleur.ai` availability surface — sign-in and every
  data-backed page, plus the Better Stack paging path that is supposed to wake
  a human when it dies.
- **Vector:** worst case is a *silent* outage — a user hits a dead product and
  learns we are down before we do; for an autonomous-engineering product, "we
  couldn't detect our own down state" is the brand damage, ahead of the raw
  downtime minutes.
- **Threshold:** `single-user incident`.

## Why This Approach

| Decision | Chosen | Rationale |
|---|---|---|
| Paging channel | **Free-tier Slack integration** (operator one-time OAuth in dashboard) + measured `push = true` flip on `app_health` | Operator declined the Responder seat ($29–34/mo) even though the `expenses.md` deferral trigger (#3960) has now fired twice; free tier = Slack + email only, so Slack mobile push is the $0 page. `push` is probed at apply on one monitor first (vendor-refusal reverts cleanly — #7798 precedent). |
| Escalation policies | Stay gated off (`var.betterstack_paid_tier` unset) | Escalation requires Responder; not purchased. Recorded in ADR. |
| Restart autonomy | **Bounded auto-restart watchdog** | The failure signature is proven twice and restart is the only recovery; a page-then-approve loop still waits on a human who may be asleep — the exact gap this incident exposed. Mirroring `scheduled-inngest-health.yml` (classifier + cooldown + dedup + audit issue). Deviation from `hr-menu-option-ack-not-prod-write-auth` recorded expressly in the ADR (CLO condition; ADR-079/ADR-248 precedent). |
| Restart substrate | **Scheduled GHA workflow** (not Inngest cron) | The app container deliberately holds no Management PAT (`cron-supabase-disk-io.ts` comment); CI already calls the Management API (`scheduled-inngest-health.yml`, `apply-inngest-rls.yml`) — no credential-surface widening. |
| Restart trigger condition | Signature-only: `db`+`auth`+`rest` UNHEALTHY while pooler stays ACTIVE_HEALTHY, sustained ≥3 reads | `probe_unavailable`/ambiguous states never restart; worst false-positive cost is ~6 min of restart downtime on an already-down service. |
| Compute | **Micro → Small via `supabase/supabase` Terraform provider** (+$5/mo net) | Provider supports `supabase_project.instance_size` (verified v1.9+ registry docs) — IaC-compliant, no dashboard deviation. Chosen by operator as mitigation alongside the ticket, not as diagnosis. |
| Supabase support ticket | **Draft committed in-repo; operator submits via dashboard** | No ticket API on Pro; submission is a credential-entry operator step. Draft carries both incident windows, log signature, restart timestamps, minimized log excerpts (CLO Art. 5(1)(c) guidance). |
| 09-28 postmortem | **Written in this PR** | 09-15 got one; the ticket's evidence pack needs it anyway (COO). |
| Status page | **No work** — already live | Operator corrected the "never-shipped" premise: `soleur-ai.betteruptime.com` is live and recorded today's 39-min incident. Discoverability gap (nothing user-facing links to it) filed as follow-up. |

## Key Decisions

1. Slack integration is the paging channel; native Better Stack Slack
   integration via dashboard OAuth (operator step — credential consent, same
   class as the `betteruptime_team_member.ops` invite at `uptime-alerts.tf`).
   `betteruptime_outgoing_webhook` exists only as a comment mention; the raw
   webhook payload isn't Slack-compatible, and there is no TF-managed Slack
   resource — dashboard step is the honest path.
2. `push = true` is flipped on `app_health` alone first; vendor refusal on this
   plan reverts it. Fleet-wide sweep only if the measure lands.
3. Auto-restart watchdog = new scheduled workflow + extracted unit-tested
   classifier script + cooldown/dedup + `auto`-filed audit issue + Sentry
   heartbeat. Restart requires the full proven signature sustained over ≥3
   consecutive reads.
4. `supabase/supabase` provider declared in `apps/web-platform/infra/`; project
   imported pinned to live `instance_size = "micro"` (zero-diff); the
   `"small"` flip is a follow-up PR applied while the operator watches.
   `SUPABASE_ACCESS_TOKEN` already exists in Doppler `prd` and `prd_terraform`.
5. ADR-259 (provisional — 256/257/258 got claimed by siblings during this session; ship gate re-verifies) records: Slack-vs-Responder
   deferral discharge, the bounded auto-restart authorization model + circuit
   breaker, Art. 32(1)(c) rationale (CLO), compute-size rationale, and the
   #7529 Better Stack DPA note.
6. New `betteruptime` resources/changes update the `-target` allowlist in
   `apply-web-platform-infra.yml` (parity gate: `terraform-target-parity.test.ts`)
   and the runbook's "which alarm" table.

## Open Questions

- Does the account's existing $68/mo Better Stack Logs plan already include
  Uptime-side Responder features (push/escalation)? Unverifiable via read-only
  API — measured empirically at the `push = true` apply; if it lands, setting
  `var.betterstack_paid_tier = true` later arms the already-wired policies at
  $0 marginal cost.
- Did `ops@jikigai.com` accept the Better Stack team invite? If pending,
  operator re-accepts from the invite email (checklist item, not a blocker —
  Slack path is independent of it).
- Supabase support response may change the compute story — if support names a
  platform fault class that compute can't fix, Small stays as headroom and the
  ADR records why.
- Status page: already live AND already linked — the dashboard nav carries a
  "Status" link to `soleur-ai.betteruptime.com`
  (`apps/web-platform/app/(dashboard)/dashboard-shell.tsx`). An initial
  discoverability-gap claim + follow-up issue (#9186) were filed on the stale
  premise and retracted/closed after operator correction.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** GO with conditions — the brand damage is the silence, not the 37
minutes; a second undetected outage in 13 days for an autonomous-engineering
product is the worst shape. Buy a paging path now (Slack-push acceptable), gate
compute spend on ticket findings, and note the status page exists (operator
confirmed live during brainstorm).

### Legal (CLO)

**Summary:** GO with conditions — no SLA exists in ToS §10.2 and this is
compliance-positive under GDPR Art. 32(1)(c) (timely restoration). ADR must
record the restart-authorization delegation, an audit trail, and a circuit
breaker; support ticket applies log minimization; Better Stack DPA is unsigned
(#7529) — flagged, not blocking.

### Engineering (CTO)

**Summary:** GO with conditions — Slack integration is the $0 paging path;
`push` flip is measure-first on `app_health` alone; bounded auto-restart is
safe on the proven signature via a GH-workflow watchdog (never Inngest — the
container holds no Management PAT); compute upgrade is mitigation, not fix.

### Operations (COO)

**Summary:** GO with conditions — the `expenses.md` Responder deferral trigger
fired (operator chose the $0 Slack path anyway — recorded); Small compute is
defensible mitigation at +$5/mo; operator-side steps are the Supabase ticket
submission, the Slack OAuth consent, and the ops@ invite acceptance; **no
09-28 postmortem existed** — written in this PR.

## Capability Gaps

- **No Terraform-managed Slack integration for Better Stack.** Evidence:
  `git grep -oE "betteruptime_[a-z_]+" -- apps/web-platform/infra/` lists
  monitor/heartbeat/policy/team_member only; `betteruptime_outgoing_webhook`
  appears once as a comment (`uptime-alerts.tf:464`); `GET
  /api/v2/slack-integrations` returns `{"data":[]}` — no integration exists
  live either. Resolution: dashboard OAuth step (operator).
- **No Supabase restart automation.** Evidence: `git grep -lEi
  "supabase.*restart|restart.*supabase" -- apps/ scripts/` → no restart path;
  `postgrest-reload-schema.sh` is the nearest Management-API write precedent
  (pinned host, bearer-on-stdin). The watchdog workflow is the gap-closing
  build.

## Session Errors

- I asserted "no Supabase Terraform provider" during the compute question —
  wrong; `supabase/supabase` exists and manages `instance_size`. Corrected
  against live registry docs (v1.9+ shows `instance_size` on
  `supabase_project`, applied via the billing/addons PATCH).
- I asserted the status page was "decided but never shipped" — wrong;
  `soleur-ai.betteruptime.com` is live and recorded today's incident. The
  archived spec's `Issue: TBD` field was the stale signal.
