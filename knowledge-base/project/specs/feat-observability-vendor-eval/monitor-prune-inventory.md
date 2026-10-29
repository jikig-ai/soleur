---
title: Sentry cron-monitor prune inventory (live-vs-declared)
date: 2026-10-29
method: static repo diff — declared `sentry_cron_monitor.name` attrs vs producer slugs (Inngest SENTRY_MONITOR_SLUG consts, GHA sentry-heartbeat `slug:` params, host-script `/cron/<slug>/` URLs)
---

# Monitor prune inventory

## Measured state (2026-10-29, worktree feat-observability-vendor-eval)

- **67** declared `sentry_cron_monitor` resources (`infra/sentry/cron-monitors.tf`)
- **~97** producer slugs found repo-wide: 45 `SENTRY_MONITOR_SLUG` consts in
  `server/inngest/`, 22 `slug:` params across `.github/workflows/` +
  composite action, ~30 host-script check-in URLs (some extraction noise —
  single-word fragments discarded)
- **Declared with NO repo-visible producer: 1** — `cron-egress-resolve`.
  `infra/cron-egress-resolve.sh` exists and emits to Sentry (54 refs) but its
  check-in slug was not statically resolvable — likely env-var derived.
  **Verify live before any delete** (`sentry-monitors-audit.sh` +
  Sentry API), do not trust this single row.

## Consequence: prune is value-based, not orphan-based

Essentially every declared monitor has a live producer — the earlier "~23
orphans" hypothesis is refuted. Pruning therefore proceeds per #6590's
criterion: keep monitors **where silence is undetectable elsewhere** OR
**with demonstrated catch value** (#6591 evidence — needs Sentry API
checkin/issue history, a credential-bearing read for the execution session).

## KEEP candidates (silence undetectable elsewhere / watchdog-of-watchdog)

Per file-header cohort comments + ADR-218 doctrine — verify against #6591
catch-value before final list:

- `scheduled_oauth_probe` — OAuth canary, load-bearing Art.33-adjacent
- `scheduled_github_app_drift_guard` — register-cited Art. 33 primitive
  (spec NG5: do not touch)
- `scheduled_inngest_health`, `zot_restart_loop_alarm` — substrate-liveness
- `cron_*` host-watchdog monitors (`cron_egress_resolve` pending verify,
  `cron_workspace_sync_health`, `cron_email_ingress_probe`,
  `cron_github_cidr_refresh`, `cron_kb_template_health`,
  `cron_weekly_release_digest`, `cron_action_required_sla`)
- `main_health_monitor`, `image_cve_scan` — release/security line

## Candidate prune classes (needs #6591 catch-value per monitor)

- **CLAUDE-EVAL cohort (12 monitors)** — `scheduled_bug_fixer`,
  `scheduled_community_monitor`, `scheduled_roadmap_review`,
  `scheduled_legal_audit`, `scheduled_agent_native_audit`,
  `scheduled_competitive_analysis`, `scheduled_content_generator`,
  `scheduled_ux_audit`, `scheduled_campaign_calendar`,
  `scheduled_growth_audit`, `scheduled_growth_execution`,
  `scheduled_seo_aeo_audit` — each misses a weekly/monthly content run whose
  silence is already visible in its output artifacts (digests/issues it
  files). ~$9.36/mo.
- **Routine scheduled-* fleet** (~40 remaining) — triage per catch-value:
  monitors that have never fired a real miss AND whose cron produces a
  visible artifact (issue, comment, PR) are prune candidates.

## Next-step requirements (execution session)

1. `SENTRY_IAC_AUTH_TOKEN` (Doppler prd) → run `sentry-monitors-audit.sh`
   live: confirm `cron-egress-resolve` slug mapping + last-checkin dates.
2. Pull per-monitor incident history (Sentry API) for #6591 catch-value —
   drives final keep/delete list.
3. Any monitor deleted MUST have a surviving-signal citation in this doc
   before its TF block is removed.
