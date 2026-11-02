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

## Live API pass (2026-10-29) — verdict

`sentry-monitors-audit.sh` against `jikigai-eu.sentry.io` with
`SENTRY_IAC_AUTH_TOKEN`: **67 live monitors == 67 declared** (0 Class A/B/C
orphans; Class D unresolved without a state file — no undeclared monitors
expected). 6 muted (see below). Per-monitor 90-day `/stats/` pulled:
ok/error/missed/timeout totals informed the verdicts below.

`cron-egress-resolve` RESOLVED: live slug exists, actively checking in
(~85k ok + 517 err / 90d — per-minute cadence). The static unmatch was
extraction noise, not a dead producer. **KEEP.**

### Prune criterion applied (#6590)

Keep a monitor only where the cron's **silence is undetectable elsewhere
AND dangerous**: substrate/watchdog/wake-path monitors, product-function
host crons, and security lines. A cron that fails loudly throws to Sentry
errors for free; a cron whose silence is artifact-visible (digests,
reports, filed issues) or covered by a downstream pager does not earn a
$0.78/mo seat. Catch-value (missed/error checkins in 90d) breaks ties:
never-fired monitors prune first.

### KEEP — 24 (silence undetectable + dangerous)

| monitor | keep reason |
|---|---|
| scheduled_github_app_drift_guard | Art. 33 latency primitive, register-cited (#6590 hard constraint, spec NG5) |
| scheduled_oauth_probe | OAuth canary, auth substrate |
| scheduled_inngest_health | Inngest substrate liveness (274 err caught) |
| scheduled_inngest_cron_watchdog | watchdog-of-watchdog — fleet backstop for every pruned Inngest cron via EXPECTED_CRON_FUNCTIONS parity |
| scheduled_inngest_probe_heartbeat | Inngest dispatch probe |
| scheduled_supabase_watchdog | DB substrate (105 missed caught) |
| scheduled_betterstack_incident_mirror | the wake path itself |
| scheduled_sentry_alert_drift | drift gate for the Sentry alert system being pruned |
| scheduled_heartbeat_reconcile | Better Stack live-vs-declared drift gate |
| scheduled_terraform_drift | IaC drift watchdog |
| cron_egress_resolve | egress watchdog, per-minute, 517 error catches |
| main_health_monitor | main/release line (111 error catches) |
| image_cve_scan | CVE scan, security line |
| zot_restart_loop_alarm | registry substrate |
| workspaces_luks_verify | LUKS deadman silence arm (fires covered by BS journald pager) |
| workspaces_luks_verify_web2 | LUKS deadman silence arm (unrouted-map entry stays) |
| scheduled_merge_queue_stall_dispatch | merge-queue substrate (111 catches) |
| scheduled_anthropic_credit_probe | muted by #8704; checkins feed sentry_alert.anthropic_credit_exhausted — deleting it kills the alert path |
| cron_email_ingress_probe | email ingress product function |
| cron_workspace_sync_health | workspace sync product function |
| cron_kb_template_health | KB template product function |
| scheduled_membership_health | membership product function, hourly |
| scheduled_realtime_probe | realtime product-surface probe |
| scheduled_marketplace_drift | plugin delivery channel drift |

### PRUNE — 43

Surviving-signal citation per row (required before TF block removal).

| monitor | 90d ok/err/missed | surviving signal |
|---|---|---|
| scheduled_actions_queue_health | 1444/9/125 | false-page class (30-min margin jitter); queue stalls surface via inngest-health + actions behavior |
| scheduled_agent_native_audit | 1/0/0 | monthly audit report artifact |
| scheduled_anthropic_cost_report | 30/0/2 | cost report artifact; burn covered by claude_cost_daily_burn BS alert |
| scheduled_architecture_diagram_sync | 4/0/0 | weekly diagram artifact; never fired |
| scheduled_bot_pr_reaper | 338/0/27 | sentry_alert.stale_bot_pr covers stale bot PRs (its unrouted-map note); armed-PR visibility in GH |
| scheduled_bug_fixer | 30/0/2 | muted (already non-alerting); filed-PR artifacts |
| scheduled_campaign_calendar | 4/0/0 | CLAUDE-EVAL; calendar artifact |
| scheduled_cloud_task_heartbeat | 31/0/3 | beacon; cloud-task surface visible in Devin console |
| scheduled_community_monitor | 31/4/2 | CLAUDE-EVAL; digest artifacts |
| scheduled_competitive_analysis | 1/0/0 | CLAUDE-EVAL; monthly report artifact |
| scheduled_compound_promote | 10/0/0 | promotion artifacts |
| scheduled_content_generator | 7/2/1 | muted; content artifacts |
| scheduled_content_publisher | 33/0/3 | publish artifacts |
| scheduled_content_vendor_drift | 2/2/0 | vendor drift artifacts |
| scheduled_daily_triage | 30/0/2 | muted; triage artifacts |
| scheduled_devin_docs_drift | 30/0/16 | docs drift is advisory; upstream-ask tracker #8172 |
| scheduled_domain_model_drift | 4/0/0 | register artifact; never fired |
| scheduled_follow_through | 22/0/1 | muted; followthrough artifacts |
| cron_github_cidr_refresh | 30/0/2 | stale CIDRs surface via egress_gw_probe_fail/_silent Better Stack pagers |
| scheduled_growth_audit | 3/1/0 | CLAUDE-EVAL; audit artifacts |
| scheduled_growth_execution | 2/0/0 | CLAUDE-EVAL; growth artifacts |
| scheduled_integration_suites | 16/10/0 | CI suite status visible in Actions |
| scheduled_legal_audit | 1/0/0 | CLAUDE-EVAL; quarterly report artifact |
| scheduled_linkedin_token_check | 5/0/0 | LinkedIn post failures surface downstream |
| scheduled_machinery_drain | 0/6/0 | muted; drain artifacts |
| scheduled_nag_4216_readiness | 4/0/0 | readiness artifacts |
| scheduled_orphan_sweeps | 6/1/0 | orphan accumulation surfaces via drift monitors |
| scheduled_plausible_goals | 1/0/0 | goals reconciliation artifact |
| scheduled_prod_version_drift | 152/0/19 | deploy staleness visible via apply workflows + PR merge receipts |
| scheduled_roadmap_review | 4/0/0 | CLAUDE-EVAL; roadmap artifacts |
| scheduled_rule_prune | 1/0/0 | quarterly; rule-prune artifacts |
| scheduled_ruleset_bypass_audit | 29/1/2 | weekly audit; bypass state visible in GH ruleset audit trail |
| scheduled_seo_aeo_audit | 3/1/0 | CLAUDE-EVAL; audit artifacts |
| scheduled_skill_freshness | 1/0/0 | freshness artifacts |
| scheduled_stale_deferred_scope_outs | 30/0/3 | stale-deferral artifacts |
| scheduled_strategy_review | 4/0/0 | strategy artifacts |
| scheduled_supabase_advisor_scan | 30/0/2 | advisor findings artifact |
| scheduled_supabase_disk_io | 120/0/10 | disk covered by BS LUKS/disk journald pagers |
| scheduled_ux_audit | 0/0/0 | dead producer (0 checkins ever); audit artifacts |
| scheduled_weekly_analytics | 4/0/0 | analytics artifacts |
| scheduled_workspace_gc | 120/0/10 | GC consequences covered by disk pagers |
| cron_weekly_release_digest | 4/0/1 | weekly digest artifact |
| cron_action_required_sla | 4/0/1 | SLA staleness artifacts |

**Result: 67 → 24 monitors** (−43; PAYG seats 66→23 billable × $0.78 ≈
$17.94/mo vs ~$51.48). Muted-5 (bug-fixer, daily-triage, follow-through,
content-generator, machinery-drain) are inside the prune set — they were
already non-alerting; deletion is pure savings. The 6th muted monitor
(anthropic-credit-probe) stays for its checkin-fed sentry_alert.

### Sequencing (two-PR removal rule, sentry/README.md §two-PR)

- **PR A (this PR):** inventory + ADR-031 amendment + move the 43 labels
  from `sentry_alert.cron_monitor_failure.monitor_ids` to
  `cron_monitor_alert_unrouted` (reason cites #6590) + regenerated
  `alert-reference.json`. No monitor is destroyed by this PR.
- **PR B (follow-up):** delete the 43 `sentry_cron_monitor` blocks +
  their unrouted entries, plus the README-listed removal edits
  (`NON_INNGEST_MONITORS` exemption, `[ack-destroy]` commit trailer,
  count citations in README/audit-script comment/model.c4+likec4.json).
