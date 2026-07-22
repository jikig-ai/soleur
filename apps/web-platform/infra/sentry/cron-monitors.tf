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
# issue). All hourly Inngest-fired monitors use 1; daily/weekly monitors
# use 1 because a single miss on a daily monitor is itself noteworthy.
#
# `checkin_margin_minutes` is sized per-substrate. All hourly cron monitors
# are now Inngest-fired (`scheduled_oauth_probe`, `scheduled_github_app_drift_guard`)
# and use a 30-min margin — Inngest fires deterministically with ≤2-min
# jitter, so 30 is honest. Daily/weekly monitors use 30-240 min as their
# observed jitter dictates. The TR9 substrate-migration sequence completed
# the move off GHA hourly cron: PR-1 #3985 (daily-triage), PR-2 #4062
# (follow-through), PR-3 #4227 closing issue #4211 (oauth-probe), PR-4
# closing issue #4235 (github-app-drift-guard).
#
# CLAUDE-EVAL COHORT — 60-min margin (NOT 30). The 12 `max_runtime_minutes = 55`
# monitors (scheduled_bug_fixer, scheduled_community_monitor, scheduled_roadmap_review,
# scheduled_legal_audit, scheduled_agent_native_audit, scheduled_competitive_analysis,
# scheduled_content_generator, scheduled_ux_audit, scheduled_campaign_calendar,
# scheduled_growth_audit, scheduled_growth_execution, scheduled_seo_aeo_audit) post a
# SINGLE end-of-run Sentry heartbeat (`_cron-claude-eval-substrate.ts` → handler step 4
# `sentry-heartbeat`) AFTER a `claude --print` run whose budget is 50 min
# (`MAX_TURN_DURATION_MS = 50 * 60 * 1000`) plus token-mint + depth-1 clone + workspace
# teardown overhead (~5-10 min). So a fully SUCCESSFUL run lands its check-in up to ~60 min
# after the scheduled fire — a 30-min margin false-pages "missed check-in" on success. This
# is exactly the false positive that paged for scheduled-agent-native-audit on 2026-06-15
# (the run filed issue #5318 at 09:09 UTC; only the end-of-run heartbeat was late). 60 =
# 50-min budget + setup/teardown slack; it stays far under every cohort monitor's inter-fire
# gap (the tightest cohort cadences are twice-weekly / weekly / monthly — all ≥ 1 day), so a
# maximally-late run is never misread as a missed NEXT run, and a genuinely dead cron still
# pages within ~1h. `cron-inngest-cron-watchdog` (`scheduled_inngest_cron_watchdog` liveness
# beacon + the parity-guarded `EXPECTED_CRON_FUNCTIONS` manifest) remains the not-firing
# backstop. NOTE: the small-cron / pure-TS Inngest crons keep the 30-min margin — only the
# single-end-of-run-heartbeat-after-a-50-min-budget shape warrants 60.
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

# scheduled-terraform-drift is now Inngest-DISPATCHED, not GHA-`schedule:`-fired.
# An Inngest cron (apps/web-platform/server/inngest/functions/cron-terraform-drift.ts,
# `0 6,18 * * *`, ≤2-min jitter) triggers the scheduled-terraform-drift GHA
# workflow via workflow_dispatch; the GHA run still executes terraform and emits
# this monitor's end-of-job heartbeat (the Inngest fn does NOT check in here).
# Because Inngest replaces GHA's jittery `schedule:` trigger, the margin tightens
# 480 -> 60: Inngest fire (≤2 min) + dispatch (seconds) + runner queue + terraform
# (~2-3 min) lands the check-in ~5-10 min after schedule, so 60 min is comfortable
# headroom while staying far under the 720-min inter-fire gap (06:00 -> 18:00) —
# a maximally-late run of one slot is never misread as a missed run of the next,
# and a genuinely dropped run still pages within 60 min instead of up to 8h.
# This supersedes the GHA-schedule-jitter rationale that justified 480 in PR #4772
# (which widened 180 -> 480 to absorb the jitter this PR removes at its source).
# The dispatcher's OWN liveness is covered by cron-inngest-cron-watchdog (the
# parity-guarded EXPECTED_CRON_FUNCTIONS manifest), not a second monitor.
# Executor liveness for the weekly action-required SLA staleness cron (#6836). The
# DISPATCHER (cron-action-required-sla.ts) heartbeats this slug; the event-fired WORKER
# (sla-issue-process.ts) has NO monitor by design (no cadence → a crontab monitor would
# page MISSED forever). Weekly Fri 12:00 UTC; 60-min margin per the Inngest-dispatch cohort.
resource "sentry_cron_monitor" "cron_action_required_sla" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-action-required-sla"
  schedule                = { crontab = "0 12 * * 5" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "scheduled_terraform_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-terraform-drift"
  schedule                = { crontab = "0 6,18 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Executor liveness for the weekly domain-model register drift cron (#5872).
# Dispatched by apps/web-platform/server/inngest/functions/cron-domain-model-drift.ts
# (workflow_dispatch); the GHA scheduled-domain-model-drift.yml executor POSTs
# the heartbeat (ok on analyzer rc 0/1, error on rc 2/3 or an empty-stale
# anomaly). Own monitor (not Design A) because weekly-cadence absence-based
# liveness is too weak — a broken executor that files nothing would be invisible
# for up to 7 days. Margin 60 min matches the Inngest-dispatch cohort convention.
resource "sentry_cron_monitor" "scheduled_domain_model_drift" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-domain-model-drift"
  schedule                = { crontab = "0 8 * * 1" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-3 (closes #4211): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`. The GHA
# scheduled-oauth-probe workflow was deleted in the same commit per TR9 I-13
# hygiene. Resource id, `name`, and Sentry monitor slug UNCHANGED —
# historical check-in continuity preserved.
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

# #5674: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts`.
# NEW hourly 1-token canary on the operator ANTHROPIC_API_KEY — pages when the
# claude-eval fleet's credit is exhausted or the key is revoked (the 2026-06-29
# silent-fleet-down incident). It is a SMALL / pure-TS Inngest cron (no claude-eval
# spawn, no 50-min budget), so it takes the 30-min margin of the hourly small-cron
# cohort (scheduled_oauth_probe / scheduled_github_app_drift_guard / cron_kb_template
# _health), NOT the 60-min CLAUDE-EVAL COHORT. Fires at :47 (off-peak minute).
resource "sentry_cron_monitor" "scheduled_anthropic_credit_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-anthropic-credit-probe"
  schedule                = { crontab = "47 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #cost-attribution (plan Phase 3): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-anthropic-cost-report.ts`.
# Daily 06:17 UTC pull of the Anthropic Admin cost/usage API → the
# SOLEUR_CLAUDE_COST_DAILY marker. RED on a missed check-in OR a classified
# 401/403 (bad admin key). A MISSING admin key self-reports GREEN + key-missing
# marker (benign) — it does NOT flip this monitor red (obs P4). Mirrors the
# scheduled_domain_model_drift daily cohort (60-min margin, 15-min runtime).
resource "sentry_cron_monitor" "scheduled_anthropic_cost_report" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-anthropic-cost-report"
  schedule                = { crontab = "17 6 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 15
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

# TR9 PR-4 (closes #4235): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`.
# The GHA scheduled-github-app-drift-guard workflow was deleted in the same
# commit per TR9 I-13 hygiene. Resource id, `name`, and Sentry monitor slug
# UNCHANGED — historical check-in continuity preserved.
resource "sentry_cron_monitor" "scheduled_github_app_drift_guard" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-github-app-drift-guard"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #3413: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-kb-template-health.ts`.
# NEW hourly probe — no GHA-era predecessor (the issue body named a
# GitHub Actions workflow but the work landed as an Inngest cron per the
# 45-cron-vs-4-workflow precedent + ADR-030; the structural sibling is
# scheduled_github_app_drift_guard above). The slug `cron-kb-template-health`
# matches SENTRY_MONITOR_SLUG in the handler; hourly cadence + 30-min margin
# + 10-min runtime mirror the drift-guard sibling (same API-probe shape).
resource "sentry_cron_monitor" "cron_kb_template_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-kb-template-health"
  schedule                = { crontab = "0 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-5 (closes #4376): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-bug-fixer workflow was
# deleted in the same commit per TR9 I-13 hygiene.
resource "sentry_cron_monitor" "scheduled_bug_fixer" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-bug-fixer"
  schedule                = { crontab = "0 6 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
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

# scheduled-realtime-probe is GHA-fired (.github/workflows/scheduled-realtime-probe.yml,
# on.schedule "0 7 * * *"), so it is subject to GitHub Actions scheduler
# reliability gaps. On 2026-05-26 GitHub dropped the scheduled run ENTIRELY
# (not jitter — a whole missing run), which paged a "missed check-in" on
# 2026-05-28 even though the last actual run (05-27) passed 5/5. The 180-min
# margin tolerated jitter but not a dropped 24h run; widen to 1440 (24h) so a
# single dropped scheduled run does not page. A genuine realtime regression is
# still caught loudly within any run that DOES fire (the probe's own 5x
# SUBSCRIBED check files ci/realtime-broken); the margin only governs the
# missed-RUN path, which is the false-alarm source. See issue #4189.
resource "sentry_cron_monitor" "scheduled_realtime_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-realtime-probe"
  schedule                = { crontab = "0 7 * * *" }
  checkin_margin_minutes  = 1440
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

# TR9 PR-11: Inngest-fired via
# apps/web-platform/server/inngest/functions/cron-community-monitor.ts.
# Migrated from the GHA scheduled-community-monitor workflow (deleted in
# the same PR per TR9 I-13 hygiene). The Sentry monitor resource pre-
# existed (it tracked the GHA-era external heartbeat); this PR updates
# fields in place: sets checkin_margin to 60 min (claude-eval cohort margin —
# single end-of-run heartbeat after a 50-min budget; see header) and raises
# max_runtime (10→55 min, claude-eval cohort budget mirroring scheduled_bug_fixer/
# scheduled_roadmap_review/scheduled_legal_audit/scheduled_agent_native_audit/
# scheduled_competitive_analysis).
resource "sentry_cron_monitor" "scheduled_community_monitor" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-community-monitor"
  schedule                = { crontab = "0 8 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
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

# TR9 PR-6 (closes #4416): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-strategy-review workflow was
# deleted in the same commit per TR9 I-13 hygiene.
# Weekly Monday 08:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent (scheduled_daily_triage, scheduled_follow_through,
# scheduled_bug_fixer); tighter than the GHA-era 240-min margin
# (cf. scheduled_gh_pages_cert_state) because Inngest has minimal jitter.
# Single-miss alert (failure_issue_threshold=1): a single missed Monday is
# noteworthy on a weekly cadence.
resource "sentry_cron_monitor" "scheduled_strategy_review" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-strategy-review"
  schedule                = { crontab = "0 8 * * 1" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-7 (closes #4425): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-roadmap-review workflow was
# deleted in the same commit per TR9 I-13 hygiene.
# Weekly Monday 09:00 UTC. Inngest-fired (not GHA) — 60-min margin per the
# claude-eval cohort (single end-of-run heartbeat after a 50-min budget; see
# header), NOT the 30-min small-cron margin. Single-miss alert
# (failure_issue_threshold=1): a single missed Monday is noteworthy on a weekly
# cadence.
resource "sentry_cron_monitor" "scheduled_roadmap_review" {
  organization           = var.sentry_org
  project                = data.sentry_project.web_platform.slug
  name                   = "scheduled-roadmap-review"
  schedule               = { crontab = "0 9 * * 1" }
  checkin_margin_minutes = 60
  # 55 min mirrors scheduled_bug_fixer (the only other claude-eval-spawning
  # cron — both budget 50 min for MAX_TURN_DURATION_MS plus slack). NOT 10
  # like scheduled_strategy_review, which is pure-TS with a 10-min outer
  # wall-clock. Field is decorative under single-heartbeat pattern (see
  # header lines 37-46) but maintained for sibling consistency with the
  # claude-eval cohort.
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-8 (closes #4439): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-legal-audit.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-legal-audit workflow was
# deleted in the same commit per TR9 I-13 hygiene.
# Quarterly Jan/Apr/Jul/Oct 1 @ 11:00 UTC. Inngest-fired (not GHA) — 60-min
# margin per the claude-eval cohort (single end-of-run heartbeat after a 50-min
# budget; see header), NOT the 30-min small-cron margin. Single-miss alert
# (failure_issue_threshold=1): a single missed quarter is highly noteworthy on a
# quarterly cadence. 55 min mirrors the claude-eval cohort (scheduled_bug_fixer,
# scheduled_roadmap_review) — 50-min MAX_TURN_DURATION_MS budget plus slack.
resource "sentry_cron_monitor" "scheduled_legal_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-legal-audit"
  schedule                = { crontab = "0 11 1 1,4,7,10 *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-9 (closes #4442): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-agent-native-audit workflow was
# deleted in the same commit per TR9 I-13 hygiene.
# Monthly 15th 09:00 UTC. Inngest-fired (not GHA) — 60-min margin per the
# claude-eval cohort (single end-of-run heartbeat after a 50-min budget; see
# header), NOT the 30-min small-cron margin. This is the monitor that paged a
# FALSE missed-check-in on 2026-06-15 (incident 5546660): the run succeeded and
# filed #5318 at 09:09 UTC, but its end-of-run heartbeat landed after the old
# 30-min margin. Single-miss alert (failure_issue_threshold=1): a single missed
# monthly run is noteworthy on a monthly cadence. 55 min mirrors the claude-eval
# cohort.
resource "sentry_cron_monitor" "scheduled_agent_native_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-agent-native-audit"
  schedule                = { crontab = "0 9 15 * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-10 (closes #4448): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`.
# NEW monitor — no GHA-era predecessor.
# Monthly 1st @ 09:00 UTC. Inngest-fired (not GHA) — 60-min margin per the
# claude-eval cohort (single end-of-run heartbeat after a 50-min budget; see
# header), NOT the 30-min small-cron margin. Single-miss alert. 55 min mirrors
# the claude-eval cohort.
resource "sentry_cron_monitor" "scheduled_competitive_analysis" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-competitive-analysis"
  schedule                = { crontab = "0 9 1 * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 Phase 2 (#4483): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-content-generator.ts`. This
# monitor was MISSING — the function POSTed check-ins to the
# `scheduled-content-generator` slug that Sentry had never been told existed,
# so a `?status=error` heartbeat opened no issue. #4689's output-aware heartbeat
# is inert for content-generator (#4684) without this resource: the producer
# correctly resolves ok:false, but with no monitor the red signal is dropped.
# Tue/Thu 10:00 UTC. Inngest-fired — 60-min margin per the claude-eval cohort
# (single end-of-run heartbeat after a 50-min budget; see header), NOT the 30-min
# small-cron margin. 55 min mirrors the claude-eval cohort (50-min
# MAX_TURN_DURATION_MS budget plus slack). Single-miss alert
# (failure_issue_threshold=1): a single missed twice-weekly fire is noteworthy.
resource "sentry_cron_monitor" "scheduled_content_generator" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-content-generator"
  schedule                = { crontab = "0 10 * * 2,4" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# PR #4457: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`.
# Migrated from the GHA scheduled-stale-deferred-scope-outs workflow (deleted
# in the same PR). NEW monitor — no GHA-era predecessor (the GHA workflow
# shipped in PR #4452 with no Sentry check-in and was migrated before its
# first natural fire).
# Daily @ 12:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent (scheduled_daily_triage, scheduled_follow_through,
# scheduled_bug_fixer cohort). Single-miss alert (failure_issue_threshold=1):
# a single missed daily fire is noteworthy. 10 min mirrors the small-cron
# cohort (scheduled_oauth_probe, scheduled_github_app_drift_guard,
# scheduled_community_monitor) — pure-TS sweep with no claude-eval spawn.
resource "sentry_cron_monitor" "scheduled_stale_deferred_scope_outs" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-stale-deferred-scope-outs"
  schedule                = { crontab = "0 12 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-11 (Refs #3948): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`.
# NEW monitor — the GHA scheduled-compound-promote workflow ran on GHA's
# runner pool with no Sentry check-in. The GHA workflow was deleted in
# the same commit per TR9 I-13 hygiene.
# Weekly Sunday 00:00 UTC. Inngest-fired (not GHA) — 30-min margin per
# the Inngest-fired precedent. Single-miss alert. 10 min mirrors the
# small-cron cohort (pure-TS handler, no claude-eval spawn).
resource "sentry_cron_monitor" "scheduled_compound_promote" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-compound-promote"
  schedule                = { crontab = "0 0 * * 0" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-11 (#4464): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`. NEW
# monitor — the GHA scheduled-ux-audit workflow had no Sentry check-in.
# Monthly 1st @ 09:00 UTC. Inngest-fired (not GHA) — 60-min margin per the
# claude-eval cohort (single end-of-run heartbeat after a 50-min budget; see
# header), NOT the 30-min small-cron margin. Single-miss alert
# (failure_issue_threshold=1): a single missed monthly fire is noteworthy on a
# monthly cadence. 55 min mirrors the claude-eval cohort (scheduled_bug_fixer,
# scheduled_roadmap_review, scheduled_legal_audit) — 50-min
# MAX_TURN_DURATION_MS budget plus slack.
resource "sentry_cron_monitor" "scheduled_ux_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-ux-audit"
  schedule                = { crontab = "0 9 1 * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Issue #4650: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts`.
# LIVENESS BEACON (#4682 retired the self-heal). The watchdog originally queried
# the server's /v1/functions registry to classify + self-restore dropped (H9a) /
# de-planned (H9b) cron triggers, but that introspection API is loopback-gated
# and unreachable from the app container (health=200, /v1/functions=404), and the
# self-heal is redundant with --poll-interval 60 (#4652) + the per-function cron
# monitors. The function now just posts ok=true every 4h: its own check-in proves
# the inngest cron scheduler is alive enough to fire it. So THIS monitor pages
# only on a MISSED check-in (scheduler dead / function dropped), never on ok=false.
# 4-hourly (0 */4 * * *) — 120-min margin per the Inngest ≤2-min jitter.
resource "sentry_cron_monitor" "scheduled_inngest_cron_watchdog" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-inngest-cron-watchdog"
  schedule                = { crontab = "0 */4 * * *" }
  checkin_margin_minutes  = 120
  max_runtime_minutes     = 5
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6374: GHA-fired via .github/workflows/scheduled-inngest-health.yml (on.schedule
# '*/15 * * * *'). The EXTERNAL inngest health watchdog (#5542 crash-loop incident).
# This monitor was MISSING — the workflow's error heartbeat (its final step, POSTing
# ?status=error to the `scheduled-inngest-health` slug) had NO sentry_cron_monitor
# resource, so Sentry silently dropped the check-ins and the P1 [ci/inngest-down] alarm
# ran ~14h unseen (the operator was never paged). This resource closes that delivery
# gap: with failure_issue_threshold=1, a SINGLE ?status=error OR a missed check-in opens
# a Sentry monitor-failure issue → pages the operator within one cadence (~15-30 min).
#
# GHA-fired (NOT Inngest — a self-hosted inngest cron cannot detect inngest being down;
# that blind spot is the exact #5542 failure this watchdog closes; see the workflow's
# gate-override header). checkin_margin_minutes = 15 == the `*/15` inter-fire gap BY
# DESIGN (the zot_restart_loop_alarm precedent): margin == interval MAXIMIZES jitter
# tolerance (a run up to one interval late still checks in — no false page on GHA
# `schedule:` jitter), while a genuinely dark alarm (every run skipped) still pages once
# the window closes at the next expected fire. inngest-down is a brand-survival outage,
# so the margin is kept tight to the cadence rather than widened. max_runtime_minutes = 8
# matches the job's `timeout-minutes: 8`. Slug MUST match the `monitor-slug` in the
# workflow's sentry-heartbeat step (parity-asserted by
# apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts). That test no
# longer asserts membership of an apply-sentry-infra.yml `-target=` allowlist: since
# #6589 the workflow plans the full root, so declaring the resource here IS applying it.
# The slug-parity half of that test remains load-bearing — a slug that drifts from the
# workflow's `monitor-slug` still yields a monitor nothing checks into.
resource "sentry_cron_monitor" "scheduled_inngest_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-inngest-health"
  schedule                = { crontab = "*/15 * * * *" }
  checkin_margin_minutes  = 15
  max_runtime_minutes     = 8
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# 2026-06-02: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts`.
# Proactive prod Disk-IO early-warning monitor. A MISSED check-in means the
# monitor stopped (scheduler dead / function dropped); a ?status=error heartbeat
# means the monitor RAN and a tripwire fired (cache-hit floor breach, a dedup
# table over the row ceiling, or the signal RPC failed). 6-hourly (0 */6 * * *) —
# 30-min margin per the Inngest ≤2-min-jitter precedent. 10-min runtime mirrors
# the small-cron cohort (pure-TS, one read-only RPC, no claude-eval spawn). Slug
# MUST match SENTRY_MONITOR_SLUG in the handler.
resource "sentry_cron_monitor" "scheduled_supabase_disk_io" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-supabase-disk-io"
  schedule                = { crontab = "0 */6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# 2026-06-03: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts`.
# Ephemeral cron-clone garbage collector. A MISSED check-in means the GC stopped
# (scheduler dead / function dropped) — the failure mode that let leaked clones
# accumulate into the 2026-06-02 KB-sync ENOSPC freeze (#4882). The handler always
# heartbeats ok:true (the sweep RAN; a clean 0-reclaim run is healthy) — the
# actionable "volume still low after GC" condition pages via a warnSilentFallback
# Sentry warn, not a ?status=error heartbeat. 6-hourly (0 */6 * * *), 30-min margin
# + 10-min runtime mirror the disk-io small-cron cohort (pure-TS local fs, no
# claude-eval spawn). Slug MUST match SENTRY_MONITOR_SLUG in the handler.
resource "sentry_cron_monitor" "scheduled_workspace_gc" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-workspace-gc"
  schedule                = { crontab = "0 */6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #5046 PR-2 — host-side egress-allowlist re-resolve timer
# (cron-egress-resolve.timer, every 1 min). A DEAD timer freezes the
# nftables allowlist set → progressive then total container egress loss as
# SaaS IPs rotate, so missed-check-in detection is the load-bearing alarm
# (the unit's OnFailure= only fires when the service RUNS and fails — a
# hang or a never-firing timer pages ONLY here). The systemd timer is
# monotonic (OnUnitActiveSec), not wall-aligned, so check-ins drift across
# crontab windows: margin 5 + threshold 5 pages after ~10 min of true
# silence while absorbing reboot windows and per-tick jitter. Slug MUST
# match SENTRY_SLUG in cron-egress-resolve.sh and cron-egress-alarm.sh
# (parity-asserted by cron-egress-firewall.test.sh).
# feat-operator-inbox-delegation Phase 6: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts`.
# Daily email-ingress liveness probe: sends a tokenized marker email via
# Resend outbound (notifications@ → ops@), step.sleeps 15 min INSIDE the run,
# then asserts its own mail_class='probe' row landed (same-run assertion).
# Probe row found → ?status=ok; absent → ?status=error + throw (the function
# pins retries: 0 so a late-landing probe can never retry-to-green).
# checkin_margin 60 DEVIATES from the 30-min Inngest-fired precedent
# (scheduled_daily_triage cohort): the check-in lands ~16-17 min AFTER the
# scheduled fire (15-min in-run sleep + send/assert overhead), so a 30-min
# margin would leave <14 min of real headroom for redeploy windows and
# queue backpressure; 60 keeps an honest alarm within the hour while never
# paging on the structural in-run delay.
# max_runtime_minutes 25, NOT the small-cron 10: the 15-min sleep is INSIDE
# the run, so a 10-min budget would mark every single run errored.
resource "sentry_cron_monitor" "cron_email_ingress_probe" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-email-ingress-probe"
  schedule                = { crontab = "0 6 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 25
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

resource "sentry_cron_monitor" "cron_egress_resolve" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-egress-resolve"
  schedule                = { crontab = "* * * * *" }
  checkin_margin_minutes  = 5
  max_runtime_minutes     = 5
  failure_issue_threshold = 5
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #5080: Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts`.
# Weekly community release digest -> Discord #releases, Friday 15:00 UTC.
# Closest sibling: scheduled_strategy_review (pure-TS Inngest-fired cohort —
# 30-min margin, NOT the 55-min claude-eval cohort). The handler's catch
# shape always sends a check-in (ok or error); the margin is the backstop
# for the skip/heartbeat-failure paths (Sentry env unset, or the check-in
# POST itself failing — swallowed best-effort). Single-miss alert
# (failure_issue_threshold=1): one missed Friday is noteworthy on a weekly
# cadence — the digest IS the channel's only content source.
resource "sentry_cron_monitor" "cron_weekly_release_digest" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-weekly-release-digest"
  schedule                = { crontab = "0 15 * * 5" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# ---------------------------------------------------------------------------
# 2026-06-11 IaC-gap backfill (surfaced by PR #5133's AC12 verification):
# 13 Inngest crons (+ a 14th, nag-4216-readiness, surfaced by the parity
# test itself) posted heartbeats to monitor slugs that had NO
# sentry_cron_monitor resource — Sentry's check-in API silently accepts or
# drops check-ins for unknown slugs, so a dead cron in this set paged nowhere.
# One resource per code slug below; the parity test
# (apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts)
# asserts every SENTRY_MONITOR_SLUG in server/inngest/functions/ has a
# matching `name` here, so a new cron cannot ship without its monitor.
#
# Margins/runtimes follow the file's established cohorts: pure-TS/script
# Inngest crons (≤2-min jitter) get a 30-min margin + 10-15 min runtime;
# the claude-eval cohort gets a 60-min margin (single end-of-run heartbeat
# after a 50-min MAX_TURN_DURATION_MS budget + slack; see header) AND the
# 55-min runtime (mirroring scheduled_bug_fixer). The four
# Tier-2-dormant claude-spawn crons (campaign-calendar, growth-audit,
# growth-execution, seo-aeo-audit) post their deferral heartbeat on
# schedule today, so missed-check-in detection is live for them now and
# stays correctly sized for Tier-2 restoration.
# ---------------------------------------------------------------------------

# Daily 06:23 UTC — KB workspace sync-health probe (pure TS).
resource "sentry_cron_monitor" "cron_workspace_sync_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-workspace-sync-health"
  schedule                = { crontab = "23 6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Mon 16:00 UTC — claude-eval cohort (Tier-2 dormant; deferral
# heartbeat fires on schedule).
resource "sentry_cron_monitor" "scheduled_campaign_calendar" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-campaign-calendar"
  schedule                = { crontab = "0 16 * * 1" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Daily 09:30 UTC — cloud-task heartbeat aggregator (pure TS).
resource "sentry_cron_monitor" "scheduled_cloud_task_heartbeat" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-cloud-task-heartbeat"
  schedule                = { crontab = "30 9 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Daily 14:00 UTC — content publisher (spawns content-publisher.sh,
# MAX_RUN_DURATION_MS 10 min → 15-min runtime budget).
resource "sentry_cron_monitor" "scheduled_content_publisher" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-content-publisher"
  schedule                = { crontab = "0 14 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Mon 07:00 UTC — claude-eval cohort (Tier-2 dormant).
resource "sentry_cron_monitor" "scheduled_growth_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-growth-audit"
  schedule                = { crontab = "0 7 * * 1" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# 1st + 15th 10:00 UTC — claude-eval cohort (Tier-2 dormant).
resource "sentry_cron_monitor" "scheduled_growth_execution" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-growth-execution"
  schedule                = { crontab = "0 10 1,15 * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Mon 11:00 UTC — LinkedIn token expiry check (pure TS).
resource "sentry_cron_monitor" "scheduled_linkedin_token_check" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-linkedin-token-check"
  schedule                = { crontab = "0 11 * * 1" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Hourly :17 — membership-health invariant probe (pure TS, read-only RPC).
resource "sentry_cron_monitor" "scheduled_membership_health" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-membership-health"
  schedule                = { crontab = "17 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Monthly 1st 07:00 UTC — Plausible goals reconciliation (pure TS).
resource "sentry_cron_monitor" "scheduled_plausible_goals" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-plausible-goals"
  schedule                = { crontab = "0 7 1 * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Quarterly (1 Jan/Apr/Jul/Oct) 09:00 UTC — stale-rule retirement proposer
# (spawns rule-prune.sh, MAX_RUN_DURATION_MS 5 min → 10-min runtime).
resource "sentry_cron_monitor" "scheduled_rule_prune" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-rule-prune"
  schedule                = { crontab = "0 9 1 1,4,7,10 *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Daily 06:13 UTC — GitHub ruleset bypass-actor audit (pure TS).
resource "sentry_cron_monitor" "scheduled_ruleset_bypass_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-ruleset-bypass-audit"
  schedule                = { crontab = "13 6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Mon 11:00 UTC — claude-eval cohort (Tier-2 dormant).
resource "sentry_cron_monitor" "scheduled_seo_aeo_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-seo-aeo-audit"
  schedule                = { crontab = "0 11 * * 1" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Sun 02:00 UTC — architecture diagram sync (claude-eval, 60-min budget).
resource "sentry_cron_monitor" "scheduled_architecture_diagram_sync" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-architecture-diagram-sync"
  schedule                = { crontab = "0 2 * * 0" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 65
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Mon 06:00 UTC — Plausible analytics snapshot (spawns
# weekly-analytics.sh; no explicit cap → 15-min runtime budget).
resource "sentry_cron_monitor" "scheduled_weekly_analytics" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-weekly-analytics"
  schedule                = { crontab = "0 6 * * 1" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 15
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Weekly Mon 14:00 UTC — #4216 readiness nag (pure TS). Surfaced by the
# parity test below the 13-slug backfill: the initial sweep grepped only
# `SENTRY_MONITOR_SLUG = ` declarations and the readiness nag was the 14th.
resource "sentry_cron_monitor" "scheduled_nag_4216_readiness" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-nag-4216-readiness"
  schedule                = { crontab = "0 14 * * 1" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Daily 06:41 UTC — #5284 self-refreshing GitHub /meta egress CIDR generator.
# Inngest-fired via apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.ts.
# Pure-TS glue (clone + /meta fetch + shell generator + direct-merge PR on drift);
# slug MUST match SENTRY_MONITOR_SLUG in the handler and the crontab MUST match the
# handler's `{ cron: "41 6 * * *" }` trigger. 10-min runtime (small clone + one fetch).
resource "sentry_cron_monitor" "cron_github_cidr_refresh" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "cron-github-cidr-refresh"
  schedule                = { crontab = "41 6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6291: GHA-fired via .github/workflows/scheduled-zot-restart-loop.yml (on.schedule
# '*/30 * * * *'). Self-liveness for the standing zot restart-loop recurrence alarm — a MISSED
# check-in means the alarm went dark (workflow disabled / GHA outage), a ?status=error heartbeat
# means the run's checker returned TRANSIENT (a persistent Better Stack probe fault). GREEN/FIRE/
# PRODUCER-SILENT all check in ok:true (they are successful evaluations — a FIRE's surface is the
# [ci/zot-restart-loop] issue, not this monitor). GHA-fired (NOT Inngest — see the workflow's
# gate-override header: the alarm is a bash pipeline in I7's uncontained class, and the registry is
# a separate host so an Inngest cron on the watched fleet would be a dark-alarm risk).
#
# checkin_margin_minutes = 30 is PINNED (not a cohort default) to absorb GHA `schedule:` jitter: a
# tight margin on a jittery GHA cron false-paged scheduled-agent-native-audit on 2026-06-15 (the run
# succeeded and filed #5318 at 09:09 UTC; only its heartbeat was late). This monitor posts a SINGLE
# end-of-run heartbeat within ~1-2 min of the checker finishing (a small bash probe, not a claude-eval
# spawn). margin (30) == the 30-min inter-fire gap BY DESIGN: this MAXIMIZES jitter tolerance (a run
# up to 30 min late still checks in — no false page), and a genuinely dead alarm (every run skipped)
# still pages once the margin window closes at the next expected fire (~30-60 min). A SHORTER margin
# (< interval) would trade this jitter tolerance back for the 2026-06-15 false-page class — the wrong
# trade for a trust-critical standing alarm. max_runtime_minutes = 10 mirrors the
# GHA-fired small-cron cohort (scheduled_realtime_probe). Slug MUST match MONITOR_SLUG in the
# workflow's sentry-heartbeat step (scheduled-zot-restart-loop).
resource "sentry_cron_monitor" "zot_restart_loop_alarm" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-zot-restart-loop"
  schedule                = { crontab = "*/30 * * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# Executor liveness for the nightly Supabase advisor RLS gate (#3366).
# Dispatched by apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts;
# the check-in is posted at the END of .github/workflows/scheduled-supabase-advisor-scan.yml
# and ONLY for Inngest-sourced runs, so a manual smoke-test dispatch cannot forge
# liveness while the dispatcher is dead.
#
# `name` MUST stay slug-shaped: Sentry derives the monitor slug by slugifying
# `name`, and the workflow's `monitor-slug` input must equal that derived slug.
# scan-workflow.test.sh asserts the two agree.
#
# 03:37 UTC is deliberate: 20 minutes after the `17 * * * *` hourly Inngest-RLS
# self-heal, which minimizes the window in which the advisor is legitimately
# stale and the gate would have to fall back to its object-scoped carve-out.
# A MISSED check-in is what covers a dead dispatch, so the margin is what makes
# "Inngest never fired" visible rather than silent.
resource "sentry_cron_monitor" "scheduled_supabase_advisor_scan" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-supabase-advisor-scan"
  schedule                = { crontab = "37 3 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6549 item 2 — liveness for the source-vs-live Better Stack heartbeat reconcile job
# (scheduled-terraform-drift.yml → heartbeat-live-reconcile). A GHA-workflow-fired
# heartbeat (no Inngest counterpart); slug mirrors the workflow's `sentry-heartbeat`
# check-in, so sentry-monitor-iac-parity.test.ts's code→IaC GHA-slug guard is satisfied.
# checkin_margin_minutes=60 tracks the Inngest-dispatch cadence (≤2-3 min jitter), NOT
# raw GHA `schedule:` drift — mirrors scheduled_terraform_drift, the same dispatch.
resource "sentry_cron_monitor" "scheduled_heartbeat_reconcile" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-heartbeat-reconcile"
  schedule                = { crontab = "0 6,18 * * *" }
  checkin_margin_minutes  = 60
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# #6031 (ADR-088) — the scheduled-ghcr-token-minter monitor was REMOVED: the minter
# cron is disabled (ADR-088 arm-b — App installation tokens cannot pull the private
# repo-linked GHCR packages; pending GitHub-support confirmation). The handler
# no-ops under Doppler `GHCR_MINTER_DISABLED=true`, so there is nothing to monitor.
# Its slug is carried in KNOWN_UNMONITORED_SLUGS (function-registry-count.test.ts).
# Restore this block when the cron is re-enabled.
