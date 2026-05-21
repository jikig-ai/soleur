# Cron monitors for the 8 currently-scheduled GitHub Actions workflows that
# touch secrets. Closes #3236 (vendor-hosted dead-man's-switch). The plan
# enumerated 9 workflows; `scheduled-cf-token-expiry-check` is deferred
# this cycle (its `schedule:` block is commented out — see the
# breadcrumb-only resource gap at lines 50-56). Re-introduce a 9th
# resource when that workflow's schedule lands.
#
# Sentry derives the monitor slug
# from `name` (slugified); we use the workflow filename without `.yml` so
# the slug matches the MONITOR_SLUG env var in each workflow's check-in
# steps (Phase 4).
#
# AUTO-CREATED on push to main via .github/workflows/apply-sentry-infra.yml
# (Phase 5.5) — this closes the window between Phase 4 check-in steps
# shipping and the monitors existing in Sentry.
#
# Per-workflow grace periods (checkin_margin_minutes / max_runtime_minutes)
# come from observed run history. TBD entries fall back to 60/15 defaults
# until the operator captures real medians via `gh run list`.
#
# All monitors use UTC timezone — workflow cron expressions are UTC by GHA
# convention.
#
# `failure_issue_threshold` default is 1 (single missed check-in opens an
# issue). One remaining exception (`scheduled_github_app_drift_guard`, set
# to 2) is still GHA-fired hourly, where a single transient network hiccup
# is more likely than a real failure — requiring two consecutive misses
# raises the noise floor without losing the signal. TR9 PR-4 follow-up
# tracks migrating this last hourly monitor off GHA; at that point the
# exception dissolves. All other monitors fire daily/weekly where a single
# miss is itself noteworthy.
#
# `checkin_margin_minutes` is sized per-substrate. GHA-fired monitors must
# accommodate observed GHA hourly-cron drift (~150-min median / 293-min
# max in the May 18-21 2026 window — far beyond the "~10-30 min daytime
# jitter" model) — see the drift-guard resource below. Inngest-fired
# monitors (`scheduled_oauth_probe`, `scheduled_daily_triage`,
# `scheduled_follow_through`) fire deterministically with ≤2-min jitter,
# so a 30-min margin is honest. TR9 PR-3 (#4211) migrated oauth-probe to
# the Inngest substrate per the PR-1 (#3985) / PR-2 (#4062) precedent;
# TR9 PR-4 tracks drift-guard.
#
# `max_runtime_minutes` only matters for two-step (in_progress -> ok/error)
# check-ins where Sentry can detect a job exceeding its declared budget.
# All monitors currently defined here use a single end-of-job heartbeat
# (oauth-probe + 7 sister workflows post-rollout), so this field is
# decorative — only missed-run detection is in play. Retain the value
# for schema/sibling consistency and as a future-compat default if any
# monitor migrates back to the two-step pattern. If a new monitor lands
# in two-step shape (e.g. scheduled-cf-token-expiry-check per the gap at
# lines 71-77), update this prose AND verify the field becomes load-
# bearing for the new resource.

resource "sentry_cron_monitor" "scheduled_terraform_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-terraform-drift"
  schedule                = { crontab = "0 6,18 * * *" }
  checkin_margin_minutes  = 180
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-3 (#4211): now Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`.
# The GHA scheduled-oauth-probe workflow was deleted in the same commit
# per TR9 I-13 hygiene. Margin / threshold revert to the honest
# 30 / 1 values used by sibling Inngest monitors (`scheduled_daily_triage`,
# `scheduled_follow_through`) — Inngest fires deterministically with ≤2-min
# jitter, so a 30-min margin is real, not a GHA-jitter-cover decorative
# value. The previous 360 / 2 bump (PR #4207, 2026-05-21) was immediate-
# relief while the GHA substrate was the firing path; ADR-030 + ADR-033
# precedent (PR-1 #3985, PR-2 #4062) shows the post-Inngest target.
# Resource id, `name`, and Sentry monitor slug UNCHANGED — historical
# check-in continuity preserved.
resource "sentry_cron_monitor" "scheduled_oauth_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-oauth-probe"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# scheduled-cf-token-expiry-check: NOT wired this cycle. The workflow's
# `schedule:` block is currently commented out (manual-dispatch only —
# waiting on end-to-end validation per its own header). A cron monitor
# with no firing workflow would surface a permanent "missed check-in"
# false-positive page every Monday. Re-introduce this resource when the
# workflow's schedule line lands in `.github/workflows/scheduled-cf-token-
# expiry-check.yml` lines 13-15.

# Margin bumped 180 → 360 on 2026-05-21: hourly GHA-cron substrate drifts
# to ~150-min median / ~307-min max in the observed May 18-21 window —
# 180 was silently absorbing misses below `failure_issue_threshold = 2`;
# 360 preempts the next regression-issue fire. TR9 PR-4 follow-up tracks
# migrating this monitor to the Inngest cron substrate (per the
# `scheduled_oauth_probe` precedent above, where TR9 PR-3 #4211 dropped
# margin back to 30 once on Inngest). Once that lands, the 360 / 2 values
# revert to 30 / 1 and the joint-exception breadcrumb above can drop the
# last named exception.
resource "sentry_cron_monitor" "scheduled_github_app_drift_guard" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-github-app-drift-guard"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 360
  max_runtime_minutes     = 10
  failure_issue_threshold = 2
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_daily_triage" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "scheduled-daily-triage"
  schedule     = { crontab = "0 4 * * *" }
  # TR9 PR-1 (#3948): tightened from 240 min (GHA-era jitter tolerance) to
  # 30 min after migration to Inngest cron (cron-daily-triage.ts). Inngest
  # fires at most once per scheduled time with minimal jitter, vs GHA's
  # sub-hourly runner-pool degradation of ~60 min daytime / longer overnight.
  # Resource id, `name`, and Sentry slug UNCHANGED — historical check-in
  # continuity preserved.
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_follow_through" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "scheduled-follow-through"
  schedule     = { crontab = "0 9 * * 1-5" }
  # TR9 PR-2 (#4063): NEW Inngest-fired monitor for cron-follow-through-monitor.ts.
  # 30-min margin per Inngest-fired precedent (scheduled_daily_triage above + PR-γ
  # #4006's scheduled_gh_pages_cert_state). Weekday-only DOW range (1-5) is honored
  # by Sentry's croniter-backed missed-checkin algorithm AND the jianyuan/sentry
  # provider passes the crontab through verbatim (verified at Phase 0.4 of the plan
  # via gh search against the provider's internal/provider/resource_cron_monitor_impl.go
  # — Schedule: inSchedule.Crontab.Get()). Weekend gap is expected silence, not a
  # false missed-checkin alert.
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_realtime_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-realtime-probe"
  schedule                = { crontab = "0 7 * * *" }
  checkin_margin_minutes  = 180
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_skill_freshness" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-skill-freshness"
  schedule                = { crontab = "0 2 1 * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_content_vendor_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-content-vendor-drift"
  schedule                = { crontab = "17 11 * * MON" }
  checkin_margin_minutes  = 90
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_community_monitor" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-community-monitor"
  schedule                = { crontab = "0 8 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# scheduled-gh-pages-cert-state: daily 03:00 UTC poll of GitHub Pages cert
# state for soleur.ai. Closes the gap exposed by the 2026-05-18 silent
# cert-expiry outage (PR #3974 + PR #3986 + issue #3976). Daily cadence
# leaves >2 weeks operator response on a single missed fire; the 240-
# minute `checkin_margin_minutes` absorbs GHA cron jitter — this monitor
# is GHA-fired (not Inngest), so the legacy GHA-jitter tolerance applies
# (cf. `scheduled-daily-triage` which tightened to 30 min after its
# Inngest migration in TR9 PR-1 #3985 — Inngest-fired monitors do NOT
# need the 240-min margin).
# `failure_issue_threshold = 1` because a single miss on a daily monitor
# is itself noteworthy.
resource "sentry_cron_monitor" "scheduled_gh_pages_cert_state" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-gh-pages-cert-state"
  schedule                = { crontab = "0 3 * * *" }
  checkin_margin_minutes  = 240
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
