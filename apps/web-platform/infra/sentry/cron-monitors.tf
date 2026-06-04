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
  checkin_margin_minutes  = 30
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
# fields in place: tightens checkin_margin (60→30 min, Inngest-fired
# precedent) and raises max_runtime (10→55 min, claude-eval cohort budget
# mirroring scheduled_bug_fixer/scheduled_roadmap_review/scheduled_legal_audit/
# scheduled_agent_native_audit/scheduled_competitive_analysis).
resource "sentry_cron_monitor" "scheduled_community_monitor" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-community-monitor"
  schedule                = { crontab = "0 8 * * *" }
  checkin_margin_minutes  = 30
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
# Weekly Monday 09:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent (scheduled_daily_triage, scheduled_follow_through,
# scheduled_bug_fixer, scheduled_strategy_review); tighter than the GHA-era
# 240-min margin (cf. scheduled_gh_pages_cert_state) because Inngest has
# minimal jitter. Single-miss alert (failure_issue_threshold=1): a single
# missed Monday is noteworthy on a weekly cadence.
resource "sentry_cron_monitor" "scheduled_roadmap_review" {
  organization           = var.sentry_org
  project                = data.sentry_project.web_platform.slug
  name                   = "scheduled-roadmap-review"
  schedule               = { crontab = "0 9 * * 1" }
  checkin_margin_minutes = 30
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
# Quarterly Jan/Apr/Jul/Oct 1 @ 11:00 UTC. Inngest-fired (not GHA) — 30-min
# margin per the Inngest-fired precedent (scheduled_daily_triage,
# scheduled_follow_through, scheduled_bug_fixer, scheduled_strategy_review,
# scheduled_roadmap_review). Single-miss alert (failure_issue_threshold=1):
# a single missed quarter is highly noteworthy on a quarterly cadence.
# 55 min mirrors the claude-eval cohort (scheduled_bug_fixer,
# scheduled_roadmap_review) — 50-min MAX_TURN_DURATION_MS budget plus slack.
resource "sentry_cron_monitor" "scheduled_legal_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-legal-audit"
  schedule                = { crontab = "0 11 1 1,4,7,10 *" }
  checkin_margin_minutes  = 30
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
# Monthly 15th 09:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent. Single-miss alert (failure_issue_threshold=1): a
# single missed monthly run is noteworthy on a monthly cadence.
# 55 min mirrors the claude-eval cohort.
resource "sentry_cron_monitor" "scheduled_agent_native_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-agent-native-audit"
  schedule                = { crontab = "0 9 15 * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}

# TR9 PR-10 (closes #4448): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`.
# NEW monitor — no GHA-era predecessor.
# Monthly 1st @ 09:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent. Single-miss alert. 55 min mirrors the claude-eval
# cohort.
resource "sentry_cron_monitor" "scheduled_competitive_analysis" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-competitive-analysis"
  schedule                = { crontab = "0 9 1 * *" }
  checkin_margin_minutes  = 30
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
# Tue/Thu 10:00 UTC. Inngest-fired — 30-min margin per the Inngest-fired
# precedent. 55 min mirrors the claude-eval cohort (50-min MAX_TURN_DURATION_MS
# budget plus slack). Single-miss alert (failure_issue_threshold=1): a single
# missed twice-weekly fire is noteworthy.
resource "sentry_cron_monitor" "scheduled_content_generator" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-content-generator"
  schedule                = { crontab = "0 10 * * 2,4" }
  checkin_margin_minutes  = 30
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
# Monthly 1st @ 09:00 UTC. Inngest-fired (not GHA) — 30-min margin per the
# Inngest-fired precedent. Single-miss alert (failure_issue_threshold=1):
# a single missed monthly fire is noteworthy on a monthly cadence.
# 55 min mirrors the claude-eval cohort (scheduled_bug_fixer,
# scheduled_roadmap_review, scheduled_legal_audit) — 50-min
# MAX_TURN_DURATION_MS budget plus slack.
resource "sentry_cron_monitor" "scheduled_ux_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-ux-audit"
  schedule                = { crontab = "0 9 1 * *" }
  checkin_margin_minutes  = 30
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
