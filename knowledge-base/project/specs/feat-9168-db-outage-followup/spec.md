---
title: "DB-outage paging path + bounded Supabase auto-restart (#9168)"
feature: feat-9168-db-outage-followup
date: 2026-09-28
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-9168-db-outage-followup
pr: 9184
brainstorm: knowledge-base/project/brainstorms/2026-09-28-9168-db-outage-alerting-autorestart-brainstorm.md
closes: [9168]
---

# Spec: #9168 — page a human on DB outage, auto-restart on the proven signature

## Problem Statement

On 2026-09-28 the prd Supabase Postgres instance hung (second identical
incident in 13 days; first postmortem:
`knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md`).
The `app_health` Better Stack keyword monitor detected it at +7 min but its
only channel is email, so nobody was paged; recovery started ~16 min later only
because an agent happened to read `/health`. Total downtime ~37 min
(16:12Z–16:49Z). Two defects: (A) detection does not reach a human, and (B)
recovery waits on a human even though the failure signature and its remedy
(restart via Management API) are crisp and proven twice.

## Goals

- **G1.** Better Stack incidents reach the operator's phone: connect the
  native Slack integration (dashboard OAuth, operator step) so monitor
  incidents post to Slack, and measure `push = true` on `app_health` at apply
  (revert if the vendor refuses on the current plan).
- **G2.** A bounded auto-restart watchdog: scheduled GH workflow probes the
  Supabase Management API `health?services=` endpoint and issues
  `POST /v1/projects/{ref}/restart` ONLY on the proven signature —
  `db`, `auth`, `rest` UNHEALTHY while pooler reports ACTIVE/COMING_UP —
  sustained over ≥3 consecutive reads, with a cooldown/dedup window, an
  auto-filed audit issue, and a Sentry heartbeat covering the watchdog itself.
- **G3.** Compute mitigation landed IaC-compliant: declare the
  `supabase/supabase` provider in `apps/web-platform/infra/`, import the prd
  project pinned to live `instance_size = "micro"` (zero-diff import); the
  `"small"` flip lands in a follow-up PR (+$5/mo net over the Pro credit).
- **G4.** A committed Supabase support-ticket draft carrying both incident
  windows, the log signature, restart timestamps, and minimized log excerpts
  (Art. 5(1)(c) — no unbounded Postgres logs); operator submits via dashboard.
- **G5.** The 2026-09-28 postmortem is written
  (`knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-28-postmortem.md`).
- **G6.** ADR-259 records: the Slack-vs-Responder decision (expenses.md:46
  deferral trigger fired; operator chose the $0 path), the bounded auto-restart
  authorization model (express deviation from
  `hr-menu-option-ack-not-prod-write-auth`, per ADR-079/ADR-248 precedent), the
  compute rationale, and the unsigned-Better-Stack-DPA note (#7529).
- **G7.** The readiness-alarm runbook is updated: Slack as primary channel,
  auto-restart behavior, "which alarm" table stays accurate; any new
  `betteruptime` resources update the `-target` allowlist in
  `apply-web-platform-infra.yml`.

## Non-Goals

- **NG1.** No Better Stack Responder purchase (operator decision 2026-09-28;
  revisit if the Slack path proves insufficient — the recorded deferral
  trigger in `expenses.md` has fired).
- **NG2.** No fleet-wide `push = true` sweep unless the `app_health` measure
  lands; other monitors keep email+Slack.
- **NG3.** No Supabase Medium-or-larger compute; Small only.
- **NG4.** No status-page work — `soleur-ai.betteruptime.com` is already live
  and already linked from the dashboard nav
  (`apps/web-platform/app/(dashboard)/dashboard-shell.tsx`).
- **NG5.** The watchdog never restarts on ambiguous/probe-unavailable states;
  it is not a general remediation engine.
- **NG6.** No changes to the 28 Sentry email alert rules or host-level Resend
  emails (residual email-only paths acknowledged; the DB-readiness class is the
  one that has burned twice).

## Functional Requirements

- **FR1.** `uptime-alerts.tf`: `betteruptime_monitor.app_health` gains
  `push = true` (measured — if apply 422s on this plan, revert to email+Slack
  and record the measurement in the ADR/PR body).
- **FR2.** New scheduled workflow
  `.github/workflows/scheduled-supabase-watchdog.yml`: primary trigger = an
  Inngest dispatch cron (the `cron-main-health-monitor.ts` pattern — `schedule:`
  measured to drift 2–7h, ADR-248, and is kept only as fallback); `concurrency:
  supabase-watchdog` with `cancel-in-progress: false` as the mutex. Calls the
  extracted classifier script, restarts on signature+corroboration,
  files/updates a labeled audit issue, emits a Sentry heartbeat.
- **FR3.** Classifier script (e.g. `scripts/supabase-watchdog-classify.sh`,
  unit-tested): input = Management API health JSON + corroborating signal
  (app `/health` `supabase` field — the Management API is a single failure
  surface, so a second independent signal is required before a prod write);
  output = `hang-signature` | `healthy` | `ambiguous` | `probe-unavailable`.
  Restart fires only on `hang-signature` sustained ≥3 consecutive reads WITH
  corroboration (state persisted via artifact or issue label, mirroring the
  Inngest watchdog pattern).
- **FR3b.** Dark-launch: the restart write is gated behind `vars.WATCHDOG_ARMED`;
  the workflow ships detect-only first (audit issue + check-in, zero restart
  POSTs) and is armed after a validated detection/soak window
  (`wg-dark-launch-deploy-gates`).
- **FR4.** Cooldown: ≥N minutes between automated restarts (recommend 30);
  give-up: after K consecutive restart cycles without recovery, stop and page
  (Slack + issue).
- **FR5.** `supabase/supabase` provider declared; `supabase_project.prd`
  imported (`import` block + `-target` allowlist entry) **pinned to live
  values incl. `instance_size = "micro"` — zero-diff import in this PR**; the
  `"small"` flip is a deliberately-sequenced follow-up PR (operator watches
  the ~2 min resize). Rationale: an import+resize in one apply makes a failed
  read indistinguishable from a resize diff.
- **FR6.** Support-ticket draft committed at
  `knowledge-base/engineering/operations/ticket-drafts/supabase-postgres-hang-2026-09-28.md`
  (or similar), minimized logs only.
- **FR7.** Postmortem file for 2026-09-28 in the post-mortems directory,
  matching the 09-15 template, action items cross-referencing this issue.
- **FR8.** ADR-259 in `knowledge-base/engineering/architecture/decisions/`.
- **FR9.** Runbook update + `-target` allowlist parity + monitor-count drift
  guards kept green.

## Technical Requirements

- **TR1.** `SUPABASE_ACCESS_TOKEN` consumed from GitHub secrets in the workflow
  (already present per `scheduled-inngest-health.yml` usage); the app container
  gains NO new credential surface.
- **TR2.** Management API calls use the pinned-host + bearer-on-stdin transport
  (`--header @-`, `--disable`, `--noproxy '*'`) per
  `scripts/supabase-logs-query.sh` / `postgrest-reload-schema.sh`.
- **TR3.** Terraform provider `supabase/supabase` pinned to a version ≥7 days
  old; R2 backend unchanged (same root).
- **TR4.** Observability: watchdog failures must surface via Sentry heartbeat +
  the audit-issue stream (hr-observability-layer-citation — cite the layer in
  the plan's Observability block).
- **TR5.** All new shell/TS test files follow the repo's existing test
  conventions; classifier is unit-tested including the "probe-unavailable
  never restarts" case.

## Operator Steps (credential-entry only)

1. Connect Better Stack → Slack in the dashboard (one-time OAuth; Slack is the
   account's existing workspace used by release notifications).
2. Submit the committed support-ticket draft via the Supabase dashboard.
3. Confirm the `ops@jikigai.com` Better Stack invite was accepted (re-accept if
   pending).
4. Complete the Small compute upgrade apply if it requires a window (est. ~2
   min downtime).

## Acceptance Criteria

- AC1: A simulated `app_health` failure produces a Slack message (verified at
  post-merge verification).
- AC2: Watchdog classifies the documented 09-28 signature as `hang-signature`
  and `probe-unavailable`/partial states as non-restartable (unit tests).
- AC3: `terraform plan` shows `supabase_project` imported pinned to live
  values (expected "1 to import", zero diff); apply lands without touching
  unrelated resources (`-target` discipline). The `small` flip is a follow-up
  PR.
- AC4: Postmortem, ticket draft, ADR-259, runbook update committed; issue
  #9168 links all artifacts.
- AC5: No new secrets introduced; `SUPABASE_ACCESS_TOKEN` reuse only.
